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

  `opts[:viewer]` (`%Annotate.Embed.Visibility{}`) narrows IN SQL to the
  threads the viewer may read (`comment_policy.read_visibility`); foreign
  threads are never loaded, so they cannot be rendered, counted or presigned.
  Callers serving embed viewers MUST pass it.
  """
  def list_threads_with_comments(site_id, page_key, opts \\ []) do
    threads = do_list_threads(site_id, page_key, Keyword.get(opts, :viewer))

    case Keyword.get(opts, :query) do
      nil ->
        threads

      query ->
        current = if is_map(query), do: query, else: Annotate.Anchors.parse_query(query)
        cfg = Keyword.get(opts, :anchor_config, %{})
        Enum.filter(threads, &Annotate.Anchors.query_match?(&1.query_params, current, cfg))
    end
  end

  @doc """
  Site-wide inbox for the owner dashboard: threads across every page of
  `site_id`, newest first, with page, creator and non-deleted comments
  (authors) preloaded. `status`: `:open | :resolved | :all`. Bounded by
  `:limit` (default 50, max 200).
  """
  def list_site_inbox(site_id, opts \\ []) do
    status = Keyword.get(opts, :status, :open)
    limit = opts |> Keyword.get(:limit, 50) |> min(200) |> max(1)

    from(t in Thread,
      join: p in assoc(t, :page),
      where: p.site_id == ^site_id,
      order_by: [desc: t.inserted_at],
      limit: ^limit,
      preload: [
        :page,
        :creator,
        comments:
          ^from(c in Comment,
            where: is_nil(c.deleted_at),
            order_by: [asc: c.inserted_at],
            preload: [:author]
          )
      ]
    )
    |> filter_status(status)
    |> Repo.all()
  end

  @doc """
  Filtered, cursor-paginated thread search across one site (MCP `list_threads`).
  Newest first by `(inserted_at, id)`. Options (all optional):

    * `:status` — `:open` (default) | `:resolved` | `:all`
    * `:page_path` — exact path, or a prefix when it ends in `*`; matched
      against the URL-derived `page_path` and the page's `page_key`
    * `:origin` — exact thread origin (`https://host[:port]`)
    * `:since` — `%DateTime{}`: threads created, or commented on, at/after it
    * `:text` — case-insensitive substring of any live comment body or the page title
    * `:author` — case-insensitive substring of any live comment author's display name
    * `:orphaned` — `true` | `false` (anchor lost / found)
    * `:cursor` — opaque cursor from a previous page
    * `:limit` — 1..100 (default 25)

  Returns `{threads, next_cursor | nil}`; threads preload page, creator and
  live comments (author, attachments). The caller is responsible for having
  authorized `site_id`.
  """
  def search_site_threads(site_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, 25) |> min(100) |> max(1)

    query =
      from(t in Thread,
        as: :thread,
        join: p in assoc(t, :page),
        where: p.site_id == ^site_id,
        order_by: [desc: t.inserted_at, desc: t.id],
        limit: ^(limit + 1),
        preload: [
          :page,
          :creator,
          comments:
            ^from(c in Comment,
              where: is_nil(c.deleted_at),
              order_by: [asc: c.inserted_at],
              preload: [:author, :attachments]
            )
        ]
      )
      |> filter_status(Keyword.get(opts, :status, :open))
      |> search_page_path(Keyword.get(opts, :page_path))
      |> search_origin(Keyword.get(opts, :origin))
      |> search_since(Keyword.get(opts, :since))
      |> search_text(Keyword.get(opts, :text))
      |> search_author(Keyword.get(opts, :author))
      |> search_orphaned(Keyword.get(opts, :orphaned))
      |> search_after(decode_cursor(Keyword.get(opts, :cursor)))

    rows = Repo.all(query)

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      last = List.last(page)
      {page, encode_cursor(last)}
    else
      {rows, nil}
    end
  end

  defp search_page_path(q, nil), do: q
  defp search_page_path(q, ""), do: q

  defp search_page_path(q, path) when is_binary(path) do
    if String.ends_with?(path, "*") do
      pat = (path |> String.trim_trailing("*") |> like_escape()) <> "%"
      where(q, [t, p], like(t.page_path, ^pat) or like(p.page_key, ^pat))
    else
      norm = Annotate.Anchors.normalize_path(path)
      where(q, [t, p], t.page_path == ^norm or p.page_key == ^path or p.page_key == ^norm)
    end
  end

  defp search_origin(q, nil), do: q
  defp search_origin(q, ""), do: q
  defp search_origin(q, origin), do: where(q, [t], t.origin == ^String.downcase(origin))

  defp search_since(q, %DateTime{} = since) do
    where(
      q,
      [t],
      t.inserted_at >= ^since or
        exists(
          from(c in Comment,
            where: c.thread_id == parent_as(:thread).id and c.inserted_at >= ^since
          )
        )
    )
  end

  defp search_since(q, _), do: q

  defp search_text(q, text) when is_binary(text) and text != "" do
    pat = "%" <> like_escape(text) <> "%"

    where(
      q,
      [t],
      ilike(t.page_title, ^pat) or
        exists(
          from(c in Comment,
            where:
              c.thread_id == parent_as(:thread).id and is_nil(c.deleted_at) and
                ilike(c.body_md, ^pat)
          )
        )
    )
  end

  defp search_text(q, _), do: q

  defp search_author(q, author) when is_binary(author) and author != "" do
    pat = "%" <> like_escape(author) <> "%"

    where(
      q,
      [t],
      exists(
        from(c in Comment,
          join: a in assoc(c, :author),
          where:
            c.thread_id == parent_as(:thread).id and is_nil(c.deleted_at) and
              ilike(a.display_name, ^pat)
        )
      )
    )
  end

  defp search_author(q, _), do: q

  defp search_orphaned(q, true), do: where(q, [t], not is_nil(t.orphaned_at))
  defp search_orphaned(q, false), do: where(q, [t], is_nil(t.orphaned_at))
  defp search_orphaned(q, _), do: q

  defp search_after(q, {%DateTime{} = at, id}),
    do: where(q, [t], t.inserted_at < ^at or (t.inserted_at == ^at and t.id < ^id))

  defp search_after(q, _), do: q

  defp like_escape(s),
    do:
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

  defp encode_cursor(%Thread{inserted_at: at, id: id}),
    do: Base.url_encode64(DateTime.to_iso8601(at) <> "|" <> id, padding: false)

  defp decode_cursor(nil), do: nil

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [iso, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _} <- DateTime.from_iso8601(iso),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {at, id}
    else
      _ -> :invalid
    end
  end

  defp decode_cursor(_), do: :invalid

  @doc """
  A thread and its site by thread id alone (MCP tools accept a bare thread
  id). nil for a malformed or unknown id. The caller MUST then authorize the
  returned site for the user (non-member ⇒ not_found).
  """
  def get_thread_and_site(thread_id) do
    with {:ok, id} <- Ecto.UUID.cast(thread_id),
         {%Thread{} = thread, %Site{} = site} <-
           from(t in Thread,
             join: p in assoc(t, :page),
             join: s in Site,
             on: s.id == p.site_id,
             where: t.id == ^id,
             select: {t, s}
           )
           |> Repo.one() do
      {thread, site}
    else
      _ -> nil
    end
  end

  @doc "Thread with page, creator and live comments (author, attachments)."
  def preload_thread_detail(%Thread{} = thread) do
    Repo.preload(
      thread,
      [
        :page,
        :creator,
        comments:
          from(c in Comment,
            where: is_nil(c.deleted_at),
            order_by: [asc: c.inserted_at],
            preload: [:author, :attachments]
          )
      ],
      force: true
    )
  end

  defp filter_status(query, :open), do: where(query, [t], t.status == :open)
  defp filter_status(query, :resolved), do: where(query, [t], t.status == :resolved)
  defp filter_status(query, _), do: query

  @doc "`%{open: n, resolved: n}` thread counts for a site (inbox tabs)."
  def site_thread_counts(site_id) do
    counts =
      from(t in Thread,
        join: p in assoc(t, :page),
        where: p.site_id == ^site_id,
        group_by: t.status,
        select: {t.status, count(t.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{open: Map.get(counts, :open, 0), resolved: Map.get(counts, :resolved, 0)}
  end

  defp do_list_threads(site_id, page_key, viewer) do
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
    |> scope_to_viewer(viewer)
    |> Repo.all()
  end

  defp scope_to_viewer(query, nil), do: query

  defp scope_to_viewer(query, %Annotate.Embed.Visibility{} = viewer),
    do: Annotate.Embed.Visibility.scope_threads(query, viewer)

  @doc """
  Like `get_thread_for_site/2`, but nil when `viewer` may not read the thread
  (staff_only site, not staff, not the creator) — callers answer 404, exactly
  like a foreign-site id, so existence never leaks.
  """
  def get_visible_thread_for_site(thread_id, site_id, %Annotate.Embed.Visibility{} = viewer) do
    case get_thread_for_site(thread_id, site_id) do
      %Thread{} = thread ->
        if Annotate.Embed.Visibility.can_read_thread?(viewer, thread), do: thread, else: nil

      nil ->
        nil
    end
  end

  @doc "Like `get_comment_for_site/2`, gated by the comment's thread visibility."
  def get_visible_comment_for_site(comment_id, site_id, %Annotate.Embed.Visibility{} = viewer) do
    from(c in Comment,
      join: t in assoc(c, :thread),
      join: p in assoc(t, :page),
      where: c.id == ^comment_id and p.site_id == ^site_id,
      select: {c, t.created_by}
    )
    |> Repo.one()
    |> case do
      {%Comment{} = comment, creator_id} ->
        if Annotate.Embed.Visibility.can_read_creator?(viewer, creator_id),
          do: comment,
          else: nil

      nil ->
        nil
    end
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

  @doc """
  Edits a comment's body and, optionally, its attachments.

  `opts`:
    * `:attachment_ids` — bind additional attachments (the editor's OWN, `ready`,
      unbound, same site — same rule as `add_comment/3`; else
      `{:error, :attachment_mismatch}`).
    * `:remove_attachment_ids` — detach attachments currently bound to THIS
      comment (their rows stay, unbound; ids bound elsewhere are ignored).

  No schema change: it only moves `attachments.comment_id`.
  """
  def update_comment_body(%Comment{} = comment, body_md, opts \\ []) do
    add_ids = Keyword.get(opts, :attachment_ids)
    remove_ids = Keyword.get(opts, :remove_attachment_ids) || []
    editor = Keyword.get(opts, :commenter)

    with :ok <- validate_body(body_md),
         :ok <- validate_id_list(remove_ids),
         {:ok, attachments} <-
           fetch_bindable_attachments(comment_site(comment), add_ids, editor) do
      case Repo.transaction(fn ->
             updated =
               comment
               |> Comment.changeset(%{body_md: body_md, edited_at: now_usec()})
               |> Repo.update!()

             unbind_attachments(comment.id, remove_ids)
             bind_attachments(attachments, comment.id)
             updated
           end) do
        {:ok, updated} ->
          Realtime.comment_event(updated, :comment_updated)
          {:ok, updated}

        error ->
          error
      end
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

  @doc """
  A live comment, its thread and its site by comment id alone (MCP
  `delete_comment`). nil for a malformed/unknown/already-deleted id. The
  caller MUST authorize the returned site for the user.
  """
  def get_comment_and_site(comment_id) do
    with {:ok, id} <- Ecto.UUID.cast(comment_id),
         {%Comment{} = comment, %Thread{} = thread, %Site{} = site} <-
           from(c in Comment,
             join: t in assoc(c, :thread),
             join: p in assoc(t, :page),
             join: s in Site,
             on: s.id == p.site_id,
             where: c.id == ^id and is_nil(c.deleted_at),
             select: {c, t, s}
           )
           |> Repo.one() do
      {comment, thread, site}
    else
      _ -> nil
    end
  end

  @doc """
  Dashboard/MCP team moderation rule (single source; was private to the
  inbox panel): a site **admin or owner** may soft-delete any comment; any
  member may delete their OWN team replies (the `(site_id, user_id)` team
  commenter). `role` must be the user's CURRENT role on `site`.
  """
  def team_can_delete?(%Comment{} = comment, %Site{} = site, user_id, role)
      when is_binary(user_id) do
    Annotate.SiteMembers.role_at_least?(role, :admin) or
      case Repo.get_by(Annotate.Schema.Annotate.Commenter, site_id: site.id, user_id: user_id) do
        %{id: id} -> comment.author_id == id
        nil -> false
      end
  end

  def team_can_delete?(_, _, _, _), do: false

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

  defp validate_id_list(ids) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1), do: :ok, else: {:error, :attachment_mismatch}
  end

  defp validate_id_list(_), do: {:error, :attachment_mismatch}

  defp unbind_attachments(_comment_id, []), do: :ok

  defp unbind_attachments(comment_id, ids) do
    case Enum.flat_map(ids, fn id ->
           case Ecto.UUID.cast(id) do
             {:ok, uuid} -> [uuid]
             :error -> []
           end
         end) do
      [] ->
        :ok

      uuids ->
        from(a in Attachment, where: a.comment_id == ^comment_id and a.id in ^uuids)
        |> Repo.update_all(set: [comment_id: nil])

        :ok
    end
  end

  defp comment_site(%Comment{thread_id: thread_id}) do
    from(t in Thread,
      join: p in Page,
      on: p.id == t.page_id,
      where: t.id == ^thread_id,
      select: p.site_id
    )
    |> Repo.one()
    |> case do
      nil -> nil
      site_id -> %Site{id: site_id}
    end
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
