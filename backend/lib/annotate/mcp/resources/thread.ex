defmodule Annotate.MCP.Resources.Thread do
  @moduledoc false
  use Noizu.MCP.Server.ResourceTemplate,
    uri_template: "annotate://thread/{id}",
    name: "Comment thread",
    description: "One thread with its comments (same data as get_thread).",
    mime_type: "application/json"

  alias Annotate.MCP.Resources.Common

  @impl true
  def read(uri, %{id: id}, ctx),
    do: Common.tool_json(uri, ctx, Annotate.MCP.Tools.GetThread, %{thread_id: id})
end
