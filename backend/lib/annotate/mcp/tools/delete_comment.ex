defmodule Annotate.MCP.Tools.DeleteComment do
  @moduledoc false
  use Noizu.MCP.Server.Tool,
    name: "delete_comment",
    description:
      "Delete (soft-delete) one comment: removed from the widget and the dashboard. Needs the " <>
        "comments:moderate permission; members may delete only their own team replies, admins " <>
        "and owners may delete anyone's. Destructive: confirm with the user first.",
    annotations: [
      read_only_hint: false,
      destructive_hint: true,
      idempotent_hint: true,
      title: "Delete comment"
    ],
    category: "Moderation"

  alias Annotate.MCP.Authz
  alias Annotate.MCP.Tools.Helpers

  input do
    field :comment_id, :string,
      required: true,
      max_length: 64,
      description: "Comment id (from get_thread)"

    field :site, :string, max_length: 128, description: "Optional site slug"
  end

  @impl true
  def call(%{comment_id: id} = args, ctx) do
    opts = [tool: "delete_comment", scope: "comments:moderate", kind: :write, args: args]

    pinned = args[:site]

    case Annotate.Comments.get_comment_and_site(id) do
      {comment, _thread, site} when pinned in [nil, ""] or pinned == site.slug ->
        Helpers.with_site(ctx, site.slug, opts, fn caller ->
          Helpers.audited(caller, "delete_comment", args, fn ->
            with true <-
                   Annotate.Comments.team_can_delete?(
                     comment,
                     caller.site,
                     caller.user_id,
                     caller.role
                   ) ||
                     {:error, :forbidden},
                 {:ok, comment} <- Annotate.Comments.soft_delete_comment(comment) do
              {:ok, %{comment_id: comment.id, deleted: true}}
            end
          end)
        end)

      _ ->
        Helpers.with_caller(ctx, opts, fn caller ->
          Authz.audit(caller, "delete_comment", args, "denied", :not_found)
          {:error, Authz.message(:not_found)}
        end)
    end
  end
end
