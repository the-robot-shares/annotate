defmodule Starter.Auth.SSOTest do
  use Starter.DataCase

  alias Starter.Schema.Auth.Providers.Provider
  alias Starter.Schema.Users.User

  setup do
    previous_domains = Application.get_env(:starter, :sso_domains)
    previous_auto_approve = Application.get_env(:starter, :sso_auto_approve_domains)
    previous_policies = Application.get_env(:starter, :sso_domain_policies)
    previous_require_invite = Application.get_env(:starter, :sso_require_invite)

    Application.put_env(:starter, :sso_domains, %{})
    Application.put_env(:starter, :sso_auto_approve_domains, [])
    Application.put_env(:starter, :sso_domain_policies, %{})
    # Legacy auto-provision tests opt out explicitly; gate tests set true.
    Application.put_env(:starter, :sso_require_invite, false)

    on_exit(fn ->
      Application.put_env(:starter, :sso_domains, previous_domains)
      Application.put_env(:starter, :sso_auto_approve_domains, previous_auto_approve)
      Application.put_env(:starter, :sso_domain_policies, previous_policies)
      Application.put_env(:starter, :sso_require_invite, previous_require_invite)
    end)
  end

  test "auto-provisioned SSO users are pending until profile completion" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: false)
    email = "sso-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, session} =
             Starter.Auth.SSO.authenticate_sso(:google, %{
               email: email,
               name: %{first: "Ada", last: "Lovelace"},
               sub: "google-#{System.unique_integer([:positive])}"
             })

    assert {:ref, Starter.Users.User, user_id} = session.user

    user = Starter.Repo.get!(User, user_id)
    assert user.email == email
    assert user.status == :pending
    assert user.verified == true
    assert user.profile_completed_at == nil
    assert user.mobile_phone == nil
  end

  test "auto-approved SSO domain creates active incomplete users" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: true)
    email = "sso-approved-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, session} =
             Starter.Auth.SSO.authenticate_sso("google", %{
               email: email,
               name: %{first: "Ada", last: "Lovelace"},
               sub: "google-approved-#{System.unique_integer([:positive])}"
             })

    assert {:ref, Starter.Users.User, user_id} = session.user

    user = Starter.Repo.get!(User, user_id)
    assert user.status == :active
    assert user.approved_at
    assert user.profile_completed_at == nil
  end

  test "SSO is rejected when the email domain is not available for the provider" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["oidc"], auto_approve: true)

    assert {:error, :sso_not_allowed} =
             Starter.Auth.SSO.authenticate_sso(:google, %{
               email: "sso-disabled-#{System.unique_integer([:positive])}@example.com",
               name: %{first: "Ada", last: "Lovelace"},
               sub: "google-disabled-#{System.unique_integer([:positive])}"
             })
  end

  # ── register open, app gated (Starter.Auth.InviteGate) ────────────────────

  test "register open: unknown SSO identity without an invite is created :pending (both flag values)" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: false)

    for flag <- [true, false] do
      Application.put_env(:starter, :sso_require_invite, flag)
      email = "gated-#{flag}-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, session} =
               Starter.Auth.SSO.authenticate_sso(:google, %{
                 email: email,
                 name: %{first: "Ada", last: "Lovelace"},
                 sub: "google-gated-#{System.unique_integer([:positive])}"
               })

      assert {:ref, Starter.Users.User, user_id} = session.user
      user = Starter.Repo.get!(User, user_id)
      assert user.status == :pending
      assert user.approved_at == nil
      assert Starter.Auth.InviteGate.required?(user)
    end
  end

  test "register open: auto-approve SSO domain is :active for both flag values" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: true)

    for flag <- [true, false] do
      Application.put_env(:starter, :sso_require_invite, flag)
      email = "auto-#{flag}-#{System.unique_integer([:positive])}@example.com"

      assert {:ok, session} =
               Starter.Auth.SSO.authenticate_sso(:google, %{
                 email: email,
                 sub: "google-auto-#{System.unique_integer([:positive])}"
               })

      assert {:ref, Starter.Users.User, user_id} = session.user
      user = Starter.Repo.get!(User, user_id)
      assert user.status == :active
      refute Starter.Auth.InviteGate.required?(user)
    end
  end

  test "existing pending SSO account still gets a session (the gate holds it, not login)" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: false)
    email = "repeat-#{System.unique_integer([:positive])}@example.com"
    attrs = %{email: email, sub: "google-repeat-#{System.unique_integer([:positive])}"}

    assert {:ok, _} = Starter.Auth.SSO.authenticate_sso(:google, attrs)
    assert {:ok, session} = Starter.Auth.SSO.authenticate_sso(:google, attrs)
    assert {:ref, Starter.Users.User, user_id} = session.user
    assert Starter.Repo.get!(User, user_id).status == :pending
  end

  test "an invalid invite token is rejected without provisioning" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: true)
    email = "gated-bad-#{System.unique_integer([:positive])}@example.com"

    assert {:error, :invalid_token} =
             Starter.Auth.SSO.authenticate_sso(:google, %{
               email: email,
               invite_token: "definitely-not-a-real-token",
               sub: "google-gated-bad-#{System.unique_integer([:positive])}"
             })

    assert Starter.Repo.get_by(User, email: email) == nil
  end

  test "valid invite provisions an active member and is redeemed" do
    ensure_provider!("Google", "Google OAuth")
    set_sso_policy("example.com", ["google"], auto_approve: false)
    email = "invited-#{System.unique_integer([:positive])}@example.com"

    org =
      Starter.Repo.insert!(%Starter.Schema.Organizations.Organization{
        slug: "invite-org-#{System.unique_integer([:positive])}",
        name: "Invite Org"
      })

    {:ok, invite, raw_token} =
      Starter.Organizations.create_invite_token(%{
        organization_id: org.id,
        email: email,
        role: "member",
        starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        max_uses: 1
      })

    assert {:ok, session} =
             Starter.Auth.SSO.authenticate_sso(:google, %{
               email: email,
               invite_token: raw_token,
               name: %{first: "Ada", last: "Lovelace"},
               sub: "google-invited-#{System.unique_integer([:positive])}"
             })

    assert {:ref, Starter.Users.User, user_id} = session.user

    # Invited identities are active + approved immediately (inviter vouches).
    user = Starter.Repo.get!(User, user_id)
    assert user.status == :active
    assert user.approved_at

    # Membership at the inviter's chosen role, not a default viewer bump.
    assert {:ok, %{role: "member"}} =
             Starter.Authz.authorize(user_id, "organization", org.id, "member")

    # The invite is consumed exactly once.
    token_schema = Starter.Schema.Organizations.InviteToken
    consumed = Starter.Repo.get!(token_schema, invite.id)
    assert consumed.uses == 1
    assert consumed.status == "accepted"

    # A second SSO hit with the same (now exhausted) token is a plain login
    # for the existing user, not a re-redemption.
    assert {:ok, _} =
             Starter.Auth.SSO.authenticate_sso(:google, %{
               email: email,
               invite_token: raw_token,
               sub: "google-invited-#{System.unique_integer([:positive])}"
             })

    assert Starter.Repo.get!(token_schema, invite.id).uses == 1
  end

  defp ensure_provider!(title, description) do
    id = UUID.uuid5(:oid, "Starter.Schema.Auth.Providers.Provider@#{title}")

    Starter.Repo.insert!(
      %Provider{id: id, title: title, description: description},
      on_conflict: :nothing,
      conflict_target: :id
    )
  end

  defp set_sso_policy(domain, providers, opts) do
    Application.put_env(:starter, :sso_domain_policies, %{
      domain => %{providers: providers, auto_approve: Keyword.get(opts, :auto_approve, false)}
    })
  end
end
