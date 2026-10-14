defmodule AnnotateWeb.AnnotateAPI.CommentController do
  @moduledoc """
  Comment-level annotate endpoints (site-bound, token required):

  - `PATCH /api/v1/comments/:id` — author or site owner; sets `edited_at`.
  - `DELETE /api/v1/comments/:id` — soft delete; author or site owner.
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias AnnotateWeb.AnnotateAPI.Renderer

  def update(conn, %{"body_md" => _} = params) do
    site = conn.assigns.annotate_site
    commenter = conn.assigns.annotate_commenter

    with {:ok, comment} <- comment_for(conn, params),
         :ok <- authorize(comment, site, commenter) do
      case Comments.update_comment_body(comment, params["body_md"]) do
        {:ok, comment} ->
          json(conn, %{
            "comment" => Renderer.comment(Annotate.Repo.preload(comment, [:author, :attachments]))
          })

        {:error, :invalid_body} ->
          conn |> put_status(:bad_request) |> json(%{"error" => "invalid_body"})

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
      end
    else
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
         :ok <- authorize(comment, site, commenter) do
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

  defp comment_for(conn, params) do
    case Comments.get_comment_for_site(params["id"], conn.assigns.annotate_site.id) do
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
