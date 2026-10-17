defmodule Annotate.MCP.Tools.ListSites do
  @moduledoc false
  use Noizu.MCP.Server.Tool,
    name: "list_sites",
    description:
      "List the annotate sites you are a member of, with your role and open/resolved thread " <>
        "counts. Use a site's `slug` with the other tools. Site names are user-chosen and " <>
        "returned under `untrusted`.",
    annotations: [read_only_hint: true, idempotent_hint: true, title: "List sites"],
    category: "Sites"

  alias Annotate.MCP.Present
  alias Annotate.MCP.Tools.Helpers

  @impl true
  def call(_args, ctx) do
    Helpers.with_caller(ctx, [tool: "list_sites"], fn caller ->
      sites =
        caller
        |> Annotate.MCP.Authz.member_sites()
        |> Enum.map(fn %{site: site, role: role, member_count: count} ->
          counts = Annotate.Comments.site_thread_counts(site.id)

          Present.site(site, role, %{
            member_count: count,
            open_threads: counts.open,
            resolved_threads: counts.resolved
          })
        end)

      {:ok, %{sites: sites, note: Helpers.untrusted_note()}}
    end)
  end
end
