defmodule AnnotateWeb.MCP.OAuthFlowTest do
  @moduledoc """
  The MCP authorization server end to end through the endpoint: discovery
  documents (the library's curl checks), the 401 challenge, DCR, the
  signed-out → GitHub (stub) → return_to → consent → code → token → /mcp
  round trip, and revocation killing a live token on its next request.
  """
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.MCPCase

  describe "discovery (library curl checks)" do
    test "AS metadata advertises S256, public clients, CIMD and DCR" do
      body = build_conn() |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      assert body["issuer"] == issuer()
      assert body["code_challenge_methods_supported"] == ["S256"]
      assert "none" in body["token_endpoint_auth_methods_supported"]
      assert body["client_id_metadata_document_supported"] == true
      assert body["registration_endpoint"] == issuer() <> "/oauth/register"
      assert body["authorization_endpoint"] == issuer() <> "/oauth/authorize"
      assert "comments:write" in body["scopes_supported"]
    end

    test "openid-configuration serves the same document" do
      a = build_conn() |> get("/.well-known/oauth-authorization-server") |> json_response(200)
      b = build_conn() |> get("/.well-known/openid-configuration") |> json_response(200)
      assert a["issuer"] == b["issuer"]
    end

    test "PRM resource byte-matches the mount; one authorization server; CORS open" do
      conn = build_conn() |> get("/.well-known/oauth-protected-resource/mcp")
      body = json_response(conn, 200)
      assert body["resource"] == issuer() <> "/mcp"
      assert body["authorization_servers"] == [issuer()]
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]

      bare = build_conn() |> get("/.well-known/oauth-protected-resource") |> json_response(200)
      assert bare["resource"] == body["resource"]
    end

    test "unknown PRM suffix is a 404, never another resource's document" do
      assert get(build_conn(), "/.well-known/oauth-protected-resource/nope").status == 404
    end
  end

  describe "/mcp challenge" do
    test "unauthenticated POST → 401 + WWW-Authenticate with resource_metadata" do
      conn = mcp_post(nil, %{jsonrpc: "2.0", id: 1, method: "initialize", params: %{}})
      assert conn.status == 401
      [challenge] = get_resp_header(conn, "www-authenticate")

      assert challenge =~
               ~s(resource_metadata="#{issuer()}/.well-known/oauth-protected-resource/mcp")

      assert challenge =~ "comments:read"
    end

    test "browser preflight exposes WWW-Authenticate" do
      conn =
        build_conn()
        |> put_req_header("origin", "https://claude.ai")
        |> put_req_header("access-control-request-method", "POST")
        |> options("/mcp")

      assert conn.status in [200, 204]
      exposed = conn |> get_resp_header("access-control-expose-headers") |> Enum.join(",")
      assert String.downcase(exposed) =~ "www-authenticate"
    end

    test "garbage, wrong-audience and wrong-key tokens are 401 invalid_token" do
      user = AnnotateWeb.DashboardCase.gh_user!(9101).user
      %{token: good} = mint_token(user.id)
      assert mcp_post(good, init_body()).status == 200

      config = Annotate.MCP.Config.auth_server()

      {:ok, wrong_aud, _} =
        Noizu.MCP.Auth.Server.Tokens.mint_access_token(config, %{
          subject: user.id,
          client_id: "x",
          scope: ["comments:read"],
          resource: issuer() <> "/mcp/other"
        })

      wrong_key =
        JOSE.JWT.sign(
          JOSE.JWK.from_oct("not-the-mcp-key-not-the-mcp-key!!"),
          %{"alg" => "HS256"},
          %{
            "iss" => issuer(),
            "aud" => resource(),
            "sub" => user.id,
            "client_id" => "x",
            "jti" => "j",
            "scope" => "comments:read",
            "exp" => System.system_time(:second) + 600
          }
        )
        |> JOSE.JWS.compact()
        |> elem(1)

      for bad <- ["garbage", wrong_aud, wrong_key] do
        conn = mcp_post(bad, init_body())
        assert conn.status == 401
        assert [c] = get_resp_header(conn, "www-authenticate")
        assert c =~ "invalid_token"
      end
    end
  end

  describe "full OAuth round trip" do
    test "signed-out → GitHub → return_to → consent → code → token → /mcp; revoke kills it" do
      client_id = register_client!("Claude Code (test)")
      {verifier, challenge} = pkce()

      # 1. Signed out: authorize bounces to /sign-in with a same-origin return_to.
      conn = build_conn() |> get("/oauth/authorize?" <> authorize_query(client_id, challenge))
      login = redirected_to(conn)
      assert login =~ ~r{^/sign-in\?return_to=}
      return_to = URI.decode_query(URI.parse(login).query)["return_to"]
      assert AnnotateWeb.ReturnTo.safe(return_to) =~ ~r{^/oauth/authorize\?login_state=}

      # 2. /sign-in renders provider links carrying it.
      page = conn |> recycle() |> get(login) |> html_response(200)
      assert page =~ "return_to="

      # 3. GitHub (stub) round trip, carrying return_to.
      q =
        URI.encode_query(%{
          stub_id: 99_001,
          stub_login: "mcpowner",
          stub_email: "mcpowner@noizu.com",
          return_to: return_to
        })

      conn = conn |> recycle() |> get("/auth/github?" <> q)
      conn = conn |> recycle() |> get(redirected_to(conn))
      callback = redirected_to(conn)
      assert callback =~ "return_to="

      # 4. /auth/sso-callback issues the dashboard session and hands off to return_to.
      conn = conn |> recycle() |> get(callback)
      html = html_response(conn, 200)
      [_, target] = Regex.run(~r{http-equiv="refresh" content="0;url=([^"]+)"}, html)
      target = target |> String.replace("&amp;", "&")
      assert String.starts_with?(target, "/oauth/authorize?login_state=")

      # 5. Back at authorize, now signed in → consent screen (escaped, scoped).
      conn = conn |> recycle() |> get(target)
      consent = html_response(conn, 200)
      assert consent =~ "Claude Code (test)"
      assert consent =~ "mcpowner@noizu.com"
      assert consent =~ "comments:moderate"
      [_, csrf] = Regex.run(~r{name="csrf_token" value="([^"]+)"}, consent)
      [_, state] = Regex.run(~r{name="login_state" value="([^"]+)"}, consent)
      [_, action] = Regex.run(~r{<form method="post" action="([^"]+)"}, consent)

      # 6. Approve → code on the loopback redirect (any port).
      conn =
        conn
        |> recycle()
        |> post(URI.parse(action).path, %{
          "login_state" => state,
          "csrf_token" => csrf,
          "decision" => "approve",
          "grant_scope" => ["comments:write", "comments:moderate"]
        })

      redirect = redirected_to(conn)
      assert redirect =~ ~r{^http://localhost:53682/callback\?}
      params = URI.decode_query(URI.parse(redirect).query)
      assert params["iss"] == issuer()
      code = params["code"]

      # 7. Token exchange (no cookie, form-encoded).
      tok =
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
        |> json_response(200)

      assert tok["token_type"] in ["Bearer", "bearer"]
      assert tok["expires_in"] <= 900
      assert is_binary(tok["refresh_token"])
      access = tok["access_token"]

      # 8. /mcp accepts it.
      assert mcp_post(access, init_body()).status == 200

      # The code is single-use.
      replay =
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(
          "/oauth/token",
          URI.encode_query(%{
            grant_type: "authorization_code",
            code: code,
            redirect_uri: "http://localhost:53682/callback",
            client_id: client_id,
            code_verifier: verifier
          })
        )

      assert replay.status == 400

      # 9. Revoke from the dashboard model → the SAME access token dies now.
      user = Annotate.Repo.get_by!(Annotate.Schema.Users.User, email: "mcpowner@noizu.com")
      :ok = Annotate.MCP.Grants.revoke(user.id, client_id)
      assert mcp_post(access, init_body()).status == 401

      # …and its refresh token is dead too.
      refreshed =
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(
          "/oauth/token",
          URI.encode_query(%{
            grant_type: "refresh_token",
            refresh_token: tok["refresh_token"],
            client_id: client_id
          })
        )

      assert refreshed.status == 400
    end

    test "consent checkboxes: read-only grant → no write in the token → 403 step-up → re-consent adds write" do
      %{user: user, token: session} = AnnotateWeb.DashboardCase.gh_user!(9104)
      client_id = register_client!("Stepper")

      # Consent screen: read pre-checked + required, write/moderate opt-in, unchecked.
      %{tokens: tok, consent_html: html} = oauth_grant!(session, client_id, [])
      assert html =~ ~s(type="checkbox" checked disabled)
      assert html =~ ~s(name="grant_scope[]" value="comments:write")
      refute html =~ ~s(value="comments:write" checked)
      assert peek_claims(tok["access_token"])["scope"] == "comments:read"
      assert tok["scope"] == "comments:read"

      # A write tool → HTTP 403 insufficient_scope naming the step-up scope.
      sid = mcp_session!(tok["access_token"])

      conn =
        mcp_post(
          tok["access_token"],
          %{
            jsonrpc: "2.0",
            id: 7,
            method: "tools/call",
            params: %{name: "reply_to_thread", arguments: %{}}
          },
          sid
        )

      assert conn.status == 403
      [challenge] = get_resp_header(conn, "www-authenticate")
      assert challenge =~ ~s(error="insufficient_scope")
      assert challenge =~ "comments:write"
      assert challenge =~ "resource_metadata="

      # Read tools (and every non-write method) still pass the HTTP gate.
      ok =
        mcp_post(
          tok["access_token"],
          %{jsonrpc: "2.0", id: 8, method: "tools/list", params: %{}},
          sid
        )

      assert ok.status == 200

      # A client-forged scope header changes nothing (stripped by the plug).
      forged =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json, text/event-stream")
        |> put_req_header("authorization", "Bearer " <> tok["access_token"])
        |> put_req_header("mcp-session-id", sid)
        |> put_req_header("mcp-protocol-version", "2025-11-25")
        |> put_req_header("x-annotate-mcp-required-scope", "")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            id: 9,
            method: "tools/call",
            params: %{name: "delete_comment", arguments: %{}}
          })
        )

      assert forged.status == 403

      # Re-consent: the broadened ask re-prompts; ticking write grants it.
      %{tokens: tok2, consent_html: html2} = oauth_grant!(session, client_id, ["comments:write"])
      assert html2, "a broadened request must re-prompt"
      assert peek_claims(tok2["access_token"])["scope"] == "comments:read comments:write"

      sid2 = mcp_session!(tok2["access_token"])

      write =
        mcp_post(
          tok2["access_token"],
          %{
            jsonrpc: "2.0",
            id: 10,
            method: "tools/call",
            params: %{name: "reply_to_thread", arguments: %{}}
          },
          sid2
        )

      refute write.status == 403

      moderate =
        mcp_post(
          tok2["access_token"],
          %{
            jsonrpc: "2.0",
            id: 11,
            method: "tools/call",
            params: %{name: "delete_comment", arguments: %{}}
          },
          sid2
        )

      assert moderate.status == 403

      # /dashboard/agents data: the connection lists exactly the granted scopes.
      assert [%{client_id: ^client_id, scopes: scopes}] = Annotate.MCP.Grants.list(user.id)
      assert Enum.sort(scopes) == ["comments:read", "comments:write"]
    end

    test "a forged consent POST (bad CSRF) cannot rewrite the requested scope" do
      %{token: session} = AnnotateWeb.DashboardCase.gh_user!(9105)
      client_id = register_client!()
      {_v, challenge} = pkce()

      html =
        build_conn()
        |> init_test_session(%{"access_token" => session})
        |> get(
          "/oauth/authorize?" <>
            authorize_query(client_id, challenge, "comments:read comments:write")
        )
        |> html_response(200)

      [_, state] = Regex.run(~r{name="login_state" value="([^"]+)"}, html)

      bad =
        build_conn()
        |> init_test_session(%{"access_token" => session})
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(
          "/oauth/consent",
          URI.encode_query(%{login_state: state, csrf_token: "nope", decision: "approve"})
        )

      assert bad.status == 400
      {store, opts} = Annotate.MCP.Config.store()
      {:ok, payload} = store.get_login_state(state, opts)
      assert payload["scope"] == ["comments:read", "comments:write"]
    end

    test "a pending (invite-gated) dashboard user never reaches consent" do
      %{token: token} = AnnotateWeb.DashboardCase.gh_user!(9102, %{pending: true})
      client_id = register_client!()
      {_v, challenge} = pkce()

      conn =
        build_conn()
        |> init_test_session(%{"access_token" => token})
        |> get("/oauth/authorize?" <> authorize_query(client_id, challenge))

      refute conn.status == 200 and conn.resp_body =~ "csrf_token"
      refute conn.status == 302 and redirected_to(conn) =~ "code="
    end

    test "consent escapes a hostile client_name" do
      client_id = register_client!(~s|<script>alert(1)</script>"><img src=x>|)
      %{token: token} = AnnotateWeb.DashboardCase.gh_user!(9103)
      {_v, challenge} = pkce()

      html =
        build_conn()
        |> init_test_session(%{"access_token" => token})
        |> get("/oauth/authorize?" <> authorize_query(client_id, challenge))
        |> html_response(200)

      refute html =~ "<script>alert"
      refute html =~ "<img src=x>"
      assert html =~ "&lt;script&gt;"
    end

    test "DCR refuses a non-allowlisted https redirect host" do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(
          "/oauth/register",
          Jason.encode!(%{
            client_name: "evil",
            redirect_uris: ["https://evil.example/cb"],
            token_endpoint_auth_method: "none"
          })
        )

      assert conn.status == 400
    end
  end

  defp init_body,
    do: %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: "2025-11-25",
        capabilities: %{},
        clientInfo: %{name: "t", version: "0"}
      }
    }
end
