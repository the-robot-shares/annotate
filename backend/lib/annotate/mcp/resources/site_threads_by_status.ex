defmodule Annotate.MCP.Resources.SiteThreadsByStatus do
  @moduledoc false
  use Noizu.MCP.Server.ResourceTemplate,
    uri_template: "annotate://site/{slug}/threads/{status}",
    name: "Threads on a site by status",
    description: "First page of threads on a site; status is open, resolved or all.",
    mime_type: "application/json"

  alias Annotate.MCP.Resources.Common

  @impl true
  def read(uri, %{slug: slug, status: status}, ctx) when status in ["open", "resolved", "all"],
    do:
      Common.tool_json(uri, ctx, Annotate.MCP.Tools.ListThreads, %{
        site: slug,
        status: String.to_existing_atom(status),
        limit: 50
      })

  def read(uri, _vars, _ctx), do: {:error, Noizu.MCP.Error.resource_not_found(uri)}
end
