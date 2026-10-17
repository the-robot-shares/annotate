defmodule AnnotateWeb.AnnotateAPI.ThreadCommentsController do
  @moduledoc """
  Thread-level annotate endpoints (site-bound, token required):

  - `POST /api/v1/threads/:id/comments` (params may carry `?site=<slug>`)
  - `POST /api/v1/threads/:id/resolve` · `POST .../reopen`
  - `PATCH /api/v1/threads/:id/anchor` (re-anchor repair; clears `orphaned_at`)
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias AnnotateWeb.AnnotateAPI.Renderer

  def create(conn, params) do
    with {:ok, thread} <- thread_for(conn, params),
         :ok <- Annotate.Moderation.check_text(params["body_md"]) do
      case Comments.add_comment(thread, conn.assigns.annotate_commenter, params) do
        {:ok, comment} ->
          comment = with_preloads(comment)

          conn
          |> put_status(:created)
          |> json(%{"comment" => Renderer.comment(comment)})

        {:error, :invalid_body} ->
          conn |> put_status(:bad_request) |> json(%{"error" => "invalid_body"})

        {:error, :invalid_parent} ->
          conn |> put_status(:bad_request) |> json(%{"error" => "invalid_parent"})

        {:error, :attachment_mismatch} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "attachment_mismatch"})

        {:error, :billing_read_only} ->
          conn
          |> put_status(:forbidden)
          |> json(%{
            "error" => "billing_read_only",
            "message" => Annotate.Billing.locked_message()
          })

        {:error, _} ->
          conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
      end
    else
      {:error, :content_rejected} ->
        conn |> put_status(:unprocessable_entity) |> json(Annotate.Moderation.rejection_payload())

      {:error, %Plug.Conn{} = conn} -> conn
    end
  end

  def resolve(conn, params) do
    with {:ok, thread} <- thread_for(conn, params) do
      case Comments.resolve_thread(thread, conn.assigns.annotate_commenter) do
        {:ok, thread} -> json(conn, %{"thread" => Renderer.thread(with_preloads(thread))})
        {:error, _} -> unprocessable(conn)
      end
    else
      {:error, %Plug.Conn{} = conn} -> conn
    end
  end

  def reopen(conn, params) do
    with {:ok, thread} <- thread_for(conn, params) do
      case Comments.reopen_thread(thread) do
        {:ok, thread} -> json(conn, %{"thread" => Renderer.thread(with_preloads(thread))})
        {:error, _} -> unprocessable(conn)
      end
    else
      {:error, %Plug.Conn{} = conn} -> conn
    end
  end

  def patch_anchor(conn, params) do
    with {:ok, thread} <- thread_for(conn, params) do
      case Comments.set_thread_anchor(thread, params["anchor"]) do
        {:ok, thread} ->
          json(conn, %{"thread" => Renderer.thread(with_preloads(thread))})

        {:error, :invalid_anchor} ->
          conn |> put_status(:bad_request) |> json(%{"error" => "invalid_anchor"})

        {:error, _} ->
          unprocessable(conn)
      end
    else
      {:error, %Plug.Conn{} = conn} -> conn
    end
  end

  # ── Helpers ─────────────────────────────────────────────────

  # Visibility-gated (staff_only: a non-staff viewer may act only on threads
  # they started) — an unreadable thread is 404 exactly like a foreign one.
  defp thread_for(conn, params) do
    site = conn.assigns.annotate_site

    viewer =
      Annotate.Embed.Visibility.viewer(
        site,
        conn.assigns[:annotate_commenter],
        conn.assigns[:annotate_claims]
      )

    case Comments.get_visible_thread_for_site(params["id"], site.id, viewer) do
      %Annotate.Schema.Annotate.Thread{} = thread -> {:ok, thread}
      nil -> {:error, not_found(conn)}
    end
  end

  defp with_preloads(%Annotate.Schema.Annotate.Thread{} = t) do
    Annotate.Repo.preload(t, [:creator, comments: [:author, :attachments]])
  end

  defp with_preloads(comment) do
    Annotate.Repo.preload(comment, [:author, :attachments])
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{"error" => "not_found"})
    |> halt()
  end

  defp unprocessable(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"error" => "invalid_request"})
    |> halt()
  end
end
