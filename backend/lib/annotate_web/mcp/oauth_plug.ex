defmodule AnnotateWeb.MCP.OAuthPlug do
  @moduledoc """
  `/oauth/{authorize,consent,token,register,revoke}` — the noizu_mcp
  authorization server router. Mounted AFTER the session plug (authorize and
  consent read the dashboard session through `Annotate.MCP.Bridge`) and
  outside any CSRF protection (token/register/revoke are machine calls with
  no cookie; the consent form carries the library's own flow-bound CSRF
  token). Never behind a require-login pipeline: the flow itself redirects a
  signed-out user to `/sign-in?return_to=…`.

  `authorize`/`consent` get a per-IP rate limit here; the library limits
  `register` and `token` itself through `Annotate.MCP.RateLimit.oauth/3`.
  """
  @behaviour Plug
  import Plug.Conn

  @endpoints ~w(authorize consent token register revoke)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["oauth", endpoint]} = conn, _opts)
      when endpoint in @endpoints do
    conn = fetch_session(conn)

    limited =
      if endpoint in ["authorize", "consent"],
        do: Annotate.MCP.RateLimit.oauth(String.to_existing_atom(endpoint), conn, nil),
        else: :ok

    case limited do
      :ok ->
        config = Annotate.MCP.Config.auth_server()
        router = Noizu.MCP.Auth.Server.Router

        if endpoint == "consent" and conn.method == "POST", do: narrow_consent(conn, config)

        conn
        |> put_resp_header("x-robots-tag", "noindex")
        |> router.call(router.init(config))
        |> halt()

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> send_resp(429, "Too many authorization attempts; retry shortly.")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  Consent checkboxes: the user grants a SUBSET of what the client asked for.
  `comments:read` is always granted (the base scope); `comments:write` and
  `comments:moderate` only when ticked (`grant_scope[]`). Before the library
  records consent and mints the code it reads the request scope from the
  login state, so the narrowed scope is written there first — only after the
  flow's CSRF token checks out (`Noizu.MCP.Auth.Server.Consent.valid_csrf?/2`;
  the library re-checks it). The code, its tokens and the recorded consent
  then carry only the ticked scopes. Denials pass through untouched.
  """
  def narrow_consent(conn, config) do
    params = conn.body_params

    with %{"decision" => "approve", "login_state" => state} when is_binary(state) <- params,
         {store, opts} = Noizu.MCP.Auth.Server.Config.store(config),
         {:ok, payload} <- store.get_login_state(state, opts),
         true <- Noizu.MCP.Auth.Server.Consent.valid_csrf?(payload, params["csrf_token"]) do
      requested = payload |> Map.get("scope") |> List.wrap()
      _ = store.update_login_state(state, %{"scope" => granted_scopes(requested, params)}, opts)
      :ok
    else
      _ -> :ok
    end
  end

  @doc "requested ∩ ({comments:read} ∪ ticked)."
  def granted_scopes(requested, params) do
    ticked =
      case params["grant_scope"] do
        list when is_list(list) -> Enum.filter(list, &is_binary/1)
        one when is_binary(one) -> [one]
        _ -> []
      end

    allowed = [Annotate.MCP.Scopes.base() | ticked]
    Enum.filter(requested, &(&1 in allowed))
  end
end
