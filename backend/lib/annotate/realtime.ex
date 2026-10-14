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
      "thread" => Renderer.thread(thread)
    })
  end

  @doc """
  `comment_created` — the comment comes back from the transaction with
  `:author` + `:attachments` preloaded; the topic is resolved from the
  thread's page.
  """
  def comment_created(page_id, %Comment{} = comment) do
    with {slug, page_key} <- page_identity(page_id) do
      broadcast!(
        page_topic(slug, page_key),
        "comment_created",
        %{"comment" => Renderer.comment(comment)}
      )
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

    with {slug, page_key} <- page_identity(thread.page_id) do
      broadcast!(page_topic(slug, page_key), Atom.to_string(event), %{
        "thread" => Renderer.thread(thread)
      })
    end
  end

  @doc """
  Comment events (`:comment_updated`, `:comment_deleted`) — re-preloads the
  comment (author + attachments) and broadcasts it. The soft-deleted comment
  is rendered as-is so subscribers can key removal off the id.
  """
  def comment_event(%Comment{} = comment, event) when event in @comment_events do
    comment = Repo.preload(comment, [:author, :attachments])

    with {slug, page_key} <- page_identity_by_comment(comment) do
      broadcast!(
        page_topic(slug, page_key),
        Atom.to_string(event),
        %{"comment" => Renderer.comment(comment)}
      )
    end
  end

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

  defp page_identity(page_id) do
    Repo.one(
      from p in Page,
        join: s in assoc(p, :site),
        where: p.id == ^page_id,
        select: {s.slug, p.page_key}
    )
  end

  defp page_identity_by_comment(%Comment{thread_id: thread_id}) do
    Repo.one(
      from p in Page,
        join: t in Thread,
        on: t.page_id == p.id,
        join: s in assoc(p, :site),
        where: t.id == ^thread_id,
        select: {s.slug, p.page_key}
    )
  end

  defp broadcast!(topic, event, payload) when is_binary(topic) and is_binary(event) do
    Phoenix.PubSub.broadcast!(@pubsub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: event,
      payload: payload
    })
  end
end
