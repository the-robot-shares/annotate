defmodule Annotate.MCP.Tools.ReopenThread do
  @moduledoc false
  use Noizu.MCP.Server.Tool,
    name: "reopen_thread",
    description: "Reopen a resolved thread. Needs comments:write and site membership.",
    annotations: [
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: true,
      title: "Reopen thread"
    ],
    category: "Threads"

  alias Annotate.MCP.Tools.Helpers

  input do
    field :thread_id, :string, required: true, max_length: 64, description: "Thread id"
    field :site, :string, max_length: 128, description: "Optional site slug"
  end

  @impl true
  def call(%{thread_id: id} = args, ctx) do
    opts = [tool: "reopen_thread", scope: "comments:write", kind: :write, args: args]

    Helpers.with_thread(ctx, id, args[:site], opts, fn caller, thread ->
      Helpers.audited(caller, "reopen_thread", args, fn ->
        with {:ok, thread} <- Annotate.Comments.reopen_thread(thread) do
          {:ok, %{thread_id: thread.id, status: to_string(thread.status)}}
        end
      end)
    end)
  end
end
