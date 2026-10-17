defmodule Annotate.Schema.SiteManagementSchemaTest do
  use Annotate.DataCase, async: true

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.{Commenter, GithubIdentity, Site, SiteMember}
  alias Annotate.Schema.Users.User

  defp user!(email) do
    Repo.insert!(%User{id: Ecto.UUID.generate(), email: email, status: :active, verified: true})
  end

  defp site!(slug) do
    Repo.insert!(%Site{slug: slug, name: slug, allowed_origins: ["https://#{slug}.test"]})
  end

  test "site_members: unique (site, user), defaults to member, cascades" do
    site = site!("sm-a")
    user = user!("a@example.com")

    {:ok, m} =
      %SiteMember{}
      |> SiteMember.changeset(%{site_id: site.id, user_id: user.id})
      |> Repo.insert()

    assert m.role == :member

    assert {:error, cs} =
             %SiteMember{}
             |> SiteMember.changeset(%{site_id: site.id, user_id: user.id, role: :owner})
             |> Repo.insert()

    assert {"has already been taken", _} = cs.errors[:site_id]

    Repo.delete!(site)
    assert Repo.get(SiteMember, m.id) == nil
  end

  test "site_members: inviter is nulled when the inviter user is deleted" do
    site = site!("sm-b")
    owner = user!("o@example.com")
    invitee = user!("i@example.com")

    m =
      %SiteMember{}
      |> SiteMember.changeset(%{site_id: site.id, user_id: invitee.id, invited_by: owner.id})
      |> Repo.insert!()

    Repo.delete!(owner)
    assert Repo.get!(SiteMember, m.id).invited_by == nil
  end

  test "github_identities: github_id and user_id are each unique" do
    u1 = user!("g1@example.com")
    u2 = user!("g2@example.com")
    attrs = %{github_id: 42, user_id: u1.id, login: "octo"}

    assert {:ok, _} = %GithubIdentity{} |> GithubIdentity.changeset(attrs) |> Repo.insert()

    assert {:error, cs} =
             %GithubIdentity{}
             |> GithubIdentity.changeset(%{attrs | user_id: u2.id})
             |> Repo.insert()

    assert cs.errors[:github_id]

    assert {:error, cs} =
             %GithubIdentity{}
             |> GithubIdentity.changeset(%{attrs | github_id: 43})
             |> Repo.insert()

    assert cs.errors[:user_id]
  end

  test "commenters: email_verified defaults nil; user_id unique per site" do
    site = site!("sm-c")
    user = user!("t@example.com")
    c = Repo.insert!(%Commenter{site_id: site.id, external_id: "x"})
    assert c.email_verified == nil

    Repo.insert!(%Commenter{site_id: site.id, external_id: "team-1", user_id: user.id})

    assert_raise Ecto.ConstraintError, fn ->
      Repo.insert!(%Commenter{site_id: site.id, external_id: "team-2", user_id: user.id})
    end
  end
end
