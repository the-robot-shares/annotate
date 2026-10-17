defmodule AnnotateWeb.Hologram.InboxTest do
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.DashboardCase

  alias Annotate.Comments
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Commenter
  alias Annotate.SiteMembers
  alias Annotate.Sites
  alias AnnotateWeb.Hologram.Components.InboxPanel

  setup do
    owner = gh_user!(30, %{name: "Olive Owner"})
    admin = gh_user!(31)
    member = gh_user!(32)
    stranger = gh_user!(33)

    {:ok, site, _} =
      Sites.create_site_with_owner(
        %{"slug" => "inbox-site", "name" => "Inbox", "allowed_origins" => ["https://i.example"]},
        Repo.reload!(owner.user)
      )

    {:ok, _} = SiteMembers.add_member(site, Repo.reload!(admin.user), :admin)
    {:ok, _} = SiteMembers.add_member(site, Repo.reload!(member.user), :member)

    visitor = Repo.insert!(%Commenter{authentik_sub: "ak-visitor", display_name: "Vera Visitor"})

    {:ok, t1} =
      Comments.create_thread(site, visitor, %{
        "page_key" => "/pricing",
        "url" => "https://i.example/pricing?plan=pro&utm_source=x#top",
        "body_md" => "Typo here\nsecond line </script>",
        "anchor" => %{"css" => "#h1"}
      })

    {:ok, t2} =
      Comments.create_thread(site, visitor, %{
        "page_key" => "/",
        "body_md" => "Old",
        "anchor" => %{"css" => "#x"}
      })

    {:ok, _} = Comments.resolve_thread(t2, visitor)

    %{
      site: site,
      owner: owner,
      admin: admin,
      member: member,
      stranger: stranger,
      t1: t1,
      t2: t2,
      visitor: visitor
    }
  end

  defp cmd(name, params, server), do: run_command(InboxPanel, name, params, server)

  test "member loads the open inbox: page path, significant query, deep link", %{
    member: m,
    t1: t1
  } do
    assert {:loaded, %{threads: [t], counts: %{open: 1, resolved: 1}}} =
             cmd(:load_inbox, %{slug: "inbox-site", status: "open"}, m.server)

    assert t.id == t1.id
    assert t.page_label =~ "/pricing"
    assert t.query_label =~ "plan=pro"
    assert t.deep_link =~ "#annotate=#{t1.id}"

    assert [
             %{
               author: "Vera Visitor",
               body: "Typo here\nsecond line </script>",
               can_delete: false
             }
           ] = t.comments

    assert {:loaded, %{threads: [_]}} =
             cmd(:load_inbox, %{slug: "inbox-site", status: "resolved"}, m.server)

    assert {:loaded, %{threads: [_, _]}} =
             cmd(:load_inbox, %{slug: "inbox-site", status: "all"}, m.server)
  end

  test "reply as the site-team identity (not claimable by host-assert)", %{
    owner: o,
    site: site,
    t1: t1
  } do
    assert {:loaded, %{threads: [t], sent_thread: sent}} =
             cmd(
               :reply,
               %{slug: "inbox-site", status: "open", thread_id: t1.id, body: "Fixed, thanks!"},
               o.server
             )

    assert sent == t1.id
    reply = List.last(t.comments)
    assert reply.body == "Fixed, thanks!" and reply.team and reply.author == "Olive Owner"

    team = Repo.get_by!(Commenter, site_id: site.id, user_id: o.user.id)
    assert team.external_id == nil and team.email == nil and team.authentik_sub == nil

    assert {:failed, %{error: e}} =
             cmd(
               :reply,
               %{slug: "inbox-site", status: "open", thread_id: t1.id, body: "  "},
               o.server
             )

    assert e =~ "Write a reply"
  end

  test "resolve / reopen", %{member: m, t1: t1} do
    assert {:loaded, %{threads: [], counts: %{open: 0, resolved: 2}}} =
             cmd(:resolve, %{slug: "inbox-site", status: "open", thread_id: t1.id}, m.server)

    assert {:loaded, %{counts: %{open: 1}}} =
             cmd(:reopen, %{slug: "inbox-site", status: "open", thread_id: t1.id}, m.server)
  end

  test "soft delete: admin any, member only own team replies", %{admin: a, member: m, t1: t1} do
    [visitor_comment] = t1.comments

    assert {:failed, %{error: e}} =
             cmd(
               :delete_comment,
               %{slug: "inbox-site", status: "open", comment_id: visitor_comment.id},
               m.server
             )

    assert e =~ "admins and owners"

    {:loaded, %{threads: [t]}} =
      cmd(:reply, %{slug: "inbox-site", status: "open", thread_id: t1.id, body: "mine"}, m.server)

    mine = List.last(t.comments)
    assert mine.can_delete

    assert {:loaded, _} =
             cmd(
               :delete_comment,
               %{slug: "inbox-site", status: "open", comment_id: mine.id},
               m.server
             )

    # Deleting the thread's last live comment leaves nothing to show: the
    # thread drops out of the inbox (hidden, not deleted).
    assert {:loaded, %{threads: []}} =
             cmd(
               :delete_comment,
               %{slug: "inbox-site", status: "open", comment_id: visitor_comment.id},
               a.server
             )

    assert Repo.reload!(visitor_comment).deleted_at
  end

  test "tenant isolation: non-members and foreign ids get nothing", %{
    stranger: x,
    owner: o,
    t1: t1
  } do
    assert {:failed, %{error: "Site not found."}} =
             cmd(:load_inbox, %{slug: "inbox-site", status: "open"}, x.server)

    {:ok, other, _} =
      Sites.create_site_with_owner(
        %{"slug" => "other-site", "name" => "O", "allowed_origins" => []},
        Repo.reload!(x.user)
      )

    _ = other

    # x owns other-site but t1 belongs to inbox-site → not found inside other-site
    assert {:failed, %{error: "That thread no longer exists."}} =
             run_command(
               InboxPanel,
               :reply,
               %{slug: "other-site", status: "open", thread_id: t1.id, body: "hi"},
               x.server
             )

    assert {:loaded, _} = cmd(:load_inbox, %{slug: "inbox-site", status: "open"}, o.server)
  end

  test "comment writes ping the data-less inbox channel", %{t1: t1, visitor: v} do
    topic = Hologram.Realtime.channel_topic(Annotate.Realtime.inbox_channel("inbox-site"))
    Phoenix.PubSub.subscribe(Hologram.PubSub, topic)

    {:ok, _} = Comments.add_comment(t1, v, %{"body_md" => "ping"})
    assert_receive {:broadcast_action, {:annotate_inbox, "inbox-site"}, :inbox_changed, params, _}
    assert params == %{}
  end

  test "page HTML never inlines comment bodies (hydration safety); inbox tab is default when open threads exist" do
    conn = signed_in_conn(5)
    user = Repo.get_by!(Annotate.Schema.Users.User, email: "h5@example.com")
    site = Sites.get_site_by_slug("inbox-site")
    {:ok, _} = SiteMembers.add_member(site, user, :member)

    html = conn |> recycle() |> get("/dashboard/sites/inbox-site") |> html_response(200)
    assert html =~ ~s(data-cy="dsh-inbox")
    assert html =~ "Loading comments"
    refute html =~ "Typo here"
    refute html =~ "second line"
  end
end
