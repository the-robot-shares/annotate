defmodule Annotate.Comments do
  @moduledoc """
  Pages, threads, comments, and attachments for the annotate API.
  """

  import Ecto.Query
  alias Annotate.Realtime
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Attachment
  alias Annotate.Schema.Annotate.Comment
  alias Annotate.Schema.Annotate.Page
  alias Annotate.Schema.Annotate.Site
  alias Annotate.Schema.Annotate.Thread

  @stale_pending_hours 24

  # ── Pages ─────────────────────────────────────────────────────

  @doc "Upserts the (site, page_key) page, refreshing last_url/title."
  def upsert_page(%Site{} = site, page_key, url, title) do
    case Repo.get_by(Page, site_id: site.id, page_key: page_key) do
      %Page{} = page ->
        page
        |> Ecto.Changeset.change(%{last_url: url || page.last_url, title: title || page.title})
        |> Repo.update!()

      nil ->
        %Page{}
        |> Page.changeset(%{site_id: site.id, page_key: page_key, last_url: url, title: title})
        |> Repo.insert!()
    end
  end

  # ── Threads ───────────────────────────────────────────────────

  def get_thread_for_site(thread_id, site_id) do
    from(t in Thread,
      join: p in assoc(t, :page),
      where: t.id == ^thread_id and p.site_id == ^site_id
    )
    |> Repo.one()
  end

  @doc """
  Threads (with comments, authors, attachments) for a site page_key.

  `opts[:query]` (raw query string or params map) narrows to threads whose
  stored query params match, using the site's significance config
  (`Annotate.Anchors`); without it every thread on the page is returned.
  """
  def list_threads_with_comments(site_id, page_key, opts \\ []) do
    threads = do_list_threads(site_id, page_key)

    case Keyword.get(opts, :query) do
      nil ->
        threads

      query ->
        current = if is_map(query), do: query, else: Annotate.Anchors.parse_query(query)
        cfg = Keyword.get(opts, :anchor_config, %{})
        Enum.filter(threads, &Annotate.Anchors.query_match?(&1.query_params, current, cfg))
    end
  end

  defp do_list_threads(site_id, page_key) do
    from(t in Thread,
      join: p in assoc(t, :page),
      where: p.site_id == ^site_id and p.page_key == ^page_key,
      order_by: [asc: t.inserted_at],
      preload: [
        :creator,
        comments:
          ^from(c in Comment,
            where: is_nil(c.deleted_at),
            preload: [:author, :attachments]
          )
      ]
    )
    |> Repo.all()
  end

  @doc """
  Creates a page (upsert), thread, and root comment in one transaction,
  binding `attachment_ids` (must be the author's OWN, `ready`, unbound, and
  on the same site). Requires a non-nil commenter — guests are resolved to a
  site-scoped guest row by the caller.
  """
  def create_thread(%Site{} = site, commenter, attrs) do
    page_key = attrs["page_key"]
    anchor = attrs["anchor"]
    body_md = attrs["body_md"]

    with :ok <- require_author(commenter),
         :ok <- validate_page_key(page_key),
         :ok <- validate_anchor(anchor),
         :ok <- validate_body(body_md),
         {:ok, attachments} <-
           fetch_bindable_attachments(site, attrs["attachment_ids"], commenter) do
      case Repo.transaction(fn ->
             page = upsert_page(site, page_key, attrs["url"], attrs["title"])

             thread =
               %Thread{}
               |> Thread.changeset(
                 Map.merge(Annotate.Anchors.context_from_params(attrs), %{
                   "page_id" => page.id,
                   "anchor" => anchor,
                   "created_by" => commenter.id,
                   "anchor_version" => anchor_version(anchor)
                 })
               )
               |> Repo.insert!()

             comment =
               %Comment{}
               |> Comment.changeset(%{
                 thread_id: thread.id,
                 author_id: commenter.id,
                 body_md: body_md
               })
               |> Repo.insert!()

             bind_attachments(attachments, comment.id)

             thread
             |> Repo.preload([:page, :creator])
             |> Map.put(:comments, [Repo.preload(comment, [:author, :attachments])])
           end) do
        {:ok, thread} ->
          Realtime.thread_created(site, page_key, thread)
          {:ok, thread}

        error ->
          error
      end
    end
  end

  @doc "Adds a comment (optionally a reply via parent_id) to a thread."
  def add_comment(%Thread{} = thread, commenter, attrs) do
    body_md = attrs["body_md"]

    with :ok <- validate_body(body_md),
         :ok <- require_author(commenter),
         {:ok, parent_id} <- validate_parent(thread, attrs["parent_id"]),
         {:ok, attachments} <-
           fetch_bindable_attachments(thread_site(thread), attrs["attachment_ids"], commenter) do
      case Repo.transaction(fn ->
             comment =
               %Comment{}
               |> Comment.changeset(%{
                 thread_id: thread.id,
                 parent_id: parent_id,
                 author_id: commenter.id,
                 body_md: body_md
               })
               |> Repo.insert!()

             bind_attachments(attachments, comment.id)
             Repo.preload(comment, [:author, :attachments])
           end) do
        {:ok, comment} ->
          Realtime.comment_created(thread.page_id, comment)
          {:ok, comment}

        error ->
          error
      end
    end
  end

  def resolve_thread(%Thread{} = thread, commenter) do
    with {:ok, thread} <-
           thread
           |> Thread.changeset(%{
             status: :resolved,
             resolved_by: commenter && commenter.id,
             resolved_at: now_usec()
           })
           |> Repo.update() do
      Realtime.thread_event(thread, :thread_resolved)
      {:ok, thread}
    end
  end

  def reopen_thread(%Thread{} = thread) do
    with {:ok, thread} <-
           thread
           |> Thread.changeset(%{status: :open, resolved_by: nil, resolved_at: nil})
           |> Repo.update() do
      Realtime.thread_event(thread, :thread_reopened)
      {:ok, thread}
    end
  end

  @doc "Re-anchor repair: replaces the anchor and clears `orphaned_at`."
  def set_thread_anchor(%Thread{} = thread, anchor) do
    with :ok <- validate_anchor(anchor),
         {:ok, thread} <-
           thread
           |> Thread.changeset(%{anchor: anchor, orphaned_at: nil})
           |> Repo.update() do
      Realtime.thread_event(thread, :thread_anchor_updated)
      {:ok, thread}
    end
  end

  @doc "Marks a thread orphaned (widget-side anchor lookup failed)."
  def mark_thread_orphaned(%Thread{} = thread) do
    thread
    |> Thread.changeset(%{orphaned_at: now_usec()})
    |> Repo.update()
  end

  # ── Comments ──────────────────────────────────────────────────

  @doc "Comment visible to the API: exists, belongs to a thread of `site_id`."
  def get_comment_for_site(comment_id, site_id) do
    from(c in Comment,
      join: t in assoc(c, :thread),
      join: p in assoc(t, :page),
      where: c.id == ^comment_id and p.site_id == ^site_id
    )
    |> Repo.one()
  end

  def update_comment_body(%Comment{} = comment, body_md) do
    with :ok <- validate_body(body_md),
         {:ok, comment} <-
           comment
           |> Comment.changeset(%{body_md: body_md, edited_at: now_usec()})
           |> Repo.update() do
      Realtime.comment_event(comment, :comment_updated)
      {:ok, comment}
    end
  end

  def soft_delete_comment(%Comment{} = comment) do
    with {:ok, comment} <-
           comment
           |> Comment.changeset(%{deleted_at: now_usec()})
           |> Repo.update() do
      Realtime.comment_event(comment, :comment_deleted)
      {:ok, comment}
    end
  end

  @doc "True when the commenter may edit/delete: author, else site owner."
  def comment_manageable_by?(%Comment{} = comment, site, commenter)
      when commenter != nil do
    comment.author_id == commenter.id or site.owner_commenter_id == commenter.id
  end

  def comment_manageable_by?(_, _, _), do: false

  @doc """
  True when the commenter may DELETE (moderate) the comment: its author, the
  legacy `sites.owner_commenter_id`, or a team **owner/admin**. The team role
  is re-derived from current membership / site policy on this request
  (`Annotate.Embed.Team.moderator?/3`), never trusted from the token alone.
  Editing someone else's text stays author/owner-only
  (`comment_manageable_by?/3`).
  """
  def comment_moderatable_by?(%Comment{} = comment, site, commenter, claims)
      when commenter != nil do
    comment_manageable_by?(comment, site, commenter) or
      Annotate.Embed.Team.moderator?(site, commenter, claims)
  end

  def comment_moderatable_by?(_, _, _, _), do: false

  # ── Attachments ───────────────────────────────────────────────

  @doc """
  Creates a pending attachment + presigned PUT. Returns
  `{:ok, attachment, upload_url}`.
  """
  def create_pending_attachment(%Site{} = site, uploader, %{
        filename: filename,
        content_type: content_type,
        bytes: bytes,
        kind: kind
      }) do
    storage_key = storage_key(site, filename)
    upload_url = Annotate.Storage.presigned_upload_url(storage_key, content_type)

    %Attachment{}
    |> Attachment.changeset(%{
      uploader_id: uploader.id,
      site_id: site.id,
      kind: kind,
      storage_key: storage_key,
      content_type: content_type,
      bytes: bytes,
      status: :pending
    })
    |> Repo.insert()
    |> case do
      {:ok, attachment} -> {:ok, attachment, upload_url}
      error -> error
    end
  end

  def get_attachment_for_site(id, site_id) do
    from(a in Attachment, where: a.id == ^id and a.site_id == ^site_id) |> Repo.one()
  end

  @doc "pending → ready with optional width/height/annotation."
  def complete_attachment(%Attachment{status: :pending} = attachment, attrs) do
    attachment
    |> Attachment.changeset(%{
      width: attrs["width"],
      height: attrs["height"],
      annotation: attrs["annotation"],
      status: :ready
    })
    |> Repo.update()
  end

  def complete_attachment(%Attachment{}, _attrs), do: {:error, :not_pending}

  @doc "Sweeps pending attachments older than #{@stale_pending_hours}h. Returns deleted count."
  def sweep_stale_pending do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_pending_hours, :hour)

    {count, _} =
      from(a in Attachment, where: a.status == :pending and a.inserted_at < ^cutoff)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc "Presigned GET urls for a set of attachments."
  def presign_downloads(attachments) do
    Map.new(attachments, fn a ->
      {a.id, Annotate.Storage.presigned_download_url(a.storage_key)}
    end)
  end

  # ── Internals ─────────────────────────────────────────────────

  defp validate_page_key(pk) when is_binary(pk) and byte_size(pk) in 1..255, do: :ok
  defp validate_page_key(_), do: {:error, :invalid_page_key}

  # Comments never carry a NULL author: callers must resolve an author (token
  # commenter or site-scoped guest row) before writing. Anonymous HTTP access
  # is decided at the plug/controller layer, never inside the context.
  defp require_author(%Annotate.Schema.Annotate.Commenter{}), do: :ok
  defp require_author(nil), do: {:error, :invalid_author}
  defp require_author(_), do: {:error, :invalid_author}

  defp anchor_version(%{"v" => v}) when is_integer(v) and v in 1..32_767, do: v
  defp anchor_version(_), do: 1

  defp validate_anchor(a) when is_map(a), do: :ok
  defp validate_anchor(_), do: {:error, :invalid_anchor}

  defp validate_body(b) when is_binary(b), do: :ok
  defp validate_body(_), do: {:error, :invalid_body}

  defp validate_parent(_thread, nil), do: {:ok, nil}

  defp validate_parent(thread, parent_id) when is_binary(parent_id) do
    case Comment
         |> Ecto.Query.where(
           [c],
           c.id == ^parent_id and c.thread_id == ^thread.id and is_nil(c.deleted_at)
         )
         |> Repo.one() do
      %Comment{} -> {:ok, parent_id}
      nil -> {:error, :invalid_parent}
    end
  end

  defp validate_parent(_, _), do: {:error, :invalid_parent}

  defp fetch_bindable_attachments(_site, nil, _commenter), do: {:ok, []}

  # Only the author's OWN attachments on the same site, still unbound, and
  # already completed (`ready`) — pending uploads cannot be smuggled onto a
  # comment before their content landed, and foreign uploads cannot be bound.
  defp fetch_bindable_attachments(%Site{} = site, ids, commenter) when is_list(ids) do
    unique_ids = Enum.uniq(ids)

    uploader_id = commenter && commenter.id

    attachments =
      from(a in Attachment,
        where: a.id in ^unique_ids,
        where: a.site_id == ^site.id,
        where: is_nil(a.comment_id),
        where: a.uploader_id == ^uploader_id,
        where: a.status == :ready
      )
      |> Repo.all()

    if length(attachments) == length(unique_ids) do
      {:ok, attachments}
    else
      {:error, :attachment_mismatch}
    end
  end

  defp fetch_bindable_attachments(_, _, _), do: {:error, :attachment_mismatch}

  defp bind_attachments(attachments, comment_id) do
    Enum.each(attachments, fn a ->
      a
      |> Ecto.Changeset.change(comment_id: comment_id)
      |> Repo.update!()
    end)
  end

  defp thread_site(%Thread{page_id: page_id}) do
    from(p in Page, where: p.id == ^page_id, select: p.site_id)
    |> Repo.one()
    |> case do
      nil -> nil
      site_id -> %Site{id: site_id}
    end
  end

  defp storage_key(%Site{} = site, filename) do
    safe =
      filename
      |> to_string()
      |> Path.basename()
      |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
      |> binary_part_check()

    "annotate/#{site.id}/#{Ecto.UUID.generate()}/#{safe}"
  end

  defp binary_part_check(""), do: "file"
  defp binary_part_check(name), do: String.slice(name, 0, 200)

  defp now_usec, do: DateTime.truncate(DateTime.utc_now(), :microsecond)
end
