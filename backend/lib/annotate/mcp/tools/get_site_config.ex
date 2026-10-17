defmodule Annotate.MCP.Tools.GetSiteConfig do
  @moduledoc false
  use Noizu.MCP.Server.Tool,
    name: "get_site_config",
    description:
      "Configuration summary of one site you are a member of: allowed origins (where the " <>
        "comment widget may run), read/comment policy, your role and thread counts. Never " <>
        "returns keys or secrets.",
    annotations: [read_only_hint: true, idempotent_hint: true, title: "Get site config"],
    category: "Sites"

  alias Annotate.MCP.Present
  alias Annotate.MCP.Tools.Helpers

  input do
    field :site, :string,
      required: true,
      max_length: 128,
      description: "Site slug (from list_sites)"
  end

  @impl true
  def call(%{site: slug} = args, ctx) do
    Helpers.with_site(ctx, slug, [tool: "get_site_config", args: args], fn caller ->
      counts = Annotate.Comments.site_thread_counts(caller.site.id)
      {:ok, Present.site_config(caller.site, caller.role, counts)}
    end)
  end
end
