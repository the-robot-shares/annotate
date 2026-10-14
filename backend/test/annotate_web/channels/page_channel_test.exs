defmodule AnnotateWeb.PageChannelEventTest do
  @moduledoc """
  One test per realtime event: after the matching commit in
  `Annotate.Comments`, the page topic receives EXACTLY ONE broadcast whose
  payload is rendered by the same JSON renderer the REST API uses
  (`AnnotateWeb.AnnotateAPI.Renderer` — attachment presigned GET urls
  included).
  """

  use AnnotateWeb.ChannelCase, async: true

  # (Ecto.Query comes in via Annotate.DataCase's using-quote.)

  alias Annotate.Comments
  alias Annotate.Realtime
  alias Annotate.Repo
  alias AnnotateWeb.AnnotateAPI.Renderer

  defp page_key, do: "/rt-events-#{System.unique_integer([:positive])}"

  defp join_page(site, page_key) do
    {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, %{"site" => site.slug})

    {:ok, _reply, channel} =
      subscribe_and_join(
        socket,
        AnnotateWeb.PageChannel,
        Realtime.page_topic(site.slug, page_key)
      )

    channel
  end

  # Mirrors Realtime's thread preload (== the REST read path).
  defp rendered_thread(thread) do
    Renderer.thread(Repo.preload(thread, [:creator, comments: live_comments_query()]))
  end

  defp live_comments_query do
    from(c in Annotate.Schema.Annotate.Comment,
      where: is_nil(c.deleted_at),
      preload: [:author, :attachments]
    )
  end

  # ── thread lifecycle ──────────────────────────────────────────

  test "thread_created fires exactly once with the rendered thread" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)

    {:ok, thread} =
      Comments.create_thread(site, commenter, %{
        "page_key" => page,
        "anchor" => %{"css" => "h1"},
        "body_md" => "first!"
      })

    payload = %{"thread" => Renderer.thread(thread)}
    assert_broadcast "thread_created", ^payload
    refute_broadcast "thread_created", %{}, 0
  end

  test "thread_resolved fires exactly once with the rendered thread" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})

    {:ok, thread} = Comments.resolve_thread(thread, commenter)

    payload = %{"thread" => rendered_thread(thread)}
    assert_broadcast "thread_resolved", ^payload
    refute_broadcast "thread_resolved", %{}, 0
  end

  test "thread_reopened fires exactly once with the rendered thread" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})
    {:ok, thread} = Comments.resolve_thread(thread, commenter)

    {:ok, thread} = Comments.reopen_thread(thread)

    payload = %{"thread" => rendered_thread(thread)}
    assert_broadcast "thread_reopened", ^payload
    refute_broadcast "thread_reopened", %{}, 0
  end

  test "thread_anchor_updated fires exactly once with the rendered thread" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})

    {:ok, thread} = Comments.set_thread_anchor(thread, %{"css" => "#new-anchor"})

    payload = %{"thread" => rendered_thread(thread)}
    assert_broadcast "thread_anchor_updated", ^payload
    refute_broadcast "thread_anchor_updated", %{}, 0
  end

  # ── comments ──────────────────────────────────────────────────

  test "comment_created fires exactly once with the rendered comment" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})

    {:ok, comment} = Comments.add_comment(thread, commenter, %{"body_md" => "a reply"})

    payload = %{"comment" => Renderer.comment(comment)}
    assert_broadcast "comment_created", ^payload
    refute_broadcast "comment_created", %{}, 0
  end

  test "comment_updated fires exactly once with the rendered comment" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})
    root = hd(thread.comments)

    {:ok, comment} = Comments.update_comment_body(root, "edited body")

    payload = %{"comment" => Renderer.comment(Repo.preload(comment, [:author, :attachments]))}
    assert_broadcast "comment_updated", ^payload
    refute_broadcast "comment_updated", %{}, 0
  end

  test "comment_deleted fires exactly once with the rendered comment" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)
    thread = create_thread!(site, commenter, %{"page_key" => page})
    root = hd(thread.comments)

    {:ok, comment} = Comments.soft_delete_comment(root)

    payload = %{"comment" => Renderer.comment(Repo.preload(comment, [:author, :attachments]))}
    assert_broadcast "comment_deleted", ^payload
    refute_broadcast "comment_deleted", %{}, 0
  end

  test "thread_created payload carries attachment presigned GET urls" do
    {site, _} = create_site()
    commenter = create_commenter()
    page = page_key()
    join_page(site, page)

    {:ok, attachment, _upload_url} =
      Comments.create_pending_attachment(site, commenter, %{
        filename: "shot.png",
        content_type: "image/png",
        bytes: 1234,
        kind: :image
      })

    {:ok, attachment} = Comments.complete_attachment(attachment, %{"width" => 10, "height" => 10})

    {:ok, thread} =
      Comments.create_thread(site, commenter, %{
        "page_key" => page,
        "anchor" => %{"css" => "h2"},
        "body_md" => "with attachment",
        "attachment_ids" => [attachment.id]
      })

    assert_broadcast "thread_created", %{"thread" => rendered}

    broadcast_attachment = rendered["comments"] |> hd() |> Map.fetch!("attachments") |> hd()
    assert is_binary(broadcast_attachment["url"]) and byte_size(broadcast_attachment["url"]) > 0

    # Everything but the (time-dependent, presigned) url matches the REST
    # renderer exactly.
    assert Map.drop(broadcast_attachment, ["url"]) ==
             Map.drop(Renderer.attachment(attachment), ["url"])
  end

  # ── read-only channel ─────────────────────────────────────────

  test "client pushes are rejected — the channel is broadcast-only" do
    {site, _} = create_site()
    page = page_key()
    channel = join_page(site, page)

    ref = push(channel, "comment_created", %{"body_md" => "smuggled"})
    assert_reply ref, :error, %{reason: "read_only"}

    ref = push(channel, "anything", %{})
    assert_reply ref, :error, %{reason: "read_only"}
  end

  # ── isolation ─────────────────────────────────────────────────

  test "events only reach the page topic they belong to" do
    {site, _} = create_site()
    commenter = create_commenter()
    this_page = page_key()
    other_page = page_key()
    join_page(site, this_page)

    Comments.create_thread(site, commenter, %{
      "page_key" => other_page,
      "anchor" => %{"css" => "h1"},
      "body_md" => "elsewhere"
    })

    refute_broadcast "thread_created", %{}, 0
  end
end
