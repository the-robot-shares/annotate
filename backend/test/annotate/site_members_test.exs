defmodule Annotate.SiteMembersTest do
  use Annotate.DataCase, async: false

  alias Annotate.Repo
  alias Annotate.SiteMembers
  alias Annotate.Sites
  alias Annotate.Schema.Annotate.{Commenter, SiteMember}
  alias Annotate.Schema.Users.User

  defp user!(email, verified \\ true) do
    Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      email: email,
      status: :active,
      verified: verified
    })
  end

  defp site!(owner, slug \\ nil) do
    slug = slug || "s-#{System.unique_integer([:positive])}"

    {:ok, site, _key} =
      Sites.create_site_with_owner(
        %{"slug" => slug, "name" => slug, "allowed_origins" => ["https://#{slug}.test"]},
        owner
      )

    site
  end

  describe "roles" do
    test "ladder" do
      assert SiteMembers.role_at_least?(:owner, :admin)
      assert SiteMembers.role_at_least?(:admin, :admin)
      refute SiteMembers.role_at_least?(:member, :admin)
      refute SiteMembers.role_at_least?(nil, :member)
      refute SiteMembers.role_at_least?(:bogus, :member)
    end
  end

  describe "add_member" do
    setup do
      owner = user!("owner@example.com")
      %{owner: owner, site: site!(owner)}
    end

    test "verified user by email (case/whitespace-insensitive)", %{site: site, owner: owner} do
      u = user!("bob@example.com")
      assert {:ok, m} = SiteMembers.add_member(site, "  BOB@example.com ", "admin", owner)
      assert m.user_id == u.id and m.role == :admin and m.invited_by == owner.id
    end

    test "S2: unverified user is refused", %{site: site} do
      user!("squat@example.com", false)

      assert {:error, :user_not_verified} =
               SiteMembers.add_member(site, "squat@example.com", :member)
    end

    test "unknown / duplicate / bad role", %{site: site, owner: owner} do
      assert {:error, :user_not_found} =
               SiteMembers.add_member(site, "nobody@example.com", :member)

      assert {:error, :already_member} = SiteMembers.add_member(site, owner, :member)
      user!("c@example.com")
      assert {:error, :invalid_role} = SiteMembers.add_member(site, "c@example.com", "god")
    end
  end

  describe "update_role / remove_member" do
    setup do
      owner = user!("o2@example.com")
      %{owner: owner, site: site!(owner)}
    end

    test "C1: distinct errors", %{site: site, owner: owner} do
      assert {:error, :invalid_role} = SiteMembers.update_role(site, owner.id, "nope")
      assert {:error, :not_found} = SiteMembers.update_role(site, Ecto.UUID.generate(), :admin)
      assert {:error, :last_owner} = SiteMembers.update_role(site, owner.id, :admin)
      assert {:ok, %SiteMember{role: :owner}} = SiteMembers.update_role(site, owner.id, :owner)
    end

    test "C2: removing the last owner returns :last_owner (no crash)", %{site: site, owner: owner} do
      assert {:error, :last_owner} = SiteMembers.remove_member(site, owner.id)
      assert {:error, :not_found} = SiteMembers.remove_member(site, Ecto.UUID.generate())
    end

    test "a second owner allows demoting the first", %{site: site, owner: owner} do
      other = user!("o3@example.com")
      {:ok, _} = SiteMembers.add_member(site, other, :owner)
      assert {:ok, _} = SiteMembers.update_role(site, owner.id, :member)
      assert SiteMembers.member_role(site, owner.id) == :member
      assert {:error, :last_owner} = SiteMembers.remove_member(site, other.id)
    end
  end

  test "S7: concurrent demotion of two owners leaves at least one owner" do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    a = user!("ca@example.com")
    b = user!("cb@example.com")
    site = site!(a)
    {:ok, _} = SiteMembers.add_member(site, b, :owner)

    results =
      [a, b]
      |> Enum.map(fn u -> Task.async(fn -> SiteMembers.update_role(site, u.id, :member) end) end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :last_owner}, &1)) == 1

    assert Repo.aggregate(
             from(m in SiteMember, where: m.site_id == ^site.id and m.role == :owner),
             :count
           ) == 1
  end

  test "list_sites_for_user: only the user's sites, with role + count" do
    a = user!("la@example.com")
    b = user!("lb@example.com")
    s1 = site!(a, "aaa-site")
    _s2 = site!(b, "bbb-site")
    {:ok, _} = SiteMembers.add_member(s1, b, :member)

    assert [%{site: %{slug: "aaa-site"}, role: :owner, member_count: 2}] =
             SiteMembers.list_sites_for_user(a.id)

    assert ["aaa-site", "bbb-site"] =
             b.id |> SiteMembers.list_sites_for_user() |> Enum.map(& &1.site.slug)
  end

  describe "team_role_for_commenter (bridge)" do
    setup do
      owner = user!("team@example.com")
      %{owner: owner, site: site!(owner)}
    end

    test "verified Authentik commenter + verified user → role", %{site: site} do
      c = %Commenter{authentik_sub: "ak-1", email: "Team@example.com", email_verified: true}
      assert SiteMembers.team_role_for_commenter(site, c) == :owner
    end

    test "fails closed", %{site: site} do
      refute SiteMembers.team_role_for_commenter(site, %Commenter{
               authentik_sub: "ak-1",
               email: "team@example.com",
               email_verified: false
             })

      # S1: host-asserted rows never bridge, even with email_verified forced true
      refute SiteMembers.team_role_for_commenter(site, %Commenter{
               external_id: "host-1",
               email: "team@example.com",
               email_verified: true
             })

      refute SiteMembers.team_role_for_commenter(site, %Commenter{
               authentik_sub: "ak-2",
               email: "stranger@example.com",
               email_verified: true
             })
    end

    test "S2: unverified dashboard user never bridges", %{site: site} do
      u = user!("unv@example.com", false)
      Repo.insert!(%SiteMember{site_id: site.id, user_id: u.id, role: :admin})

      refute SiteMembers.team_role_for_commenter(site, %Commenter{
               authentik_sub: "ak-3",
               email: "unv@example.com",
               email_verified: true
             })
    end
  end

  test "grant_owner_by_email" do
    owner = user!("g-owner@example.com")
    site = site!(owner, "grant-site")
    user!("g-new@example.com")
    user!("g-unv@example.com", false)

    assert :ok = SiteMembers.grant_owner_by_email("grant-site", "g-new@example.com")
    assert :ok = SiteMembers.grant_owner_by_email("grant-site", "g-new@example.com")

    assert {:error, :user_not_verified} =
             SiteMembers.grant_owner_by_email("grant-site", "g-unv@example.com")

    assert {:error, :user_not_found} =
             SiteMembers.grant_owner_by_email("grant-site", "x@example.com")

    assert {:error, :site_not_found} =
             SiteMembers.grant_owner_by_email("nope", "g-new@example.com")

    assert SiteMembers.member_role(site, Repo.get_by!(User, email: "g-new@example.com").id) ==
             :owner
  end
end
