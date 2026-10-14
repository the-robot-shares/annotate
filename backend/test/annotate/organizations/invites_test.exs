defmodule Annotate.Organizations.InvitesTest do
  use Annotate.DataCase, async: false

  alias Annotate.Schema.Organizations.InviteToken
  alias Annotate.Schema.Organizations.InviteTokenRedemption
  alias Annotate.Schema.Users.User

  import Ecto.Query

  @token_schema InviteToken

  describe "redeem_invite_for_user/3 exhaustion guard" do
    test "sequential second redeem of a spent invite fails without a second redemption row" do
      {:ok, invite, _raw} = mint_invite(max_uses: 1)
      {:ok, user_a} = create_test_user()
      {:ok, user_b} = create_test_user()

      assert {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, user_a)

      assert {:error, :invite_exhausted} =
               Annotate.Organizations.redeem_invite_for_user(invite, user_b)

      token = Annotate.Repo.get!(@token_schema, invite.id)
      assert token.uses == 1
      assert token.redemption_count == 1
      assert redemptions(invite.id) == 1
    end

    test "concurrent redeems of a max_uses=1 invite: exactly one wins" do
      {:ok, invite, _raw} = mint_invite(max_uses: 1)
      {:ok, user_a} = create_test_user()
      {:ok, user_b} = create_test_user()

      parent = self()

      # Each task shares the test sandbox connection; the row lock serializes
      # the two transactions, which is precisely the interleaving the guarded
      # update_all exists to make safe (the loser re-reads uses under the
      # lock, sees it spent, and rolls back instead of incrementing).
      tasks =
        for user <- [user_a, user_b] do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Annotate.Repo, parent, self())
            Annotate.Organizations.redeem_invite_for_user(invite, user)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      assert Enum.sort(results) == [{:error, :invite_exhausted}, {:ok, :ok}]
      assert Annotate.Repo.get!(@token_schema, invite.id).uses == 1
      assert redemptions(invite.id) == 1
    end

    test "same user re-redeem is a no-op: no duplicate row, no use consumed" do
      {:ok, invite, _raw} = mint_invite(max_uses: 2)
      {:ok, user} = create_test_user()
      {:ok, user_b} = create_test_user()

      assert {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, user)

      assert {:ok, :already_redeemed} =
               Annotate.Organizations.redeem_invite_for_user(invite, user)

      # The repeat burned nothing — the other use is still available.
      assert Annotate.Repo.get!(@token_schema, invite.id).uses == 1
      assert redemptions(invite.id) == 1
      assert {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, user_b)
      assert Annotate.Repo.get!(@token_schema, invite.id).uses == 2
    end

    test "multi-use invites allow up to max_uses redemptions" do
      {:ok, invite, _raw} = mint_invite(max_uses: 2)
      {:ok, user_a} = create_test_user()
      {:ok, user_b} = create_test_user()
      {:ok, user_c} = create_test_user()

      assert {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, user_a)
      assert {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, user_b)

      assert {:error, :invite_exhausted} =
               Annotate.Organizations.redeem_invite_for_user(invite, user_c)

      assert Annotate.Repo.get!(@token_schema, invite.id).uses == 2
    end
  end

  describe "invite role validation" do
    test "create_invite_token rejects owner (and any non-role) at the changeset" do
      org = create_org()

      assert {:error, changeset} =
               Annotate.Organizations.create_invite_token(%{
                 organization_id: org.id,
                 role: "owner"
               })

      assert changeset.errors[:role]

      assert {:error, changeset} =
               Annotate.Organizations.create_invite_token(%{
                 organization_id: org.id,
                 role: "emperor"
               })

      assert changeset.errors[:role]
    end

    test "invite_redemption_counts/1 groups exact counts for an org" do
      org = create_org()
      {:ok, invite_a, _raw} = mint_invite(org: org, max_uses: 3)
      {:ok, invite_b, _raw} = mint_invite(org: org, max_uses: 1)
      {:ok, invite_other_org, _raw} = mint_invite(max_uses: 1)

      assert Annotate.Organizations.invite_redemption_counts(org.id) == %{}

      {:ok, user} = create_test_user()
      {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite_a, user)
      {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite_b, user)

      counts = Annotate.Organizations.invite_redemption_counts(org.id)
      assert counts[invite_a.id] == 1
      assert counts[invite_b.id] == 1
      # An invite from another org must not leak into this org's counts.
      refute Map.has_key?(counts, invite_other_org.id)
    end
  end

  describe "Annotate.Auth.Registration.register_user_with_invite/5 rollback seam" do
    test "an exhaustion race rolls the registration back entirely — no user row" do
      org = create_org()
      email = "rollback-#{System.unique_integer([:positive])}@example.com"

      # The invite still LOOKS active to the caller (stale struct), but the
      # guarded increment sees uses == max_uses and fails — the same state a
      # lost race leaves behind.
      {:ok, invite, _raw} =
        Annotate.Organizations.create_invite_token(%{
          organization_id: org.id,
          role: "member",
          starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          max_uses: 1
        })

      {:ok, squatter} = create_test_user()
      {:ok, :ok} = Annotate.Organizations.redeem_invite_for_user(invite, squatter)

      assert {:error, :invite_exhausted} =
               Annotate.Auth.Registration.register_user_with_invite(
                 %{
                   user_name: uniq(email),
                   email: email,
                   password: "password123",
                   name: %{first: "Seam", last: "Test"}
                 },
                 {:login, {email, "password123"}},
                 [status: :active, invite_token_id: invite.id],
                 invite
               )

      # The account, its credential, and any membership all rolled back.
      assert Annotate.Repo.get_by(User, email: email) == nil
      assert redemptions(invite.id) == 1
    end

    test "a fresh invite registers, redeems, and grants membership atomically" do
      org = create_org()
      email = "seam-#{System.unique_integer([:positive])}@example.com"

      {:ok, invite, _raw} =
        Annotate.Organizations.create_invite_token(%{
          organization_id: org.id,
          role: "member",
          starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          max_uses: 1
        })

      assert {:ok, user} =
               Annotate.Auth.Registration.register_user_with_invite(
                 %{
                   user_name: uniq(email),
                   email: email,
                   password: "password123",
                   name: %{first: "Seam", last: "Test"}
                 },
                 {:login, {email, "password123"}},
                 [status: :active, invite_token_id: invite.id],
                 invite
               )

      assert {:ok, %{role: "member"}} =
               Annotate.Authz.authorize(user.id, "organization", org.id, "member")

      assert Annotate.Repo.get!(@token_schema, invite.id).uses == 1
    end
  end

  # user_name max is 32 chars (Annotate.Users.valid_user_name?/1): 5 + 10 + 1 +
  # unique_integer digits. The old "seam_user_" prefix + 20-char base overflowed
  # once unique_integer reached 5 digits (seed-dependent {:user_name, :invalid}).
  defp uniq(email) do
    base =
      email
      |> String.split("@")
      |> hd()
      |> String.replace(~r/[^a-z0-9]/, "")
      |> String.slice(0, 10)

    "seam_#{base}_#{System.unique_integer([:positive])}"
  end

  defp mint_invite(opts) do
    Annotate.Organizations.create_invite_token(%{
      organization_id: (Keyword.get(opts, :org) || create_org()).id,
      role: Keyword.get(opts, :role, "viewer"),
      starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      max_uses: Keyword.get(opts, :max_uses, 1)
    })
  end

  defp create_org do
    Annotate.Repo.insert!(%Annotate.Schema.Organizations.Organization{
      slug: "inv-org-#{System.unique_integer([:positive])}",
      name: "Invite Org"
    })
  end

  defp create_test_user do
    uniq = System.unique_integer([:positive])

    {:ok, name} =
      %Annotate.Schema.Versioned.Names.Name{first: "Invite", last: "Test#{uniq}"}
      |> Annotate.Repo.insert()

    user =
      %User{
        id: UUID.uuid4(),
        user_name: "invite_user_#{uniq}",
        handle: "invite_user_#{uniq}",
        name_id: name.id,
        email: "invite-user-#{uniq}@example.com",
        status: :active,
        verified: true
      }
      |> Annotate.Repo.insert!()

    {:ok, user}
  end

  defp redemptions(invite_id) do
    Annotate.Repo.aggregate(
      from(r in InviteTokenRedemption, where: r.invite_token_id == ^invite_id),
      :count
    )
  end
end
