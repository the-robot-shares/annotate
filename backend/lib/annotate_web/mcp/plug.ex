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

  defp serve(conn, module, opts), do: conn |> module.call(module.init(opts)) |> Plug.Conn.halt()
end
