defmodule Annotate.MCP.Resources.Sites do
  @moduledoc false
  use Noizu.MCP.Server.Resource,
    uri: "annotate://sites",
    name: "My annotate sites",
    description: "Sites you are a member of (same data as the list_sites tool).",
    mime_type: "application/json"

  alias Annotate.MCP.Resources.Common

  @impl true
  def read(uri, ctx), do: Common.tool_json(uri, ctx, Annotate.MCP.Tools.ListSites, %{})
end
