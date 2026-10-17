defmodule Annotate.MCP.Context do
  @moduledoc "Session assigns captured at MCP `initialize` (client IP for the audit log)."

  def assigns(conn), do: %{client_ip: AnnotateWeb.Plugs.RateLimit.client_ip(conn)}
end
