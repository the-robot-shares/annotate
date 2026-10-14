defmodule StarterWeb.UserControllerTest do
  use StarterWeb.ConnCase

  alias Starter.Schema.Users.User

  describe "POST /api/v1/users/me/complete-registration" do
    test "completes required profile but remains pending without invite", %{conn: conn} do
      %{access_token: token, user: user} = setup_user_and_token()
      mark_pending!(user)

      conn =
        conn
        |> authenticated_conn(token)
        |> post("/api/v1/users/me/complete-registration", %{user: profile_params()})

      response = json_response(conn, 200)
      assert response["user"]["profile_complete"] == true
      assert response["user"]["status"] == "pending"

      updated = Starter.Repo.get!(User, user.id)
      assert updated.profile_completed_at
      assert updated.status == :pending
    end

    test "valid invite activates a pending completed-registration user", %{conn: conn} do
      %{access_token: token, user: user} = setup_user_and_token()
      mark_pending!(user)

      {:ok, invite, raw_token} =
        Starter.Organizations.create_invite_token(invite_attrs(user.email))

      params = Map.put(profile_params(), :invite_token, raw_token)

      conn =
        conn
        |> authenticated_conn(token)
        |> post("/api/v1/users/me/complete-registration", %{user: params})

      response = json_response(conn, 200)
      assert response["user"]["status"] == "active"
      assert response["user"]["profile_complete"] == true

      updated = Starter.Repo.get!(User, user.id)
      assert updated.status == :active
      assert updated.invite_token_id == invite.id
      assert updated.approved_at
    end
  end

  defp mark_pending!(user) do
    user
    |> User.changeset(%{status: :pending, profile_completed_at: nil, mobile_phone: nil})
    |> Starter.Repo.update!()
  end

  defp profile_params do
    %{
      user_name: "complete#{System.unique_integer([:positive])}",
      first_name: "Grace",
      last_name: "Hopper",
      mobile_phone: "+15555550999"
    }
  end

  defp invite_attrs(email) do
    %{
      email: email,
      starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      max_uses: 1
    }
  end
end
