defmodule StarterWeb.UserController do
  use StarterWeb, :controller

  alias Starter.Guardian
  alias Starter.Organizations
  alias Starter.Schema.Users.User, as: UserSchema
  alias Starter.Schema.Versioned.Names.Name, as: NameSchema
  import Ecto.Query, only: [from: 2]

  # <REMOVED UUID HERE> show :: auto-generated pointer for public function show
  def show(conn, _params) do
    user = get_current_user_schema(conn)

    conn
    |> put_status(:ok)
    |> json(%{user: serialize_user(user)})
  end

  # <REMOVED UUID HERE> update :: auto-generated pointer for public function update
  def update(conn, %{"user" => user_params}) do
    user = get_current_user_schema(conn)

    with :ok <- validate_update_params(user, user_params),
         {:ok, updated_user} <- apply_profile_updates(user, user_params, false) do
      conn
      |> put_status(:ok)
      |> json(%{user: serialize_user(updated_user)})
    else
      {:error, :invalid_current_password} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Current password is incorrect"})

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def update(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user params required"})
  end

  # <REMOVED UUID HERE> complete_registration :: auto-generated pointer for public function complete_registration
  def complete_registration(conn, %{"user" => user_params}) do
    user = get_current_user_schema(conn)
    invite_token = optional_string(user_params["invite_token"])

    with :ok <- validate_required_profile(user_params),
         {:ok, invite} <- resolve_invite(invite_token, user.email) do
      # Redeem and profile save share one transaction: a failed redeem must
      # not leave a half-completed profile behind (and vice versa).
      result =
        Starter.Repo.transaction(fn ->
          with {:ok, activated_user} <- maybe_activate_with_invite(user, invite, conn),
               {:ok, updated_user} <- apply_profile_updates(activated_user, user_params, true) do
            updated_user
          else
            {:error, reason} -> Starter.Repo.rollback(reason)
          end
        end)

      case result do
        {:ok, updated_user} ->
          conn |> put_status(:ok) |> json(%{user: serialize_user(updated_user)})

        {:error, :invalid_token} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired invite token"})

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})

        {:error, reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
      end
    else
      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid or expired invite token"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def complete_registration(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "user params required"})
  end

  defp get_current_user_schema(conn) do
    session = Guardian.Plug.current_resource(conn)

    user_id =
      case session.user do
        {:ref, _, id} -> id
        %{id: id} -> id
      end

    Starter.Repo.get!(UserSchema, user_id)
  end

  defp validate_update_params(user, params) do
    if params["new_password"] && params["current_password"] do
      {:ok, auth_provider} = Starter.Auth.Providers.login()
      {:ok, auth_provider_id} = Starter.Auth.Providers.Provider.id(auth_provider)

      q =
        from c in Starter.Schema.Users.Credentials.UserCredential,
          where: c.user_id == ^user.id,
          where: c.auth_provider_id == ^auth_provider_id,
          where: c.status == :active,
          limit: 1

      case Starter.Repo.one(q) do
        nil ->
          {:error, :invalid_current_password}

        credential ->
          if Bcrypt.verify_pass(params["current_password"], credential.settings["password"]) do
            :ok
          else
            {:error, :invalid_current_password}
          end
      end
    else
      :ok
    end
  end

  defp validate_required_profile(params) do
    missing =
      [
        {"user_name", "User name"},
        {"first_name", "First name"},
        {"last_name", "Last name"},
        {"mobile_phone", "Mobile phone"}
      ]
      |> Enum.filter(fn {key, _label} ->
        value = params[key]
        !(is_binary(value) && String.trim(value) != "")
      end)

    case missing do
      [] -> :ok
      [{_key, label} | _] -> {:error, "#{label} is required"}
    end
  end

  defp apply_profile_updates(user, params, mark_complete?) do
    Starter.Repo.transaction(fn ->
      name_id = upsert_name!(user.name_id, params)

      attrs =
        %{}
        |> maybe_put(:user_name, optional_string(params["user_name"]))
        |> maybe_put(:handle, optional_string(params["user_name"]))
        |> maybe_put(:email, optional_string(params["email"]))
        |> maybe_put(:mobile_phone, optional_string(params["mobile_phone"]))
        |> maybe_put(:name_id, name_id)
        |> maybe_put(:profile_completed_at, mark_complete? && DateTime.utc_now())

      updated_user =
        user
        |> UserSchema.changeset(attrs)
        |> Starter.Repo.update!()

      if params["new_password"] do
        case Starter.Users.Credentials.update_password(
               updated_user,
               params["new_password"],
               Noizu.Context.system()
             ) do
          {:ok, _credential} -> :ok
          {:error, reason} -> Starter.Repo.rollback(reason)
        end
      end

      updated_user
    end)
  end

  defp upsert_name!(nil, params), do: insert_name!(params)

  defp upsert_name!(name_id, params) do
    attrs = name_attrs(params)

    if map_size(attrs) == 0 do
      name_id
    else
      case Starter.Repo.get(NameSchema, name_id) do
        nil ->
          insert_name!(params)

        name ->
          name
          |> NameSchema.changeset(attrs)
          |> Starter.Repo.update!()
          |> Map.fetch!(:id)
      end
    end
  end

  defp insert_name!(params) do
    %NameSchema{}
    |> NameSchema.changeset(%{
      first: optional_string(params["first_name"]) || "",
      last: optional_string(params["last_name"]) || "",
      middle: []
    })
    |> Starter.Repo.insert!()
    |> Map.fetch!(:id)
  end

  defp name_attrs(params) do
    %{}
    |> maybe_put(:first, optional_string(params["first_name"]))
    |> maybe_put(:last, optional_string(params["last_name"]))
  end

  defp resolve_invite(nil, _email), do: {:ok, nil}
  defp resolve_invite("", _email), do: {:ok, nil}

  defp resolve_invite(raw_token, email),
    do: Organizations.find_active_invite_by_raw_token(raw_token, email)

  defp maybe_activate_with_invite(user, nil, _conn), do: {:ok, user}

  defp maybe_activate_with_invite(user, invite, conn) do
    with {:ok, :ok} <- Organizations.redeem_invite_for_user(invite, user, conn) do
      if invite.organization_id do
        Starter.Authz.ScopedMemberships.add_member(
          "organization",
          invite.organization_id,
          user.id,
          "viewer"
        )
      end

      attrs = %{
        status: :active,
        invite_token_id: invite.id,
        approved_at: DateTime.utc_now()
      }

      user
      |> UserSchema.changeset(attrs)
      |> Starter.Repo.update()
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      user_name: user.user_name,
      handle: user.handle,
      mobile_phone: user.mobile_phone,
      status: user.status,
      verified: user.verified,
      profile_completed_at: user.profile_completed_at,
      profile_complete: !!user.profile_completed_at,
      requires_profile_completion: !user.profile_completed_at
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, false), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_string(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
