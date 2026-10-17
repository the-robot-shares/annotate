defmodule Annotate.MCP.Tools.ListThreads do
  @moduledoc false
  use Noizu.MCP.Server.Tool,
    name: "list_threads",
    description:
      "Search comment threads on one site, newest first (max 100 per page; pass `next_cursor` " <>
        "back as `cursor` for more). Filters: status, page path (exact, or prefix ending in *), " <>
        "origin, activity since, text in comments/page title, author name, orphaned anchors. " <>
        "Comment excerpts, author names, titles and URLs are visitor-written and returned " <>
        "under `untrusted`; `deep_link` is set only when the thread's URL is on one of the " <>
        "site's allowed origins.",
    annotations: [read_only_hint: true, idempotent_hint: true, title: "List threads"],
    category: "Threads"

  alias Annotate.MCP.Present
  alias Annotate.MCP.Tools.Helpers

  input do
    field :site, :string, required: true, max_length: 128, description: "Site slug"
    field :status, :enum, values: [:open, :resolved, :all], default: :open

    field :page_path, :string,
      max_length: 1024,
      description: "Exact path (/pricing) or prefix (/docs/*)"

    field :origin, :string, max_length: 300, description: "Exact origin, e.g. https://example.com"

    field :since, :string,
      max_length: 40,
      description: "ISO-8601; threads created or commented on since"

    field :text, :string,
      max_length: 200,
      description: "Substring of a comment body or page title"

    field :author, :string,
      max_length: 200,
      description: "Substring of a commenter's display name"

    field :orphaned, :boolean, description: "true = anchor lost; false = anchor found"
    field :cursor, :string, max_length: 200, description: "next_cursor from the previous page"
    field :limit, :integer, min: 1, max: 100, default: 25
  end

  @impl true
  def call(%{site: slug} = args, ctx) do
    Helpers.with_site(ctx, slug, [tool: "list_threads", args: args], fn caller ->
      with {:ok, since} <- Helpers.parse_since(args[:since]) do
        {threads, next} =
          Annotate.Comments.search_site_threads(caller.site.id,
            status: Helpers.status_atom(args[:status]),
            page_path: args[:page_path],
            origin: args[:origin],
            since: since,
            text: args[:text],
            author: args[:author],
            orphaned: args[:orphaned],
            cursor: args[:cursor],
            limit: args[:limit] || 25
          )

        {:ok,
         %{
           site: caller.site.slug,
           threads: Enum.map(threads, &Present.thread_summary(&1, caller.site)),
           next_cursor: next,
           note: Helpers.untrusted_note()
         }}
      end
    end)
  end
end
