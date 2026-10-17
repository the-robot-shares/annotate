defmodule Annotate.Realtime do
  @moduledoc """
  Realtime event fan-out for the annotate API.

  After every successful commit in `Annotate.Comments`, the mutated entity is
  broadcast on Phoenix.PubSub to the page topic every widget subscribes to:

      page:<site_slug>:<sha256_hex_lower(page_key)>

  The page_key is hashed (sha256, lowercase hex) so topics stay bounded no
  matter how long or messy the host page key is.

  Payloads are rendered by `AnnotateWeb.AnnotateAPI.Renderer` — the SAME JSON
  renderer the REST API uses — so a `thread_created` payload is byte-identical
  to the REST thread shape (attachment presigned GET urls included). This is a
  deliberate web-layer dependency from the domain: the parity guarantee is the
  product requirement, and keeping rendering here means the context call sites
  stay one-liners.

  Events: `thread_created`, `comment_created`, `comment_updated`,
  `comment_deleted`, `thread_resolved`, `thread_reopened`,
  `thread_anchor_updated`.

  **Per-viewer visibility.** Every broadcast carries an internal
  `"__vis" => %{"site_id", "creator_id", "read_visibility"}` key (the thread's
  creator and the site's `read_visibility` at send time).
  `AnnotateWeb.PageChannel.handle_out/3` strips it before pushing and, for a
  `staff_only` site, re-derives each subscriber's viewer LIVE
  (`Annotate.Embed.Visibility`) and drops events for threads that subscriber
  may not read. `"__vis"` never reaches a client.
  """

  import Ecto.Query

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Comment
  alias Annotate.Schema.Annotate.Page
  alias Annotate.Schema.Annotate.Site
  alias Annotate.Schema.Annotate.Thread
  alias AnnotateWeb.AnnotateAPI.Renderer

  @pubsub Annotate.PubSub

  @thread_events ~w(thread_resolved thread_reopened thread_anchor_updated)a
  @comment_events ~w(comment_updated comment_deleted)a

  # ── Topics ────────────────────────────────────────────────────

  @doc "sha256 of the client page_key as lowercase hex — the topic hash."
  def page_hash(page_key) when is_binary(page_key),
    do: :crypto.hash(:sha256, page_key) |> Base.encode16(case: :lower)

  @doc "The page topic for a (site, page_key) pair."
  def page_topic(%Site{slug: slug}, page_key) when is_binary(slug),
    do: page_topic(slug, page_key)

  def page_topic(site_slug, page_key) when is_binary(site_slug) and is_binary(page_key),
    do: "page:" <> site_slug <> ":" <> page_hash(page_key)

  # ── Broadcast entry points (called by Annotate.Comments) ──────

  @doc """
  `thread_created` — the transaction in `Comments.create_thread/3` returns the
  thread with `:creator` and `comments[]` (author + attachments) preloaded;
  that exact struct is rendered and broadcast.
  """
  def thread_created(%Site{} = site, page_key, %Thread{} = thread) do
    broadcast!(page_topic(site, page_key), "thread_created", %{
      "thread" => Renderer.thread(thread),
      "__vis" => vis(site.id, site.comment_policy, thread.created_by)
    })

    notify_inbox(site.slug)
  end

  @doc """
  `comment_created` — the comment comes back from the transaction with
  `:author` + `:attachments` preloaded; the topic is resolved from the
  thread's page.
  """
  def comment_created(_page_id, %Comment{} = comment) do
    with {slug, page_key, vis} <- identity_by_thread(comment.thread_id) do
      broadcast!(
        page_topic(slug, page_key),
        "comment_created",
        %{"comment" => Renderer.comment(comment), "__vis" => vis}
      )

      notify_inbox(slug)
    end
  end

  @doc """
  Thread lifecycle events (`:thread_resolved`, `:thread_reopened`,
  `:thread_anchor_updated`) — re-preloads the thread exactly like the REST
  read path (creator + non-deleted comments with author + attachments) and
  broadcasts the rendered thread.
  """
  def thread_event(%Thread{} = thread, event) when event in @thread_events do
    thread = preload_thread(thread)

    with {slug, page_key, vis} <- identity_by_thread(thread.id) do
      broadcast!(page_topic(slug, page_key), Atom.to_string(event), %{
        "thread" => Renderer.thread(thread),
        "__vis" => vis
      })

      notify_inbox(slug)
    end
  end

  @doc """
  Comment events (`:comment_updated`, `:comment_deleted`) — re-preloads the
  comment (author + attachments) and broadcasts it. The soft-deleted comment
  is rendered as-is so subscribers can key removal off the id.
  """
  def comment_event(%Comment{} = comment, event) when event in @comment_events do
    comment = Repo.preload(comment, [:author, :attachments])

    with {slug, page_key, vis} <- identity_by_thread(comment.thread_id) do
      broadcast!(
        page_topic(slug, page_key),
        Atom.to_string(event),
        %{"comment" => Renderer.comment(comment), "__vis" => vis}
      )

      notify_inbox(slug)
    end
  end

  @doc """
  Pings the owner-dashboard inbox of `slug` (Hologram realtime channel
  `{:annotate_inbox, slug}`). Carries NO data: subscribed dashboard pages
  re-fetch through their own authorized command, so nothing leaks to a
  subscriber that lost access. Best-effort: never fails a comment write.
  """
  def inbox_channel(slug) when is_binary(slug), do: {:annotate_inbox, slug}

  def notify_inbox(slug) when is_binary(slug) do
    Hologram.Realtime.broadcast_action(inbox_channel(slug), :inbox_changed, %{})
    :ok
  rescue
    _ -> :ok
  end

  def notify_inbox(_), do: :ok

  # ── Internals ─────────────────────────────────────────────────

  # Same preload shape as Comments.list_threads_with_comments/2 — the REST
  # thread shape and the realtime thread payload must not diverge.
  defp preload_thread(%Thread{} = thread) do
    Repo.preload(thread, [
      :creator,
      comments:
        from(c in Comment,
          where: is_nil(c.deleted_at),
          preload: [:author, :attachments]
        )
    ])
  end

  # {site_slug, page_key, __vis meta} for the thread's page — one query
  # resolving topic + visibility facts (site, read_visibility, creator).
  defp identity_by_thread(thread_id) do
    Repo.one(
      from t in Thread,
        join: p in Page,
        on: t.page_id == p.id,
        join: s in assoc(p, :site),
        where: t.id == ^thread_id,
        select: {s.slug, p.page_key, s.id, s.comment_policy, t.created_by}
    )
    |> case do
      {slug, page_key, site_id, policy, creator_id} ->
        {slug, page_key, vis(site_id, policy, creator_id)}

      nil ->
        nil
    end
  end

  defp vis(site_id, policy, creator_id) do
    %{
      "site_id" => site_id,
      "creator_id" => creator_id,
      "read_visibility" =>
        Atom.to_string(Annotate.Sites.read_visibility(%Site{comment_policy: policy}))
    }
  end

  defp broadcast!(topic, event, payload) when is_binary(topic) and is_binary(event) do
    Phoenix.PubSub.broadcast!(@pubsub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: event,
      payload: payload
    })
  end
end
