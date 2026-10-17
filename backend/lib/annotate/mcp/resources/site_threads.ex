defmodule Annotate.MCP.Resources.SiteThreads do
  @moduledoc false
  use Noizu.MCP.Server.ResourceTemplate,
    uri_template: "annotate://site/{slug}/threads",
    name: "Open threads on a site",
    description: "First page of open threads on a site (list_threads, status=open).",
    mime_type: "application/json"

  alias Annotate.MCP.Resources.Common

  @impl true
  def read(uri, %{slug: slug}, ctx),
    do:
      Common.tool_json(uri, ctx, Annotate.MCP.Tools.ListThreads, %{
        site: slug,
        status: :open,
        limit: 50
      })
end
