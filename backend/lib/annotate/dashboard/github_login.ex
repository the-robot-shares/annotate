defmodule Annotate.Dashboard.GithubLogin do
  @moduledoc """
  Dashboard sign-in / sign-up with GitHub (the ONLY dashboard login method,
  `Annotate.Auth.LoginMethods`). First sign-in creates the account.

  ## Identity rules (security-relevant)

  - The GitHub account is keyed by its immutable numeric id
    (`github_identities.github_id`), never by login or email.
  - The account email is taken ONLY from GitHub's `/user/emails` entries with
    `verified: true` (primary first). `ueberauth_github` itself picks the
    primary email without checking `verified`, and GitHub allows an
    unverified primary. No verified email ⇒ `{:error, :no_verified_email}`.
  - A first GitHub sign-in whose verified email matches an existing scaffold
    user links to it. If that user was never verified (e.g. someone
    pre-registered the address with a password), the GitHub-verified owner of
    the address wins: the row is marked verified and its password hash is
    cleared, so the squatter's credential stops working.
  - A user already linked to a DIFFERENT GitHub account is refused
    (`:email_linked_to_other_github`) instead of being re-linked.
  - Disabled / suspended / deleted users are refused (`:account_disabled`).
  """

  import Ecto.Query

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.GithubIdentity
  alias Annotate.Schema.Users.User

  @type profile :: %{
          github_id: integer(),
          login: String.t(),
          email: String.t(),
          name: String.t() | nil,
          avatar_url: String.t() | nil
        }

  @doc "Extracts a verified profile from a GitHub `%Ueberauth.Auth{}`."
  def profile_from_auth(%{extra: %{raw_info: %{user: user}}} = auth) when is_map(user) do
    with {:ok, github_id} <- github_id(user["id"] || auth.uid),
         {:ok, email} <- verified_email(user["emails"]) do
      {:ok,
       %{
         github_id: github_id,
         login: user["login"] || (auth.info && auth.info.nickname) || "github-#{github_id}",
         email: email,
         name: user["name"] || (auth.info && auth.info.name),
         avatar_url: user["avatar_url"] || (auth.info && auth.info.image)
       }}
    end
  end

  def profile_from_auth(_), do: {:error, :invalid_profile}

  defp github_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp github_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_profile}
    end
  end

  defp github_id(_), do: {:error, :invalid_profile}

  @doc """
  Picks the account email from GitHub's `/user/emails` list: verified only;
  primary first, then non-`noreply` verified, then any verified.
  """
  def verified_email(emails) when is_list(emails) do
    verified =
      Enum.filter(emails, fn e ->
        is_map(e) and e["verified"] == true and is_binary(e["email"]) and
          String.contains?(e["email"], "@")
      end)

    pick =
      Enum.find(verified, &(&1["primary"] == true)) ||
        Enum.find(verified, &(not String.ends_with?(&1["email"], "@users.noreply.github.com"))) ||
        List.first(verified)

    case pick do
      %{"email" => email} -> {:ok, email |> String.trim() |> String.downcase()}
      nil -> {:error, :no_verified_email}
    end
  end

  def verified_email(_), do: {:error, :no_verified_email}

  @doc """
  Signs a verified GitHub profile in: links/creates the user and identity and
  opens a scaffold session. Returns `{:ok, %{user: user, session: session}}`.
  """
  def sign_in(profile) do
    Repo.transaction(fn ->
      with {:ok, user} <- resolve_user(profile),
           :ok <- check_active(user),
           {:ok, _identity} <- upsert_identity(user, profile),
           {:ok, session} <- Annotate.Auth.SSO.create_session(user, :github) do
        %{user: user, session: session}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp resolve_user(%{github_id: gid} = profile) do
    case Repo.one(
           from(i in GithubIdentity,
             where: i.github_id == ^gid,
             preload: [:user],
             lock: "FOR UPDATE"
           )
         ) do
      %GithubIdentity{user: %User{} = user} ->
        {:ok, user}

      nil ->
        case Repo.one(
               from(u in User, where: u.email == ^profile.email, limit: 1, lock: "FOR UPDATE")
             ) do
          %User{} = user -> link_existing(user, gid)
          nil -> create_user(profile)
        end
    end
  end

  defp link_existing(%User{} = user, gid) do
    case Repo.get_by(GithubIdentity, user_id: user.id) do
      %GithubIdentity{github_id: ^gid} ->
        {:ok, user}

      %GithubIdentity{} ->
        {:error, :email_linked_to_other_github}

      nil ->
        if user.verified == true do
          {:ok, user}
        else
          # Unverified holder of a GitHub-verified address: the GitHub owner
          # wins; any password set on the unverified row stops working.
          user
          |> Ecto.Changeset.change(verified: true, hashed_password: nil)
          |> Repo.update()
        end
    end
  end

  defp create_user(profile) do
    {first, last} = split_name(profile.name, profile.login)

    {:ok, name} =
      %Annotate.Schema.Versioned.Names.Name{first: first, last: last}
      |> Repo.insert()

    handle = available_handle(profile.login)

    %User{
      id: Ecto.UUID.generate(),
      user_name: handle,
      handle: handle,
      name_id: name.id,
      email: profile.email,
      status: :active,
      verified: true,
      flagged: false,
      approved_at: DateTime.utc_now(),
      # GitHub supplies everything the dashboard needs; no profile interstitial.
      profile_completed_at: DateTime.utc_now()
    }
    |> Repo.insert()
  end

  defp available_handle(login) do
    handle = login |> String.downcase() |> String.replace(~r/[^a-z0-9_-]/, "_")

    taken? =
      Repo.exists?(from(u in User, where: u.user_name == ^handle or u.handle == ^handle))

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
      github_id: profile.github_id,
      user_id: user.id,
      login: profile.login,
      email: profile.email,
      name: profile.name,
      avatar_url: profile.avatar_url
    }

    case Repo.get_by(GithubIdentity, github_id: profile.github_id) do
      nil -> %GithubIdentity{} |> GithubIdentity.changeset(attrs) |> Repo.insert()
      identity -> identity |> GithubIdentity.changeset(attrs) |> Repo.update()
    end
  end
end
