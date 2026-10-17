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
end
