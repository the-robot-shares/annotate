defmodule Annotate.Dashboard.OAuthLogin do
  @moduledoc """
  Provider-generic dashboard sign-in / sign-up (GitHub, Google). First
  sign-in creates the account; the invite gate decides whether it is usable.

  ## Profile

  `%{provider, uid, email, login, name, avatar_url, hd}` built by
  `Annotate.Dashboard.GithubLogin.profile_from_auth/1` /
  `Annotate.Dashboard.GoogleLogin.profile_from_auth/1`. `email` is ALWAYS
  provider-verified (the profile builders refuse anything else).

  ## Identity rules (security-relevant)

  - Keyed by `(provider, uid)` in `oauth_identities` — never login or email.
  - A first sign-in whose verified email matches an existing user links to
    it (one account across GitHub and Google). An unverified holder of that
    address is taken over: marked verified, password hash cleared (the
    squatter's credential stops working), status re-decided by the gate.
  - A user already linked to a DIFFERENT account at the same provider is
    refused (`:email_linked_to_other_account`).
  - Disabled / suspended / deleted users are refused (`:account_disabled`).

  ## Invite gate (`Annotate.Dashboard.Access`)

  New accounts are `:active` only on an exempt verified domain (exactly
  `@noizu.com`); otherwise `:pending`. A raw invite token carried through the
  OAuth round trip is redeemed right after (consumed + activated atomically
  by `Annotate.Auth.InviteGate.redeem/3`); a bad invite leaves the account
  pending and is reported as `invite_error`. A pending account that later
  signs in from an exempt verified email is activated.
  """

  import Ecto.Query

  alias Annotate.Auth.InviteGate
  alias Annotate.Dashboard.Access
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.OAuthIdentity
  alias Annotate.Schema.Users.User

  @providers ~w(github google)

  @doc """
  Returns `{:ok, %{user, session, invite_error}}` (`invite_error` nil or an
  atom) or `{:error, reason}`.
  """
  def sign_in(profile, invite_token \\ nil, conn \\ nil)

  def sign_in(%{provider: provider} = profile, invite_token, conn) when provider in @providers do
    Repo.transaction(fn ->
      with {:ok, user} <- resolve_user(profile),
           :ok <- check_active(user),
           {:ok, user} <- maybe_exempt_activate(user, profile),
           {:ok, _identity} <- upsert_identity(user, profile) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} ->
        {user, invite_error} = maybe_redeem(user, invite_token, conn)

        case Annotate.Auth.SSO.create_session(user, String.to_existing_atom(profile.provider)) do
          {:ok, session} -> {:ok, %{user: user, session: session, invite_error: invite_error}}
          error -> error
        end

      error ->
        error
    end
  end

  def sign_in(_, _, _), do: {:error, :invalid_profile}

  # ── user resolution ──────────────────────────────────────────

  defp resolve_user(%{provider: provider, uid: uid} = profile) do
    case Repo.one(
           from(i in OAuthIdentity,
             where: i.provider == ^provider and i.provider_uid == ^uid,
             preload: [:user],
             lock: "FOR UPDATE"
           )
         ) do
      %OAuthIdentity{user: %User{} = user} ->
        {:ok, user}

      nil ->
        case Repo.one(
               from(u in User, where: u.email == ^profile.email, limit: 1, lock: "FOR UPDATE")
             ) do
          %User{} = user -> link_existing(user, profile)
          nil -> create_user(profile)
        end
    end
  end

  defp link_existing(%User{} = user, %{provider: provider, uid: uid} = profile) do
    case Repo.get_by(OAuthIdentity, user_id: user.id, provider: provider) do
      %OAuthIdentity{provider_uid: ^uid} ->
        {:ok, user}

      %OAuthIdentity{} ->
        {:error, :email_linked_to_other_account}

      nil ->
        if user.verified == true do
          {:ok, user}
        else
          # Unverified holder of a provider-verified address: the verified
          # owner wins; any password set on the squatted row stops working,
          # and the account is (re)gated like a brand-new one.
          user
          |> Ecto.Changeset.change(
            verified: true,
            hashed_password: nil,
            status: Access.initial_status(profile)
          )
          |> Repo.update()
        end
    end
  end

  defp create_user(profile) do
    {first, last} = split_name(profile.name, profile.login || "user")

    {:ok, name} =
      %Annotate.Schema.Versioned.Names.Name{first: first, last: last}
      |> Repo.insert()

    handle = available_handle(profile.login)
    status = Access.initial_status(profile)
    now = DateTime.utc_now()

    %User{
      id: Ecto.UUID.generate(),
      user_name: handle,
      handle: handle,
      name_id: name.id,
      email: profile.email,
      status: status,
      verified: true,
      flagged: false,
      approved_at: if(status == :active, do: now),
      # The provider supplies everything the dashboard needs; no profile interstitial.
      profile_completed_at: now
    }
    |> Repo.insert()
  end

  # A pending account that now signs in with an exempt verified email (e.g.
  # it later linked its @noizu.com Google account) becomes active.
  defp maybe_exempt_activate(%User{status: :pending} = user, profile) do
    if Access.exempt?(profile) and profile.email == user.email do
      user
      |> Ecto.Changeset.change(
        status: :active,
        approved_at: user.approved_at || DateTime.utc_now()
      )
      |> Repo.update()
    else
      {:ok, user}
    end
  end

  defp maybe_exempt_activate(user, _profile), do: {:ok, user}

  # Redeem the invite carried through the OAuth round trip (only when the
  # account still needs one). InviteGate.redeem/3 binds email-bound invites to
  # the account email, consumes atomically and activates in one transaction.
  defp maybe_redeem(user, token, conn) when is_binary(token) and token != "" do
    if InviteGate.required?(user) do
      case InviteGate.redeem(user, token, conn) do
        {:ok, _invite} -> {Repo.get!(User, user.id), nil}
        {:error, reason} -> {user, reason}
      end
    else
      {user, nil}
    end
  end

  defp maybe_redeem(user, _token, _conn), do: {user, nil}

  defp available_handle(nil), do: nil

  defp available_handle(login) do
    handle = login |> String.downcase() |> String.replace(~r/[^a-z0-9_-]/, "_")
    taken? = Repo.exists?(from(u in User, where: u.user_name == ^handle or u.handle == ^handle))
    if taken?, do: nil, else: handle
  end

  defp split_name(name, _login) when is_binary(name) and name != "" do
    case String.split(String.trim(name), ~r/\s+/, parts: 2) do
      [first, last] -> {first, last}
      [first] -> {first, ""}
    end
  end

  defp split_name(_, login), do: {login, ""}

  defp check_active(%User{deleted_at: nil, status: status}) when status in [:active, :pending],
    do: :ok

  defp check_active(_), do: {:error, :account_disabled}

  defp upsert_identity(user, profile) do
    attrs = %{
      provider: profile.provider,
      provider_uid: profile.uid,
      user_id: user.id,
      login: profile.login,
      email: profile.email,
      name: profile.name,
      avatar_url: profile.avatar_url
    }

    case Repo.get_by(OAuthIdentity, provider: profile.provider, provider_uid: profile.uid) do
      nil -> %OAuthIdentity{} |> OAuthIdentity.changeset(attrs) |> Repo.insert()
      identity -> identity |> OAuthIdentity.changeset(attrs) |> Repo.update()
    end
  end
end
