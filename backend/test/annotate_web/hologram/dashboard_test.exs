defmodule AnnotateWeb.Hologram.DashboardTest do
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.DashboardCase

  alias Annotate.Repo
  alias Annotate.SiteMembers
  alias Annotate.Sites
  alias AnnotateWeb.Hologram.Pages.{DashboardSitePage, DashboardSitesPage}

  defp create!(server, slug, origins \\ "https://ex.example") do
    {:site_created, reply} =
      run_command(
        DashboardSitesPage,
        :create_site,
        %{name: "Site #{slug}", slug: slug, origins: origins},
        server
      )

    reply
  end

  describe "sites list + add site" do
    test "create: atomic owner grant, key returned once, list refreshed" do
      %{user: u, server: s} = gh_user!(1)
      reply = create!(s, "alpha", "https://a.example\nhttps://b.example")
      assert reply.slug == "alpha" and is_binary(reply.key)
      assert [%{slug: "alpha", role: "owner", member_count: 1}] = reply.sites
      site = Sites.get_site_by_slug("alpha")
      assert site.allowed_origins == ["https://a.example", "https://b.example"]
      assert SiteMembers.member_role(site, u.id) == :owner
      refute inspect(reply.sites) =~ reply.key
    end

    test "validation errors are surfaced, nothing created" do
      %{server: s} = gh_user!(2)

      assert {:create_failed, %{error: msg}} =
               run_command(
                 DashboardSitesPage,
                 :create_site,
                 %{name: "X", slug: "beta", origins: "*"},
                 s
               )

      assert msg =~ "exact"
      refute Sites.get_site_by_slug("beta")

      create!(s, "taken")

      assert {:create_failed, %{error: "That site code is taken."}} =
               run_command(
                 DashboardSitesPage,
                 :create_site,
                 %{name: "Y", slug: "taken", origins: ""},
                 gh_user!(3).server
               )
    end

    test "signed-out command is refused" do
      assert {:create_failed, _} =
               run_command(
                 DashboardSitesPage,
                 :create_site,
                 %{name: "Z", slug: "zeta", origins: ""},
                 %Hologram.Server{}
               )

      refute Sites.get_site_by_slug("zeta")
    end
  end

  describe "site page commands re-authorize per call" do
    setup do
      owner = gh_user!(10)
      create!(owner.server, "gamma")
      site = Sites.get_site_by_slug("gamma")
      admin = gh_user!(11)
      member = gh_user!(12)
      stranger = gh_user!(13)
      {:ok, _} = SiteMembers.add_member(site, Repo.reload!(admin.user), :admin)
      {:ok, _} = SiteMembers.add_member(site, Repo.reload!(member.user), :member)
      %{owner: owner, admin: admin, member: member, stranger: stranger, site: site}
    end

    test "display settings: admin yes, member no", %{admin: a, member: m} do
      params = %{
        slug: "gamma",
        name: "Gamma 2",
        public_read: "false",
        max_upload_mb: "5",
        default_visibility: "internal"
      }

      assert {:failed, %{error: msg}} =
               run_command(DashboardSitePage, :save_display, params, m.server)

      assert msg =~ "role"

      assert {:updated, %{site: %{name: "Gamma 2"}}} =
               run_command(DashboardSitePage, :save_display, params, a.server)

      site = Sites.get_site_by_slug("gamma")
      refute Sites.public_read?(site)
      assert Sites.max_upload_mb(site) == 5
    end

    test "security settings + rotation: owner only", %{owner: o, admin: a, site: site} do
      params = %{
        slug: "gamma",
        origins: "https://new.example",
        allow_anonymous: "false",
        trust_host_roles: "true",
        required_groups: "",
        allowed_email_domains: "corp.example"
      }

      assert {:failed, _} = run_command(DashboardSitePage, :save_security, params, a.server)
      assert {:updated, _} = run_command(DashboardSitePage, :save_security, params, o.server)
      s = Sites.get_site_by_slug("gamma")
      assert s.allowed_origins == ["https://new.example"]
      assert Sites.trust_host_roles?(s)

      assert {:failed, %{error: e}} =
               run_command(
                 DashboardSitePage,
                 :save_security,
                 %{params | origins: "https://x.example/path"},
                 o.server
               )

      assert e =~ "exact"

      assert {:failed, _} =
               run_command(DashboardSitePage, :rotate_key, %{slug: "gamma"}, a.server)

      assert {:key_rotated, %{key: key}} =
               run_command(DashboardSitePage, :rotate_key, %{slug: "gamma"}, o.server)

      assert Sites.get_site_by_slug("gamma").service_key_hash ==
               Annotate.Auth.ServiceKey.hash(key)

      refute Sites.get_site_by_slug("gamma").service_key_hash == site.service_key_hash
    end

    test "members: owner manages; last-owner lockout surfaced; verified users only", %{
      owner: o,
      member: m
    } do
      assert {:failed, _} =
               run_command(
                 DashboardSitePage,
                 :add_member,
                 %{slug: "gamma", email: "gh13@example.com", role: "member"},
                 m.server
               )

      assert {:updated, %{members: members}} =
               run_command(
                 DashboardSitePage,
                 :add_member,
                 %{slug: "gamma", email: "gh13@example.com", role: "member"},
                 o.server
               )

      assert Enum.any?(members, &(&1.email == "gh13@example.com"))

      assert {:failed, %{error: e}} =
               run_command(
                 DashboardSitePage,
                 :add_member,
                 %{slug: "gamma", email: "nobody@example.com", role: "member"},
                 o.server
               )

      assert e =~ "sign in with GitHub"

      assert {:failed, %{error: lock}} =
               run_command(
                 DashboardSitePage,
                 :change_role,
                 %{slug: "gamma", user_id: o.user.id, role: "member"},
                 o.server
               )

      assert lock =~ "at least one owner"

      assert {:failed, _} =
               run_command(
                 DashboardSitePage,
                 :remove_member,
                 %{slug: "gamma", user_id: o.user.id},
                 o.server
               )

      assert {:updated, _} =
               run_command(
                 DashboardSitePage,
                 :remove_member,
                 %{slug: "gamma", user_id: m.user.id},
                 o.server
               )
    end

    test "a non-member gets not-found for every command (tenant isolation)", %{stranger: x} do
      for {cmd, p} <- [
            {:save_display,
             %{
               slug: "gamma",
               name: "h",
               public_read: "true",
               max_upload_mb: "1",
               default_visibility: "public"
             }},
            {:rotate_key, %{slug: "gamma"}},
            {:remove_member, %{slug: "gamma", user_id: x.user.id}}
          ] do
        assert {:failed, %{error: "Site not found."}} =
                 run_command(DashboardSitePage, cmd, p, x.server)
      end
    end

    test "removed member loses access on the next command (no stale tab)", %{admin: a} do
      {:ok, _} = SiteMembers.remove_member(Sites.get_site_by_slug("gamma"), a.user.id)

      assert {:failed, %{error: "Site not found."}} =
               run_command(
                 DashboardSitePage,
                 :save_display,
                 %{
                   slug: "gamma",
                   name: "x",
                   public_read: "true",
                   max_upload_mb: "1",
                   default_visibility: "public"
                 },
                 a.server
               )
    end
  end

  describe "HTTP renders" do
    test "GitHub sign-in → /dashboard → add site → site page with snippet + site code" do
      conn = signed_in_conn(1)
      html = conn |> recycle() |> get("/dashboard") |> html_response(200)
      assert html =~ "No sites yet"
      assert html =~ "Create your first site"
      assert html =~ "<noizu-footer-brand"
      assert html =~ ~s(data-cy="footer-terms")

      user = Repo.get_by!(Annotate.Schema.Users.User, email: "h1@example.com")

      {:ok, _site, _key} =
        Sites.create_site_with_owner(
          %{"slug" => "delta", "name" => "Delta", "allowed_origins" => ["https://d.example"]},
          user
        )

      html = conn |> recycle() |> get("/dashboard") |> html_response(200)
      assert html =~ "/dashboard/sites/delta"

      page = conn |> recycle() |> get("/dashboard/sites/delta") |> html_response(200)

      [snippet] =
        Regex.run(~r{<code id="dsh-snippet-code">(.*?)</code>}s, page, capture: :all_but_first)

      assert snippet =~ ~r/noizu-page-comments site=(&quot;|")delta(&quot;|")/
      assert page =~ "noizu-page-comments"
      assert page =~ "Copy snippet"
    end

    test "another tenant's site renders not found; anonymous is sent to sign-in" do
      owner = gh_user!(20)
      create!(owner.server, "epsilon")

      page =
        signed_in_conn(2) |> recycle() |> get("/dashboard/sites/epsilon") |> html_response(200)

      assert page =~ "Site not found."
      refute page =~ "dsh-snippet-code"

      conn = get(build_conn(), "/dashboard")
      assert conn.status == 302
    end
  end
end
