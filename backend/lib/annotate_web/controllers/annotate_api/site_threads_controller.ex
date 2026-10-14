defmodule AnnotateWeb.AnnotateAPI.SiteThreadsController do
  @moduledoc """
  `GET /api/v1/sites/:site/threads?page_key=` — thread listing (respects
  `settings.public_read`).
  `POST /api/v1/sites/:site/threads` — create page (upsert) + thread + root
  comment, binding attachments. Anonymous posting is allowed; a valid token
  attributes the comment.
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias AnnotateWeb.AnnotateAPI.Renderer

  def index(conn, %{"page_key" => page_key} = _params) do
    site = conn.assigns.annotate_site

    if Annotate.Sites.public_read?(site) or not is_nil(conn.assigns[:annotate_commenter]) do
      threads = Comments.list_threads_with_comments(site.id, page_key)
      json(conn, %{"threads" => Renderer.thread_list(threads)})
    else
      conn |> put_status(:unauthorized) |> json(%{"error" => "invalid_token"})
    end
  end

  def index(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{"error" => "page_key_required"})
  end

  def create(conn, params) do
    site = conn.assigns.annotate_site
    commenter = conn.assigns[:annotate_commenter]

    case Comments.create_thread(site, commenter, params) do
      {:ok, thread} ->
        conn
        |> put_status(:created)
        |> json(%{"thread" => Renderer.thread(thread)})

      {:error, :invalid_page_key} ->
        conn |> put_status(:bad_request) |> json(%{"error" => "invalid_page_key"})

      {:error, :invalid_anchor} ->
        conn |> put_status(:bad_request) |> json(%{"error" => "invalid_anchor"})

      {:error, :invalid_body} ->
        conn |> put_status(:bad_request) |> json(%{"error" => "invalid_body"})

      {:error, :attachment_mismatch} ->
        conn |> put_status(:unprocessable_entity) |> json(%{"error" => "attachment_mismatch"})

      {:error, _other} ->
        conn |> put_status(:unprocessable_entity) |> json(%{"error" => "invalid_request"})
    end
  end
end
