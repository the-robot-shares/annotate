defmodule AnnotateWeb.MCPCase do
  @moduledoc """
  Helpers for the MCP server tests: a real OAuth round trip through the
  router (register → authorize → consent → token), raw JSON-RPC over `/mcp`,
  and in-process token minting through the library (`mint_token/3`) for the
  tool-contract tests.
  """

  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint AnnotateWeb.Endpoint

  def issuer, do: Annotate.MCP.Config.issuer()
  def resource, do: Annotate.MCP.Config.resource()

  def pkce do
    verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    {verifier, challenge}
  end

  @doc "DCR: register a public loopback client. Returns the client_id."
  def register_client!(name \\ "Test Agent") do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/oauth/register",
        Jason.encode!(%{
          client_name: name,
          redirect_uris: ["http://localhost/callback"],
          token_endpoint_auth_method: "none",
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"]
        })
      )

    201 = conn.status
    Jason.decode!(conn.resp_body)["client_id"]
  end

  def authorize_query(
        client_id,
        challenge,
        scope \\ "comments:read comments:write comments:moderate"
      ) do
    URI.encode_query(%{
      response_type: "code",
      client_id: client_id,
      redirect_uri: "http://localhost:53682/callback",
      code_challenge: challenge,
      code_challenge_method: "S256",
      scope: scope,
      state: "st-" <> Integer.to_string(System.unique_integer([:positive])),
      resource: resource()
    })
  end

  @doc """
  Signed-in authorize → consent (ticking `ticked` scopes) → token, for a
  dashboard session `access_token`. Returns `%{tokens, consent_html}`;
  `consent_html` is nil when consent was skipped (already granted).
  """
  def oauth_grant!(
        session_token,
        client_id,
        ticked,
        scope \\ "comments:read comments:write comments:moderate"
      ) do
    {verifier, challenge} = pkce()

    conn =
      build_conn()
      |> init_test_session(%{"access_token" => session_token})
      |> get("/oauth/authorize?" <> authorize_query(client_id, challenge, scope))

    {redirect, consent_html} =
      case conn.status do
        200 ->
          html = conn.resp_body
          [_, csrf] = Regex.run(~r{name="csrf_token" value="([^"]+)"}, html)
          [_, state] = Regex.run(~r{name="login_state" value="([^"]+)"}, html)

          body =
            URI.encode_query([
              {"login_state", state},
              {"csrf_token", csrf},
              {"decision", "approve"}
            ]) <>
              Enum.map_join(ticked, "", &("&" <> URI.encode_query([{"grant_scope[]", &1}])))

          posted =
            build_conn()
            |> init_test_session(%{"access_token" => session_token})
            |> put_req_header("content-type", "application/x-www-form-urlencoded")
            |> post("/oauth/consent", body)

          {redirected_to(posted), html}

        302 ->
          {redirected_to(conn), nil}
      end

    code = URI.decode_query(URI.parse(redirect).query)["code"] || raise "no code: #{redirect}"

    tokens =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        "/oauth/token",
        URI.encode_query(%{
          grant_type: "authorization_code",
          code: code,
          redirect_uri: "http://localhost:53682/callback",
          client_id: client_id,
          code_verifier: verifier,
          resource: resource()
        })
      )
      |> Phoenix.ConnTest.json_response(200)

    %{tokens: tokens, consent_html: consent_html}
  end

  @doc "Claims of a JWT, unverified (test inspection only)."
  def peek_claims(jwt), do: JOSE.JWT.peek_payload(jwt).fields

  @doc """
  Mint an access token straight from the library for `user_id` (the same
  path `/oauth/token` uses), with a recorded consent so the verifier accepts
  it. Returns the raw JWT.
  """
  def mint_token(user_id, scopes \\ Annotate.MCP.Config.scopes(), client_name \\ "Minted") do
    config = Annotate.MCP.Config.auth_server()
    {store, opts} = Noizu.MCP.Auth.Server.Config.store(config)
    client_id = "test-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, _} =
      store.put_client(
        %Noizu.MCP.Auth.Server.Client{
          client_id: client_id,
          client_id_kind: :preconfigured,
          client_name: client_name,
          redirect_uris: ["http://localhost/callback"],
          token_endpoint_auth_method: "none"
        },
        opts
      )

    :ok =
      Noizu.MCP.Auth.Server.Consent.record(
        %Noizu.MCP.Auth.Server.Client{client_id: client_id},
        user_id,
        scopes,
        resource(),
        config
      )

    grant = %{subject: user_id, client_id: client_id, scope: scopes, resource: resource()}
    {:ok, jwt, claims} = Noizu.MCP.Auth.Server.Tokens.mint_access_token(config, grant)
    :ok = Noizu.MCP.Auth.Server.Tokens.track_access_token(config, claims, grant)
    %{token: jwt, client_id: client_id, claims: claims}
  end

  @doc "POST one JSON-RPC message to /mcp. Returns the conn."
  def mcp_post(token, body, session_id \\ nil) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(fn c ->
      if token, do: put_req_header(c, "authorization", "Bearer " <> token), else: c
    end)
    |> then(fn c ->
      if session_id, do: put_req_header(c, "mcp-session-id", session_id), else: c
    end)
    |> then(fn c ->
      if session_id, do: put_req_header(c, "mcp-protocol-version", "2025-11-25"), else: c
    end)
    |> post("/mcp", Jason.encode!(body))
  end

  @doc "initialize + initialized; returns the session id."
  def mcp_session!(token) do
    conn =
      mcp_post(token, %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-11-25",
          capabilities: %{},
          clientInfo: %{name: "annotate-test", version: "0"}
        }
      })

    200 = conn.status
    [sid] = get_resp_header(conn, "mcp-session-id")
    202 = mcp_post(token, %{jsonrpc: "2.0", method: "notifications/initialized"}, sid).status
    sid
  end

  @doc "Decode a JSON-RPC response body (plain JSON or a single SSE `data:` frame)."
  def rpc_body(conn) do
    body = conn.resp_body

    case get_resp_header(conn, "content-type") do
      ["text/event-stream" <> _] ->
        body
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "data:"))
        |> Enum.map(&(&1 |> String.trim_leading("data:") |> String.trim() |> Jason.decode!()))
        |> Enum.find(&Map.has_key?(&1, "id"))

      _ ->
        Jason.decode!(body)
    end
  end

  @doc "tools/call → `{is_error?, structured_or_text}`."
  def call_tool(token, sid, name, args) do
    conn =
      mcp_post(
        token,
        %{
          jsonrpc: "2.0",
          id: System.unique_integer([:positive]),
          method: "tools/call",
          params: %{name: name, arguments: args}
        },
        sid
      )

    case rpc_body(conn) do
      %{"result" => %{"isError" => true, "content" => [%{"text" => text} | _]}} -> {:error, text}
      %{"result" => %{"structuredContent" => sc}} -> {:ok, sc}
      %{"result" => %{"content" => [%{"text" => text} | _]}} -> {:ok, Jason.decode!(text)}
      %{"error" => err} -> {:rpc_error, err}
      other -> {:unexpected, other, conn.status}
    end
  end
end
