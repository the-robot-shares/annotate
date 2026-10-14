defmodule AnnotateWeb.AnnotateAPI.SiteThreadsController do
  @moduledoc """
  `GET /api/v1/sites/:site/threads?page_key=` — thread listing (respects
  `settings.public_read`).
  `POST /api/v1/sites/:site/threads` — create page (upsert) + thread + root
  comment, binding attachments. A valid token attributes the comment; a
  token-less create is rejected (401) unless the site opts in via
  `comment_policy.allow_anonymous`, in which case a non-empty `guest_name` is
  required and stored on a site-scoped guest commenter row (never a NULL
  author).
  """
  use AnnotateWeb, :controller

  alias Annotate.Comments
  alias Annotate.Sites
  alias AnnotateWeb.AnnotateAPI.Renderer

  @guest_name_max 80

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

    with {:ok, author} <- resolve_author(site, commenter, params),
         {:ok, thread} <- Comments.create_thread(site, author, params) do
      conn
      |> put_status(:created)
      |> json(%{"thread" => Renderer.thread(thread)})
    else
      {:error, :guest_name_required} ->
        conn |> put_status(:bad_request) |> json(%{"error" => "guest_name_required"})

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

  # Token present → the authenticated commenter authors the thread.
  defp resolve_author(_site, %Annotate.Schema.Annotate.Commenter{} = commenter, _params),
    do: {:ok, commenter}

  # Token-less: the plug only lets us through when the site opted in via
  # comment_policy.allow_anonymous — then a non-empty guest_name is mandatory
  # and authors the comment via a site-scoped guest commenter row.
  defp resolve_author(site, nil, params) do
    guest_name = clean_guest_name(params["guest_name"])

    cond do
      guest_name == nil ->
        {:error, :guest_name_required}

      String.length(guest_name) > @guest_name_max ->
        {:error, :guest_name_required}

      true ->
        Sites.upsert_guest_commenter(site, guest_name)
    end
  end

  defp clean_guest_name(nil), do: nil

  defp clean_guest_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean_guest_name(_), do: nil
end
