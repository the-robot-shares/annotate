defmodule AnnotateWeb.Hologram.Components.InboxPanel do
  @moduledoc """
  Site comments inbox (dashboard site page): every thread across the site's
  pages with open / resolved / all filters. Members reply (as the site-team
  identity, `Annotate.Sites.team_commenter_for_user/2`), resolve and reopen;
  admins and owners also soft-delete anyone's comment; everyone may delete
  their own team replies.

  **Data never rides the server-rendered page state.** Comment bodies are
  untrusted multi-line text, and Hologram's inline hydration payload does not
  survive newlines or `</script` inside state strings. `init/3` therefore
  renders an empty, loading inbox and queues `:load` on the client; threads
  arrive through the `:load_inbox` command response.

  **Realtime:** subscribed to the data-less Hologram channel
  `{:annotate_inbox, slug}` (`Annotate.Realtime.notify_inbox/1`, fired on
  every comment/thread commit). A ping triggers a re-fetch through the same
  authorized command, so a user who lost access gets an error, never data.
  A 60 s poll backs it up in case the realtime transport is unavailable.

  Every command re-authorizes against the DB (`DashboardAuth.authorize_site/3`).
  """

  use Hologram.Component

  alias Annotate.Comments
  alias Annotate.Hologram.DashboardAuth
  alias Annotate.Realtime
  alias Annotate.SiteMembers
  alias Annotate.Sites

  prop :slug, :string
  prop :role, :string, default: "member"

  @poll_ms 60_000
  @max_body 10_000

  def init(props, component, server) do
    component =
      component
      |> put_state(
        slug: props.slug,
        role: props.role,
        status: "open",
        threads: [],
        counts: %{open: 0, resolved: 0},
        loading: true,
        error: nil,
        drafts: %{},
        busy: nil
      )
      |> put_action(:load)

    {component, put_subscription(server, Realtime.inbox_channel(props.slug))}
  end

  def template do
    ~HOLO"""
    <section class="dsh-panel" data-cy="dsh-inbox">
      <h2 class="dsh-panel__title">Comments inbox</h2>
      <div class="dsh-panel__body">
        <div class="dsh-inbox__filters" role="group" aria-label="Thread status filter">
          <button type="button" class={filter_class(@status, "open")} aria-pressed={@status == "open"} $click={action: :filter, params: %{status: "open"}} data-cy="dsh-inbox-open">Open ({@counts.open})</button>
          <button type="button" class={filter_class(@status, "resolved")} aria-pressed={@status == "resolved"} $click={action: :filter, params: %{status: "resolved"}} data-cy="dsh-inbox-resolved">Resolved ({@counts.resolved})</button>
          <button type="button" class={filter_class(@status, "all")} aria-pressed={@status == "all"} $click={action: :filter, params: %{status: "all"}} data-cy="dsh-inbox-all">All</button>
          <button type="button" class="dsh-btn dsh-btn--ghost dsh-btn--sm" $click={:load} aria-label="Refresh inbox">Refresh</button>
        </div>

        {%if @error}
          <p class="dsh-error" role="alert">{@error}</p>
        {/if}

        {%if @loading && @threads == []}
          <p class="dsh-empty" role="status">Loading comments…</p>
        {/if}

        {%if !@loading && @threads == [] && @counts.open == 0 && @counts.resolved == 0}
          <div class="dsh-empty" data-cy="dsh-inbox-empty">
            <p><strong>Nothing to triage</strong></p>
            <p>Once the widget is live, threads land here in real time — anchored to the element they're about.</p>
            <button type="button" class="dsh-btn dsh-btn--ghost dsh-btn--sm" $click={action: :tab, params: %{tab: "overview"}, target: "page"} data-cy="dsh-inbox-snippet">Grab the snippet</button>
          </div>
        {/if}

        {%if !@loading && @threads == [] && (@counts.open > 0 || @counts.resolved > 0)}
          <p class="dsh-empty" data-cy="dsh-inbox-empty">No {empty_label(@status)} threads here. Try another filter.</p>
        {/if}

        {%for t <- @threads}
          <article class="dsh-thread" data-cy="dsh-thread" data-thread-id={t.id}>
            <header class="dsh-thread__head">
              <div>
                <span class={status_class(t.status)}>{t.status}</span>
                <span class="dsh-thread__page">{t.page_label}</span>
                {%if t.query_label != ""}
                  <span class="dsh-chip dsh-chip--muted">{t.query_label}</span>
                {/if}
                {%if t.orphaned}
                  <span class="dsh-chip dsh-chip--internal">anchor lost</span>
                {/if}
              </div>
              <div class="dsh-actions">
                {%if t.deep_link}
                  <a class="dsh-btn dsh-btn--sm" href={t.deep_link} target="_blank" rel="noopener noreferrer" data-cy="dsh-thread-open">Open on page</a>
                {/if}
                {%if t.status == "open"}
                  <button type="button" class="dsh-btn dsh-btn--sm" $click={action: :resolve, params: %{id: t.id}} disabled={@busy == t.id} data-cy="dsh-thread-resolve">Resolve</button>
                {%else}
                  <button type="button" class="dsh-btn dsh-btn--sm" $click={action: :reopen, params: %{id: t.id}} disabled={@busy == t.id} data-cy="dsh-thread-reopen">Reopen</button>
                {/if}
              </div>
            </header>
            <div class="dsh-thread__body">
              {%for c <- t.comments}
                <div class={comment_class(c)} data-cy="dsh-comment">
                  <div class="dsh-comment__meta">
                    <span class="dsh-comment__author">{c.author}</span>
                    {%if c.team}
                      <span class="dsh-chip">team</span>
                    {/if}
                    <span>{c.at}</span>
                    {%if c.can_delete}
                      <button type="button" class="dsh-btn dsh-btn--danger dsh-btn--sm" $click={action: :delete, params: %{id: c.id}} aria-label="Delete comment" data-cy="dsh-comment-delete">Delete</button>
                    {/if}
                  </div>
                  <p class="dsh-comment__text">{c.body}</p>
                  {%if c.attachments != []}
                    <div class="dsh-attachments" data-cy="dsh-attachments">
                      {%for a <- c.attachments}
                        {%if a.image}
                          <a class="dsh-attachment dsh-attachment--thumb" href={a.url} target="_blank" rel="noopener noreferrer" data-lightbox={true} aria-label={a.alt} title={a.alt} data-cy="dsh-attachment-image">
                            {%if a.dims}
                              <img src={a.url} alt={a.alt} width={a.width} height={a.height} loading="lazy" decoding="async" />
                            {%else}
                              <img src={a.url} alt={a.alt} loading="lazy" decoding="async" />
                            {/if}
                          </a>
                        {%else}
                          <a class="dsh-attachment dsh-attachment--chip" href={a.url} target="_blank" rel="noopener noreferrer" data-cy="dsh-attachment-file" title={"Download " <> a.filename}>
                            <span class="dsh-attachment__badge" aria-hidden="true">{a.ext_label}</span>
                            <span class="dsh-attachment__name">{a.filename}</span>
                            {%if a.size_label != ""}
                              <span class="dsh-attachment__size">{a.size_label}</span>
                            {/if}
                          </a>
                        {/if}
                      {/for}
                    </div>
                  {/if}
                </div>
              {/for}
              <form class="dsh-form" $submit.prevent_default={action: :reply, params: %{id: t.id}}>
                <div class="dsh-field">
                  <label for={"reply-" <> t.id}>Reply as the site team</label>
                  <textarea id={"reply-" <> t.id} rows="2" maxlength="10000" value={Map.get(@drafts, t.id, "")} $change={action: :draft, params: %{id: t.id}} data-cy="dsh-reply-input"></textarea>
                </div>
                <div class="dsh-actions">
                  <button type="submit" class="dsh-btn dsh-btn--primary dsh-btn--sm" disabled={@busy == t.id} data-cy="dsh-reply-send">Send reply</button>
                </div>
              </form>
            </div>
          </article>
        {/for}
      </div>
    </section>
    """
  end

  # ── actions (client) ──────────────────────────────────────────

  def action(:load, _params, c),
    do:
      c
      |> put_state(loading: true)
      |> put_command(:load_inbox, slug: c.state.slug, status: c.state.status)

  # Realtime ping (data-less) → re-fetch through the authorized command.
  def action(:inbox_changed, _params, c), do: action(:load, %{}, c)

  def action(:poll, _params, c), do: action(:load, %{}, c)

  def action(:filter, params, c),
    do: action(:load, %{}, put_state(c, status: params.status, threads: []))

  def action(:draft, params, c),
    do: put_state(c, :drafts, Map.put(c.state.drafts, params.id, params.event.value))

  def action(:reply, params, c) do
    body = Map.get(c.state.drafts, params.id, "")

    c
    |> put_state(busy: params.id, error: nil)
    |> put_command(:reply,
      slug: c.state.slug,
      status: c.state.status,
      thread_id: params.id,
      body: body
    )
  end

  def action(:resolve, params, c),
    do:
      c
      |> put_state(busy: params.id, error: nil)
      |> put_command(:resolve, slug: c.state.slug, status: c.state.status, thread_id: params.id)

  def action(:reopen, params, c),
    do:
      c
      |> put_state(busy: params.id, error: nil)
      |> put_command(:reopen, slug: c.state.slug, status: c.state.status, thread_id: params.id)

  def action(:delete, params, c),
    do:
      c
      |> put_state(error: nil)
      |> put_command(:delete_comment,
        slug: c.state.slug,
        status: c.state.status,
        comment_id: params.id
      )

  def action(:loaded, params, c) do
    drafts =
      case params[:sent_thread] do
        nil -> c.state.drafts
        id -> Map.delete(c.state.drafts, id)
      end

    c
    |> put_state(
      threads: params.threads,
      counts: params.counts,
      loading: false,
      busy: nil,
      error: nil,
      drafts: drafts
    )
    |> put_action(name: :poll, delay: @poll_ms)
  end

  def action(:failed, params, c), do: put_state(c, loading: false, busy: nil, error: params.error)

  # ── commands (server) ─────────────────────────────────────────

  def command(:load_inbox, params, server),
    do: with_site(server, params, :member, fn _user, _site, _role -> :ok end)

  def command(:reply, params, server) do
    with_site(server, params, :member, fn user, site, _role ->
      body = params.body |> to_string() |> String.trim()

      with {:body, true} <- {:body, body != "" and String.length(body) <= @max_body},
           {:thread, %{} = thread} <-
             {:thread, Comments.get_thread_for_site(to_string(params.thread_id), site.id)},
           {:ok, team} <- Sites.team_commenter_for_user(site, user.id),
           {:ok, _comment} <- Comments.add_comment(thread, team, %{"body_md" => body}) do
        {:ok, sent_thread: thread.id}
      else
        {:body, _} -> {:error, "Write a reply first (max #{@max_body} characters)."}
        {:thread, _} -> {:error, "That thread no longer exists."}
        {:error, :billing_read_only} -> {:error, Annotate.Billing.locked_message()}
        _ -> {:error, "Could not send the reply."}
      end
    end)
  end

  def command(:resolve, params, server) do
    with_site(server, params, :member, fn user, site, _role ->
      with %{} = thread <- Comments.get_thread_for_site(to_string(params.thread_id), site.id),
           {:ok, team} <- Sites.team_commenter_for_user(site, user.id),
           {:ok, _} <- Comments.resolve_thread(thread, team) do
        :ok
      else
        _ -> {:error, "Could not resolve the thread."}
      end
    end)
  end

  def command(:reopen, params, server) do
    with_site(server, params, :member, fn _user, site, _role ->
      with %{} = thread <- Comments.get_thread_for_site(to_string(params.thread_id), site.id),
           {:ok, _} <- Comments.reopen_thread(thread) do
        :ok
      else
        _ -> {:error, "Could not reopen the thread."}
      end
    end)
  end

  def command(:delete_comment, params, server) do
    with_site(server, params, :member, fn user, site, role ->
      with %{} = comment <- Comments.get_comment_for_site(to_string(params.comment_id), site.id),
           true <- Comments.team_can_delete?(comment, site, user.id, role) || {:error, :forbidden},
           {:ok, _} <- Comments.soft_delete_comment(comment) do
        :ok
      else
        {:error, :forbidden} ->
          {:error, "Only admins and owners can delete other people's comments."}

        _ ->
          {:error, "Could not delete the comment."}
      end
    end)
  end

  # Authorize (DB, per command) → run → reply with a fresh inbox page.
  defp with_site(server, params, min_role, fun) do
    case DashboardAuth.authorize_site(server, params.slug, min_role) do
      {:ok, user, site, role} ->
        case fun.(user, site, role) do
          :ok -> reply_loaded(server, site, user, role, params, [])
          {:ok, extra} -> reply_loaded(server, site, user, role, params, extra)
          {:error, message} -> put_action(server, :failed, error: message)
        end

      {:error, reason} ->
        put_action(server, :failed, error: DashboardAuth.message(reason))
    end
  end

  defp reply_loaded(server, site, user, role, params, extra) do
    status = parse_status(params[:status])

    team =
      Annotate.Repo.get_by(Annotate.Schema.Annotate.Commenter, site_id: site.id, user_id: user.id)

    threads =
      site.id
      |> Comments.list_site_inbox(status: status)
      |> Enum.map(&serialize_thread(&1, site, team, role))

    put_action(
      server,
      :loaded,
      [threads: threads, counts: Comments.site_thread_counts(site.id)] ++ extra
    )
  end

  # ── helpers ───────────────────────────────────────────────────

  defp serialize_thread(t, site, team, role) do
    page_path = t.page_path || (t.page && t.page.page_key) || "/"
    significant = Annotate.Anchors.significant(t.query_params, site.settings || %{}) || %{}
    admin? = SiteMembers.role_at_least?(role, :admin)

    %{
      id: t.id,
      status: to_string(t.status),
      page_label: page_label(t, page_path),
      query_label: query_label(significant),
      # Origin-checked: the thread url is visitor-submitted (THREAT-MODEL T-31).
      deep_link: Annotate.Anchors.safe_deep_link(site, t.url, t.id),
      orphaned: not is_nil(t.orphaned_at),
      comments:
        Enum.map(t.comments, fn c ->
          author = (c.author && c.author.display_name) || "Guest"

          %{
            id: c.id,
            author: author,
            team: not is_nil(c.author && c.author.user_id),
            body: c.body_md || "",
            at: format_time(c.inserted_at),
            can_delete: admin? or (team != nil and c.author_id == team.id),
            attachments: serialize_attachments(c.attachments, author)
          }
        end)
    }
  end

  # Attachments arrive with the inbox preload (status :ready only). Links point
  # at the stable authenticated route (`/dashboard/attachments/:id`), which
  # re-signs on every hit — they never go stale like raw presigned urls.
  defp serialize_attachments(attachments, author) when is_list(attachments) do
    attachments
    |> Enum.filter(fn a -> a.status == :ready and is_binary(a.storage_key) end)
    |> Enum.map(fn a ->
      image? = image?(a)

      %{
        id: a.id,
        image: image?,
        # Filename part of the storage key is sanitized server-side at presign
        # time to [A-Za-z0-9._-], so it is safe hydration state as-is.
        filename: filename_of(a),
        size_label: size_label(a.bytes),
        width: a.width,
        height: a.height,
        dims: is_integer(a.width) and is_integer(a.height) and a.width > 0 and a.height > 0,
        alt: "#{kind_word(a)} attached by #{author}",
        ext_label: ext_label(a),
        url: "/dashboard/attachments/" <> to_string(a.id)
      }
    end)
  end

  defp serialize_attachments(_, _), do: []

  defp filename_of(a), do: a.storage_key |> String.split("/") |> List.last()

  defp image?(%{kind: kind}) when kind in [:image, :screenshot], do: true
  defp image?(%{content_type: ct}) when is_binary(ct), do: String.starts_with?(ct, "image/")
  defp image?(_), do: false

  defp kind_word(%{kind: :screenshot}), do: "Screenshot"
  defp kind_word(%{kind: :image}), do: "Image"
  defp kind_word(_), do: "File"

  # Tiny badge on file chips ("PNG", "PDF", "FILE") — no icon font in the
  # dashboard, so the type IS the icon.
  defp ext_label(a) do
    case String.split(filename_of(a), ".") do
      [_] -> ""
      parts -> parts |> List.last() |> String.upcase() |> String.slice(0, 4)
    end
  end

  defp size_label(b) when is_integer(b) and b > 0, do: human_bytes(b)
  defp size_label(_), do: ""

  defp human_bytes(b) when b >= 1_048_576,
    do: :erlang.float_to_binary(b / 1_048_576, decimals: 1) <> " MB"

  defp human_bytes(b) when b >= 1024, do: to_string(div(b, 1024)) <> " KB"
  defp human_bytes(b), do: to_string(b) <> " B"

  defp page_label(%{page_title: title}, path) when is_binary(title) and title != "",
    do: title <> " · " <> path

  defp page_label(_, path), do: path

  defp query_label(params) when map_size(params) == 0, do: ""

  defp query_label(params) do
    params
    |> Enum.sort()
    |> Enum.map_join("&", fn {k, vs} -> Enum.map_join(List.wrap(vs), "&", &"#{k}=#{&1}") end)
    |> then(&("?" <> &1))
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_time(_), do: ""

  defp parse_status("resolved"), do: :resolved
  defp parse_status("all"), do: :all
  defp parse_status(_), do: :open

  def filter_class(current, value) when current == value,
    do: "dsh-btn dsh-btn--primary dsh-btn--sm"

  def filter_class(_, _), do: "dsh-btn dsh-btn--sm"

  def status_class("resolved"), do: "dsh-chip dsh-chip--resolved"
  def status_class(_), do: "dsh-chip dsh-chip--open"

  def comment_class(%{team: true}), do: "dsh-comment dsh-comment--team"
  def comment_class(_), do: "dsh-comment"

  def empty_label("all"), do: ""
  def empty_label(status), do: status
end
