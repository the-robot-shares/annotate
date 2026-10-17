defmodule Annotate.Dashboard.GithubLoginTest do
  use Annotate.DataCase, async: true

  alias Annotate.Dashboard.GithubLogin
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.OAuthIdentity
  alias Annotate.Schema.Users.User

  defp profile(attrs \\ %{}) do
    Map.merge(
      %{
        github_id: 1001,
        login: "octo",
        email: "octo@example.com",
        name: "Octo Cat",
        avatar_url: nil
      },
      attrs
    )
  end

  describe "verified_email/1" do
    test "only verified entries; primary first" do
      assert {:ok, "p@x.com"} =
               GithubLogin.verified_email([
                 %{"email" => "a@x.com", "verified" => true},
                 %{"email" => "P@x.com", "verified" => true, "primary" => true}
               ])

      # ueberauth_github would pick this unverified primary — we must not
      assert {:ok, "ok@x.com"} =
               GithubLogin.verified_email([
                 %{"email" => "victim@x.com", "verified" => false, "primary" => true},
                 %{"email" => "ok@x.com", "verified" => true}
               ])

      assert {:ok, "real@x.com"} =
               GithubLogin.verified_email([
                 %{"email" => "1+o@users.noreply.github.com", "verified" => true},
                 %{"email" => "real@x.com", "verified" => true}
               ])

      assert {:error, :no_verified_email} =
               GithubLogin.verified_email([%{"email" => "v@x.com", "verified" => false}])

      assert {:error, :no_verified_email} = GithubLogin.verified_email(nil)
    end
  end

  describe "sign_in/1" do
    test "first sign-in creates a verified user + identity + session; uninvited → pending" do
      assert {:ok, %{user: user, session: session}} = GithubLogin.sign_in(profile())
      assert session
      user = Repo.get!(User, user.id)
      assert user.email == "octo@example.com" and user.verified and user.status == :pending
      assert user.handle == "octo"

      assert %OAuthIdentity{login: "octo"} =
               Repo.get_by!(OAuthIdentity, provider: "github", provider_uid: "1001")
    end

    test "exempt @noizu.com verified email → active" do
      {:ok, %{user: user}} = GithubLogin.sign_in(profile(%{email: "staff@noizu.com"}))
      assert Repo.get!(User, user.id).status == :active
    end

    test "keyed by github id: renamed login / changed email → same user" do
      {:ok, %{user: u1}} = GithubLogin.sign_in(profile())

      {:ok, %{user: u2}} =
        GithubLogin.sign_in(profile(%{login: "octo2", email: "new@example.com"}))

      assert u1.id == u2.id

      assert Repo.get_by!(OAuthIdentity, provider: "github", provider_uid: "1001").login ==
               "octo2"
    end

    test "links an existing verified user by email; an existing ACTIVE user stays active" do
      existing =
        Repo.insert!(%User{
          id: Ecto.UUID.generate(),
          email: "octo@example.com",
          status: :active,
          verified: true
        })

      {:ok, %{user: user}} = GithubLogin.sign_in(profile())
      assert user.id == existing.id
      assert Repo.get!(User, user.id).status == :active
    end

    test "an unverified squatter row is taken over, password cleared, and re-gated" do
      squat =
        Repo.insert!(%User{
          id: Ecto.UUID.generate(),
          email: "octo@example.com",
          status: :active,
          verified: false,
          hashed_password: "$2b$12$squatter"
        })

      {:ok, %{user: user}} = GithubLogin.sign_in(profile())
      assert user.id == squat.id
      reloaded = Repo.get!(User, squat.id)
      assert reloaded.verified == true
      assert reloaded.hashed_password == nil
      assert reloaded.status == :pending
    end

    test "a user already linked to another GitHub account is refused" do
      {:ok, _} = GithubLogin.sign_in(profile())

      assert {:error, :email_linked_to_other_account} =
               GithubLogin.sign_in(profile(%{github_id: 2002, login: "other"}))
    end

    test "disabled users are refused" do
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "octo@example.com",
        status: :suspended,
        verified: true
      })

      assert {:error, :account_disabled} = GithubLogin.sign_in(profile())
    end

    test "handle collision leaves handle nil instead of failing" do
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "x@example.com",
        handle: "octo",
        user_name: "octo",
        status: :active
      })

      {:ok, %{user: user}} = GithubLogin.sign_in(profile())
      assert user.handle == nil
    end
  end
end
