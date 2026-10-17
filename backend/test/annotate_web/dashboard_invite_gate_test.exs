defmodule AnnotateWeb.DashboardInviteGateTest do
  @moduledoc """
  Invite-only dashboard (user decision 2026-10-17): uninvited accounts are
  pending and get NOTHING but the interstitial + sign-out; verified @noizu.com
  is exempt (exact domain); invites (scaffold invite_tokens, org-less) are
  hashed at rest, single-use, expiring, revocable, optionally email-bound and
  consumed atomically on activation. GitHub and Google behave the same.
  """
  use AnnotateWeb.ConnCase, async: false

  import AnnotateWeb.DashboardCase
  import Ecto.Query

  alias Annotate.Dashboard.{Access, GoogleLogin, Invites, OAuthLogin}
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.{Commenter, OAuthIdentity, SiteMember}
  alias Annotate.Schema.Organizations.InviteToken
  alias Annotate.Schema.Users.User
  alias Annotate.{SiteMembers, Sites}
  alias AnnotateWeb.Hologram.Components.InboxPanel
  alias AnnotateWeb.Hologram.Pages.{DashboardInvitesPage, DashboardSitePage, DashboardSitesPage}

  defp gh(uid, email, extra \\ %{}),
    do:
      Map.merge(
        %{
          provider: "github",
          uid: to_string(uid),
          login: "u#{uid}",
          email: email,
          name: nil,
          avatar_url: nil,
          hd: nil
        },
        extra
      )

  defp server_for(user) do
    {:ok, session} = Annotate.Auth.SSO.create_session(user, :github)

    {:ok, token, _} =
      Annotate.Guardian.encode_and_sign(session, %{}, token_type: "access", ttl: {1, :hour})

    {%Hologram.Server{session: %{"access_token" => token}}, token}
  end

  defp staff! do
    {:ok, %{user: u}} = OAuthLogin.sign_in(gh(9001, "staff@noizu.com"))

    Repo.update_all(
      from(u in User, where: u.id == ^u.id),
      set: [invite_quota: 5]
    )

    Repo.get!(User, u.id)
  end

  defp invite!(opts \\ []) do
    {:ok, invite, raw} = Invites.create(staff!(), opts)
    {invite, raw}
  end

  # ── domain exemption ─────────────────────────────────────────

  describe "exemption is the EXACT verified @noizu.com domain" do
    test "exact domain only; subdomains / lookalikes / Google hd mismatch do not count" do
      assert Access.exempt?(%{email: "a@noizu.com"})
      assert Access.exempt?(%{email: "A@NOIZU.COM"})
      refute Access.exempt?(%{email: "a@eng.noizu.com"})
      refute Access.exempt?(%{email: "a@noizu.com.evil.test"})
      refute Access.exempt?(%{email: "a@evilnoizu.com"})
      refute Access.exempt?(%{email: "a@noizu.com@evil.test"})
      refute Access.exempt?(%{email: "a@noizu.com", hd: "evil.test"})
      assert Access.exempt?(%{email: "a@noizu.com", hd: "noizu.com"})
    end

    test "noizu.com user is active and can create a site" do
      {:ok, %{user: u}} = OAuthLogin.sign_in(gh(1, "dev@noizu.com"))
      u = Repo.get!(User, u.id)
      assert u.status == :active

      assert {:ok, _site, _key} =
               Sites.create_site_with_owner(
                 %{"slug" => "nz-site", "name" => "N", "allowed_origins" => []},
                 u
               )
    end
  end

  # ── uninvited (pending) gets nothing ─────────────────────────

  describe "an uninvited non-noizu account" do
    setup do
      {:ok, %{user: u}} = OAuthLogin.sign_in(gh(2, "outsider@example.com"))
      user = Repo.get!(User, u.id)
      assert user.status == :pending

      owner = staff!()

      {:ok, site, _} =
        Sites.create_site_with_owner(
          %{"slug" => "gated", "name" => "G", "allowed_origins" => []},
          owner
        )

      {server, token} = server_for(user)
      %{user: user, site: site, server: server, token: token}
    end

    test "every dashboard page redirects to the interstitial" do
      {:ok, %{user: u}} = OAuthLogin.sign_in(gh(3, "browse@example.com"))
      {:ok, session} = Annotate.Auth.SSO.create_session(Repo.get!(User, u.id), :github)
      {:ok, code} = Annotate.Auth.SSOCode.create(session.id)
      conn = get(build_conn(), "/auth/sso-callback?code=#{code}&provider=github")

      for path <- ["/dashboard", "/dashboard/sites/gated", "/dashboard/invites"] do
        res = conn |> recycle() |> get(path)
        assert res.status == 302, path
        assert redirected_to(res) == "/auth/invite-required", path
      end

      html = conn |> recycle() |> get("/auth/invite-required") |> html_response(200)
      assert html =~ "invite-only"
    end

    test "every dashboard command and the context refuse (no data, no site creation)", %{
      user: user,
      server: s
    } do
      assert {:create_failed, %{error: e}} =
               run_command(
                 DashboardSitesPage,
                 :create_site,
                 %{name: "X", slug: "pend-site", origins: ""},
                 s
               )

      assert e =~ "invite-only"

      assert {:error, :invite_required} =
               Sites.create_site_with_owner(
                 %{"slug" => "pend2", "name" => "P", "allowed_origins" => []},
                 user
               )

      # Even a membership row (e.g. added before the gate) grants nothing.
      Repo.insert!(%SiteMember{
        site_id: Sites.get_site_by_slug("gated").id,
        user_id: user.id,
        role: :owner
      })

      assert {:failed, %{error: e2}} =
               run_command(DashboardSitePage, :rotate_key, %{slug: "gated"}, s)

      assert e2 =~ "invite-only"

      assert {:failed, %{error: e3}} =
               run_command(InboxPanel, :load_inbox, %{slug: "gated", status: "open"}, s)

      assert e3 =~ "invite-only"

      assert {:failed, _} =
               run_command(
                 DashboardInvitesPage,
                 :create,
                 %{email: "", days: "14", max_uses: "1"},
                 s
               )
    end

    test "no REST API access (403 invite_required)", %{token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/v1/organizations")

      assert %{"error" => "invite_required"} = json_response(conn, 403)
    end

    test "no team role via the email bridge, and owners can't add them", %{user: user, site: site} do
      Repo.insert!(%SiteMember{site_id: site.id, user_id: user.id, role: :admin})
      c = %Commenter{authentik_sub: "ak-out", email: "outsider@example.com", email_verified: true}
      assert SiteMembers.team_role_for_commenter(site, c) == nil
      assert {:error, :user_not_active} = SiteMembers.add_member(site, user, :member)
    end
  end

  # ── invites ──────────────────────────────────────────────────

  describe "invites through the OAuth round trip" do
    defp flow(query) do
      conn = get(build_conn(), "/auth/github?" <> URI.encode_query(query))
      conn |> recycle() |> get(redirected_to(conn))
    end

    test "a valid invite activates the new account and is consumed (hash-only at rest)" do
      {invite, raw} = invite!()
      stored = Repo.get!(InviteToken, invite.id)
      refute stored.token_hash == raw
      refute inspect(Map.from_struct(stored)) =~ raw
      assert byte_size(Base.url_decode64!(raw, padding: false)) * 8 >= 128

      conn = flow(%{stub_id: "500", stub_email: "invited@example.com", invite: raw})
      assert redirected_to(conn) =~ ~r{^/auth/sso-callback\?code=[^&]+&provider=github$}
      assert %User{status: :active} = Repo.get_by!(User, email: "invited@example.com")
      assert Repo.get!(InviteToken, invite.id).uses == 1

      # reused: a second person cannot use the spent single-use invite
      conn2 = flow(%{stub_id: "501", stub_email: "second@example.com", invite: raw})
      assert redirected_to(conn2) =~ "invite_error=invite_exhausted"
      assert %User{status: :pending} = Repo.get_by!(User, email: "second@example.com")
    end

    test "expired, revoked and unknown tokens are rejected (account stays pending)" do
      {expired, raw_expired} = invite!()

      Repo.update!(
        Ecto.Changeset.change(expired, expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      )

      {revoked, raw_revoked} = invite!()
      :ok = Invites.revoke(revoked.id)

      for {raw, n} <- [
            {raw_expired, 510},
            {raw_revoked, 511},
            {"not-a-real-invite-token-xxxxxxxx", 512}
          ] do
        conn = flow(%{stub_id: "#{n}", stub_email: "x#{n}@example.com", invite: raw})
        assert redirected_to(conn) =~ "invite_error=invalid_token"
        assert %User{status: :pending} = Repo.get_by!(User, email: "x#{n}@example.com")
      end
    end

    test "an email-bound invite rejects a different verified email, accepts the bound one" do
      {_invite, raw} = invite!(email: "bound@example.com")
      conn = flow(%{stub_id: "520", stub_email: "other@example.com", invite: raw})
      assert redirected_to(conn) =~ "invite_error=invalid_token"
      conn = flow(%{stub_id: "521", stub_email: "bound@example.com", invite: raw})
      refute redirected_to(conn) =~ "invite_error"
      assert %User{status: :active} = Repo.get_by!(User, email: "bound@example.com")
    end

    test "an existing active user is unaffected (no invite needed to sign in again)" do
      {:ok, %{user: u}} = OAuthLogin.sign_in(gh(530, "veteran@example.com"))
      Repo.update!(Ecto.Changeset.change(Repo.get!(User, u.id), status: :active))
      {:ok, %{user: again}} = OAuthLogin.sign_in(gh(530, "veteran@example.com"))
      assert Repo.get!(User, again.id).status == :active
    end
  end

  describe "invites page (staff only)" do
    test "staff create → link shown once; list shows prefix only; revoke" do
      staff = staff!()
      {s, _} = server_for(staff)

      assert {:created, %{link: link, invites: [row | _]}} =
               run_command(
                 DashboardInvitesPage,
                 :create,
                 %{email: "", days: "14", max_uses: "1"},
                 s
               )

      assert link =~ "/sign-up?invite="
      raw = link |> URI.parse() |> Map.get(:query) |> URI.decode_query() |> Map.get("invite")
      refute inspect(row) =~ raw
      assert row.state == "active"

      assert {:revoked, %{invites: [%{state: "revoked"} | _]}} =
               run_command(DashboardInvitesPage, :revoke, %{id: row.id}, s)
    end

    test "a non-staff active user cannot issue invites" do
      user = gh_user!(540).user
      {s, _} = server_for(Repo.get!(User, user.id))

      assert {:failed, %{error: e}} =
               run_command(
                 DashboardInvitesPage,
                 :create,
                 %{email: "", days: "14", max_uses: "1"},
                 s
               )

      assert e =~ "staff"
    end
  end

  # ── Google ───────────────────────────────────────────────────

  describe "Google sign-in" do
    test "profile requires email_verified; hd rides along" do
      auth = fn user ->
        %Ueberauth.Auth{
          uid: user["sub"],
          info: %Ueberauth.Auth.Info{},
          extra: %Ueberauth.Auth.Extra{raw_info: %{user: user}}
        }
      end

      assert {:ok, %{provider: "google", uid: "g1", email: "a@noizu.com", hd: "noizu.com"}} =
               GoogleLogin.profile_from_auth(
                 auth.(%{
                   "sub" => "g1",
                   "email" => "A@noizu.com",
                   "email_verified" => true,
                   "hd" => "noizu.com"
                 })
               )

      assert {:error, :no_verified_email} =
               GoogleLogin.profile_from_auth(
                 auth.(%{"sub" => "g2", "email" => "a@noizu.com", "email_verified" => false})
               )
    end

    test "round trip: unverified email refused; noizu.com with matching hd is active" do
      conn =
        get(
          build_conn(),
          "/auth/google?" <>
            URI.encode_query(%{
              stub_sub: "g10",
              stub_email: "nv@example.com",
              stub_verified: "false"
            })
        )

      conn = conn |> recycle() |> get(redirected_to(conn))
      assert redirected_to(conn) == "/auth/sso-callback?error=google_email_unverified"
      refute Repo.get_by(User, email: "nv@example.com")

      conn =
        get(
          build_conn(),
          "/auth/google?" <>
            URI.encode_query(%{stub_sub: "g11", stub_email: "g@noizu.com", stub_hd: "noizu.com"})
        )

      conn = conn |> recycle() |> get(redirected_to(conn))
      assert redirected_to(conn) =~ "provider=google"
      assert %User{status: :active} = Repo.get_by!(User, email: "g@noizu.com")
    end

    test "noizu.com email with a foreign hd is NOT exempt" do
      {:ok, %{user: u}} =
        OAuthLogin.sign_in(%{
          provider: "google",
          uid: "g20",
          login: nil,
          email: "odd@noizu.com",
          name: nil,
          avatar_url: nil,
          hd: "evil.test"
        })

      assert Repo.get!(User, u.id).status == :pending
    end

    test "GitHub + Google with the same verified email → one account, two identities" do
      {:ok, %{user: a}} = OAuthLogin.sign_in(gh(30, "both@noizu.com"))

      {:ok, %{user: b}} =
        OAuthLogin.sign_in(%{
          provider: "google",
          uid: "g30",
          login: nil,
          email: "both@noizu.com",
          name: nil,
          avatar_url: nil,
          hd: "noizu.com"
        })

      assert a.id == b.id
      assert Repo.aggregate(from(i in OAuthIdentity, where: i.user_id == ^a.id), :count) == 2
    end

    test "a strategy crash is a friendly page" do
      conn =
        get(
          build_conn(),
          "/auth/google?" <> URI.encode_query(%{stub_sub: "g40", stub_crash: "tls"})
        )

      conn = conn |> recycle() |> get(redirected_to(conn))
      assert redirected_to(conn) == "/auth/sso-callback?error=google_failed"
    end
  end
end
