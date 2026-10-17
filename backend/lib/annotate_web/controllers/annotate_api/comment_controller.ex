defmodule AnnotateWeb.AnnotateAPI.CommentController do
  @moduledoc """
  Comment-level annotate endpoints (site-bound, token required):

  - `PATCH /api/v1/comments/:id` — author or site owner; sets `edited_at`.
    Optional `attachment_ids` binds new (own, ready, unbound) attachments and
    `remove_attachment_ids` detaches ones bound to this comment.
  - `DELETE /api/v1/comments/:id` — soft delete; author or site owner.
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias AnnotateWeb.AnnotateAPI.Renderer

  def update(conn, %{"body_md" => _} = params) do
    site = conn.assigns.annotate_site
    commenter = conn.assigns.annotate_commenter

    with {:ok, comment} <- comment_for(conn, params),
         :ok <- authorize(comment, site, commenter),
         :ok <- Annotate.Moderation.check_text(params["body_md"]) do
      opts = [
        attachment_ids: params["attachment_ids"],
        remove_attachment_ids: params["remove_attachment_ids"],
        commenter: commenter
      ]

      case Comments.update_comment_body(comment, params["body_md"], opts) do
        {:ok, comment} ->
          json(conn, %{
            "comment" => Renderer.comment(Annotate.Repo.preload(comment, [:author, :attachments]))
          })

        {:error, :invalid_body} ->
          conn |> put_status(:bad_request) |> json(%{"error" => "invalid_body"})

        {:error, :attachment_mismatch} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "attachment_mismatch"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
      end
    else
      {:error, :content_rejected} ->
        conn |> put_status(:unprocessable_entity) |> json(Annotate.Moderation.rejection_payload())

      {:error, %Plug.Conn{} = conn} -> conn
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def update(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "body_md_required"})
  end

  def delete(conn, params) do
    site = conn.assigns.annotate_site
    commenter = conn.assigns.annotate_commenter

    with {:ok, comment} <- comment_for(conn, params),
         :ok <- authorize_moderation(comment, site, commenter, conn.assigns[:annotate_claims]) do
      case Comments.soft_delete_comment(comment) do
        {:ok, _} ->
          send_resp(conn, :no_content, "")

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
      end
    else
      {:error, %Plug.Conn{} = conn} -> conn
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp authorize(comment, site, commenter) do
    if Comments.comment_manageable_by?(comment, site, commenter),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp authorize_moderation(comment, site, commenter, claims) do
    if Comments.comment_moderatable_by?(comment, site, commenter, claims),
      do: :ok,
      else: {:error, :forbidden}
  end

  # Visibility-gated BEFORE the author/moderator check: a comment in a thread
  # the viewer may not read (staff_only) is 404, never 403 — no existence leak.
  defp comment_for(conn, params) do
    site = conn.assigns.annotate_site

    viewer =
      Annotate.Embed.Visibility.viewer(
        site,
        conn.assigns[:annotate_commenter],
        conn.assigns[:annotate_claims]
      )

    case Comments.get_visible_comment_for_site(params["id"], site.id, viewer) do
      %Annotate.Schema.Annotate.Comment{} = comment -> {:ok, comment}
      nil -> {:error, not_found(conn)}
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "not_found"})
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{"error" => "forbidden"})
    |> halt()
  end
end
