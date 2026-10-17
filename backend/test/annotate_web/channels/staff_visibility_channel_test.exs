defmodule AnnotateWeb.StaffVisibilityChannelTest do
  @moduledoc """
  Realtime leg of the staff_only leak tests (T-25): broadcasts on the shared
  page topic are filtered PER SUBSCRIBER in `PageChannel.handle_out/3`, and
  the internal `"__vis"` meta never reaches any client.
  """
  use AnnotateWeb.ChannelCase, async: true

  alias Annotate.Comments
  alias Annotate.Realtime
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.{Commenter, SiteMember}
  alias Annotate.Schema.Users.User
  alias Annotate.Sites

  @page "/rt-vis"

  defp join_as(site, token) do
    params = if token, do: %{"site" => site.slug, "token" => token}, else: %{"site" => site.slug}
    {:ok, socket} = connect(AnnotateWeb.AnnotateSocket, params)

    {:ok, _reply, channel} =
      subscribe_and_join(socket, AnnotateWeb.PageChannel, Realtime.page_topic(site.slug, @page))

    channel
  end

  defp staff_token!(site, role) do
    email = "rt-staff-#{System.unique_integer([:positive])}@corp.example"

    u =
      Repo.insert!(%User{id: Ecto.UUID.generate(), email: email, status: :active, verified: true})

    Repo.insert!(%SiteMember{site_id: site.id, user_id: u.id, role: role})

    c =
      Repo.insert!(%Commenter{
        authentik_sub: "ak-#{System.unique_integer([:positive])}",
        email: email,
        email_verified: true,
        display_name: "RT staff"
      })

    {c, Annotate.Auth.ApiToken.issue_access(c, site, "https://good.example", :bridge)}
  end

  test "B never receives events for A's thread; B's own and staff sockets do; __vis stripped" do
    {site, _} = create_site(comment_policy: %{"read_visibility" => "staff_only"})
    a = create_commenter()
    b = create_commenter()
    # One subscriber per test process keeps push attribution exact.
    join_as(site, issue_access(b, site))

    ta = create_thread!(site, a, %{"page_key" => @page, "body_md" => "A secret"})
    {:ok, _} = Comments.add_comment(ta, a, %{"body_md" => "A reply"})
    {:ok, _} = Comments.resolve_thread(ta, a)
    refute_push "thread_created", _
    refute_push "comment_created", _
    refute_push "thread_resolved", _

    tb = create_thread!(site, b, %{"page_key" => @page, "body_md" => "B mine"})
    assert_push "thread_created", %{"thread" => %{"id" => tb_id}} = payload
    assert tb_id == tb.id
    refute Map.has_key?(payload, "__vis")
  end

  test "staff subscribers receive every thread's events" do
    {site, _} = create_site(comment_policy: %{"read_visibility" => "staff_only"})
    a = create_commenter()
    {_staff, staff_tok} = staff_token!(site, :member)
    join_as(site, staff_tok)

    ta = create_thread!(site, a, %{"page_key" => @page, "body_md" => "A secret"})
    assert_push "thread_created", %{"thread" => %{"id" => ta_id}}
    assert ta_id == ta.id
    {:ok, _} = Comments.add_comment(ta, a, %{"body_md" => "A again"})
    assert_push "comment_created", %{"comment" => %{"body_md" => "A again"}} = p2
    refute Map.has_key?(p2, "__vis")
  end

  test "anonymous subscriber on a staff_only + public_read site receives nothing" do
    {site, _} = create_site(comment_policy: %{"read_visibility" => "staff_only"})
    a = create_commenter()
    join_as(site, nil)

    create_thread!(site, a, %{"page_key" => @page})
    refute_push "thread_created", _
  end

  test "policy flip to staff_only applies to an already-open socket on the next event" do
    {site, _} = create_site()
    a = create_commenter()
    b = create_commenter()
    join_as(site, issue_access(b, site))

    t = create_thread!(site, a, %{"page_key" => @page})
    assert_push "thread_created", _

    {:ok, _} =
      Sites.update_site_security(site, %{"comment_policy" => %{"read_visibility" => "staff_only"}})

    {:ok, _} = Comments.add_comment(t, a, %{"body_md" => "after flip"})
    refute_push "comment_created", _
  end

  test "public sites push to everyone and still strip __vis" do
    {site, _} = create_site()
    a = create_commenter()
    join_as(site, nil)
    create_thread!(site, a, %{"page_key" => @page})
    assert_push "thread_created", payload
    refute Map.has_key?(payload, "__vis")
  end
end
