defmodule Annotate.Auth.SSO do
  alias Annotate.Schema.Users.User, as: UserSchema
  alias Annotate.Schema.Users.Credentials.UserCredential, as: CredentialSchema
  import Ecto.Query, only: [from: 2]

  @provider_map %{
    oidc: &Annotate.Auth.Providers.oidc/0,
    saml: &Annotate.Auth.Providers.saml/0,
    google: &Annotate.Auth.Providers.google/0,
    facebook: &Annotate.Auth.Providers.facebook/0,
    github: &Annotate.Auth.Providers.github/0,
    linkedin: &Annotate.Auth.Providers.linkedin/0
  }

  # <REMOVED UUID HERE> authenticate_sso :: auto-generated pointer for public function authenticate_sso
  # A nil/blank email claim cannot identify a user - reject rather than crash
  # on `String.trim(nil)` (the OIDC controller normally catches this earlier).
  def authenticate_sso(_provider_type, %{email: email})
      when is_nil(email) or email == "",
      do: {:error, :sso_not_allowed}

  def authenticate_sso(provider_type, %{email: email} = attrs) do
    context = Noizu.Context.system()
    email = email |> String.trim() |> String.downcase()
    provider_type = provider_type(provider_type)

    with provider_type when not is_nil(provider_type) <- provider_type,
         true <- Annotate.Auth.SSODomains.sso_available?(email, provider_type) do
      provider_ref = provider_ref(provider_type)
      {:ok, provider_id} = Annotate.Auth.Providers.Provider.id(provider_ref)

      case find_user_by_email(email) do
        {:ok, user} ->
          ensure_sso_credential(user, provider_ref, provider_id, provider_type, attrs, context)
          create_sso_session(user, provider_type, context)

        :not_found ->
          # Register open, app gated: a first SSO login always creates the
          # account. No invite → InviteGate.signup_status/3 (auto-approve
          # domain → :active, otherwise :pending, held at the interstitial);
          # valid invite → :active and redeemed in the same transaction;
          # supplied but invalid invite → {:error, :invalid_token}, no row.
          # SSO_REQUIRE_INVITE plays no part.
          with {:ok, invite} <- resolve_registration_invite(attrs[:invite_token], email) do
            invited_sso_registration(
              email,
              attrs,
              provider_ref,
              provider_id,
              provider_type,
              invite,
              context
            )
          end
      end
    else
      _ -> {:error, :sso_not_allowed}
    end
  end

  defp resolve_registration_invite(raw_token, email) when is_binary(raw_token) do
    if String.trim(raw_token) == "" do
      {:ok, nil}
    else
      Annotate.Organizations.find_active_invite_by_raw_token(raw_token, email)
    end
  end

  defp resolve_registration_invite(_token, _email), do: {:ok, nil}

  # Registration path for an SSO identity. `invite` is nil when none was
  # supplied — the account is then created at InviteGate.signup_status/3.
  defp invited_sso_registration(email, attrs, provider_ref, provider_id, provider_type, invite, context) do
    # One transactional seam: the provisioned user, the redemption, and the
    # membership grant commit together. A redemption that loses an exhaustion
    # race rolls the account back entirely — no stranded approved user with
    # no membership. The session is only created afterwards, on success.
    result =
      Annotate.Repo.transaction(fn ->
        user =
          auto_provision_user(email, attrs, provider_ref, provider_id, provider_type, context, invite)

        if invite do
          with {:ok, _} <- Annotate.Organizations.redeem_invite_for_user(invite, user),
               :ok <- grant_invite_membership(invite, user.id) do
            user
          else
            {:error, reason} -> Annotate.Repo.rollback(reason)
          end
        else
          user
        end
      end)

    with {:ok, user} <- result, do: create_sso_session(user, provider_type, context)
  end

  # Membership grant at the role the *inviter* chose. Already being a member
  # is success — re-SSO-ing with a fresh invite link should not error out.
  defp grant_invite_membership(%{organization_id: nil}, _user_id), do: :ok

  defp grant_invite_membership(invite, user_id) do
    role = invite_role(invite)

    case Annotate.Authz.authorize(user_id, "organization", invite.organization_id, "viewer") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        case Annotate.Authz.ScopedMemberships.add_member(
               "organization",
               invite.organization_id,
               user_id,
               role
             ) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  # `owner` deliberately absent: an invite must never mint a second org owner.
  defp invite_role(%{role: role}) when role in ~w(admin member viewer), do: role
  defp invite_role(_), do: "viewer"

  defp find_user_by_email(email) do
    q = from u in UserSchema, where: u.email == ^email, where: u.status != :deleted, limit: 1

    case Annotate.Repo.one(q) do
      nil -> :not_found
      user -> {:ok, user}
    end
  end

  defp provider_ref(provider_type) do
    case @provider_map[provider_type].() do
      {:ok, provider_ref} -> provider_ref
      provider_ref -> provider_ref
    end
  end

  defp provider_type(value) when is_atom(value),
    do: if(Map.has_key?(@provider_map, value), do: value)

  defp provider_type(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> provider_type()
  rescue
    ArgumentError -> nil
  end

  defp provider_type(_), do: nil

  defp ensure_sso_credential(user, provider_ref, provider_id, provider_type, attrs, context) do
    user_ref = {:ref, Annotate.Users.User, user.id}
    fingerprint = sso_fingerprint(provider_type, attrs)

    q =
      from c in CredentialSchema,
        where: c.user_id == ^user.id,
        where: c.auth_provider_id == ^provider_id,
        where: c.status == :active,
        limit: 1

    case Annotate.Repo.one(q) do
      nil ->
        %Annotate.Users.Credentials.UserCredential{
          user: user_ref,
          auth_provider: provider_ref,
          status: :active,
          settings: sso_settings(provider_type, attrs),
          state: %{},
          fingerprint: fingerprint,
          time_stamp: Noizu.Entity.TimeStamp.now()
        }
        |> Annotate.EntityRepo.create(context)

      _existing ->
        :ok
    end
  end

  defp create_sso_session(user, provider_type, context) do
    user_ref = {:ref, Annotate.Users.User, user.id}

    %Annotate.Users.Sessions.UserSession{
      user: user_ref,
      status: :active,
      details: %{auth_method: to_string(provider_type)},
      time_stamp: Noizu.Entity.TimeStamp.now()
    }
    |> Annotate.EntityRepo.create(context)
  end

  defp auto_provision_user(email, attrs, provider_ref, _provider_id, provider_type, context, invite) do
    handle = email |> String.split("@") |> hd() |> String.replace(~r/[^a-z0-9_]/, "_")
    first = get_in(attrs, [:name, :first]) || attrs[:given_name] || handle
    last = get_in(attrs, [:name, :last]) || attrs[:family_name] || "User"

    {:ok, name} =
      %Annotate.Schema.Versioned.Names.Name{
        first: first,
        last: last
      }
      |> Annotate.Repo.insert()

    # One rule for every signup path (Annotate.Auth.InviteGate): an invited
    # identity or an auto-approve domain is :active + approved; anything else
    # is :pending and held at the invite interstitial.
    status = Annotate.Auth.InviteGate.signup_status(email, provider_type, invite)
    approved_at = if status == :active, do: DateTime.utc_now()

    user_schema = %UserSchema{
      id: UUID.uuid4(),
      user_name: handle,
      handle: handle,
      name_id: name.id,
      email: email,
      status: status,
      verified: true,
      flagged: false,
      approved_at: approved_at
    }

    {:ok, user} = Annotate.Repo.insert(user_schema, on_conflict: :nothing, conflict_target: :email)

    %Annotate.Users.Credentials.UserCredential{
      user: {:ref, Annotate.Users.User, user.id},
      auth_provider: provider_ref,
      status: :active,
      settings: sso_settings(provider_type, attrs),
      state: %{},
      fingerprint: sso_fingerprint(provider_type, attrs),
      time_stamp: Noizu.Entity.TimeStamp.now()
    }
    |> Annotate.EntityRepo.create(context)

    user
  end

  defp sso_settings(:saml, attrs), do: %{email: attrs[:email], name_id: attrs[:name_id]}

  defp sso_settings(_provider_type, attrs),
    do: %{email: attrs[:email], sub: attrs[:sub] || attrs[:uid]}

  defp sso_fingerprint(:saml, attrs), do: "saml:#{attrs[:name_id]}"
  defp sso_fingerprint(provider_type, attrs), do: "#{provider_type}:#{attrs[:sub] || attrs[:uid]}"
end
