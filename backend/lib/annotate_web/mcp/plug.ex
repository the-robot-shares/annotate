defmodule AnnotateWeb.MCP.Plug do
  @moduledoc """
  Endpoint-level dispatch for the MCP surface, mounted BEFORE `Plug.Parsers`
  (the Streamable HTTP transport reads the raw body) and before the CORS
  plugs (each MCP plug answers its own CORS).

  * `/.well-known/oauth-authorization-server`, `/.well-known/openid-configuration`
    — RFC 8414 AS metadata
  * `/.well-known/oauth-protected-resource[/mcp]` — RFC 9728 PRM
  * `/mcp` — Streamable HTTP, bearer-only (`Annotate.MCP.Config.transport_auth/0`)

  Options are built per request from runtime config (`Annotate.MCP.Config`),
  never at compile time. `/oauth/*` needs the session and is served later by
  `AnnotateWeb.MCP.OAuthPlug`.
  """
  @behaviour Plug

  alias Annotate.MCP.Config

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [".well-known", doc]} = conn, _opts)
      when doc in ["oauth-authorization-server", "openid-configuration"],
      do: serve(conn, Noizu.MCP.Auth.Server.MetadataPlug, Config.auth_server())

  def call(
        %Plug.Conn{path_info: [".well-known", "oauth-protected-resource" | rest]} = conn,
        _opts
      ),
      do:
        serve(
          %{conn | path_info: rest},
          Noizu.MCP.Auth.ProtectedResourceMetadataPlug,
          Config.protected_resource_metadata()
        )

  def call(%Plug.Conn{path_info: ["mcp"]} = conn, _opts) do
    conn = conn |> Plug.Conn.delete_req_header(Annotate.MCP.Scopes.header()) |> decode_body()

    serve(
      %{conn | path_info: [], script_name: conn.script_name ++ ["mcp"]},
      Noizu.MCP.Transport.StreamableHTTP.Plug,
      server: Annotate.MCP.Server,
      auth: Config.transport_auth(),
      origins: :mcp_clients,
      cors: true,
      request_timeout: 60_000,
      context: {Annotate.MCP.Context, :assigns}
    )
  end

  def call(conn, _opts), do: conn

  # Decode a POST body ONCE (the transport accepts pre-parsed `body_params`)
  # so the write-tool scope can be enforced at the HTTP layer as a 403
  # step-up. Bounded like Plug.Parsers' default (8 MB) — anything bigger or
  # malformed is left unread for the transport to reject as it always has.
  @max_body 8_000_000
  defp decode_body(%Plug.Conn{method: "POST"} = conn) do
    case Plug.Conn.read_body(conn, length: @max_body) do
      {:ok, raw, conn} ->
        case Jason.decode(raw) do
          {:ok, body} when is_map(body) or is_list(body) ->
            conn = %{conn | body_params: wrap(body), params: wrap(body)}

            case Annotate.MCP.Scopes.required(body) do
              [] ->
                conn

              scopes ->
                Plug.Conn.put_req_header(
                  conn,
                  Annotate.MCP.Scopes.header(),
                  Enum.join(scopes, " ")
                )
            end

          _ ->
            %{conn | body_params: %{"_json" => :invalid}, params: %{}}
        end

      _ ->
        conn
    end
  end

  defp decode_body(conn), do: conn

  # A JSON-RPC batch arrives as a list; Plug's convention is `%{"_json" => list}`.
  defp wrap(body) when is_map(body), do: body
  defp wrap(body) when is_list(body), do: %{"_json" => body}

  defp serve(conn, module, opts), do: conn |> module.call(module.init(opts)) |> Plug.Conn.halt()
end
