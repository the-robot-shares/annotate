defmodule Annotate.Dashboard.GithubLogin do
  @moduledoc """
  GitHub → dashboard profile builder. Sign-in itself (identity linking,
  invite gate, session) is `Annotate.Dashboard.OAuthLogin`.

  - Keyed by GitHub's immutable numeric id (`oauth_identities`
    provider `"github"`), never login or email.
  - The account email is taken ONLY from GitHub's `/user/emails` entries with
    `verified: true` (primary first). `ueberauth_github` itself picks the
    primary email without checking `verified`, and GitHub allows an
    unverified primary. No verified email ⇒ `{:error, :no_verified_email}`.
  """

  @doc "Extracts a verified profile from a GitHub `%Ueberauth.Auth{}`."
  def profile_from_auth(%{extra: %{raw_info: %{user: user}}} = auth) when is_map(user) do
    with {:ok, github_id} <- github_id(user["id"] || auth.uid),
         {:ok, email} <- verified_email(user["emails"]) do
      {:ok,
       %{
         provider: "github",
         uid: Integer.to_string(github_id),
         login: user["login"] || (auth.info && auth.info.nickname) || "github-#{github_id}",
         email: email,
         name: user["name"] || (auth.info && auth.info.name),
         avatar_url: user["avatar_url"] || (auth.info && auth.info.image),
         hd: nil
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
  Signs a verified GitHub profile in (`Annotate.Dashboard.OAuthLogin.sign_in/3`).
  Accepts the legacy `%{github_id: integer}` shape for callers/tests.
  """
  def sign_in(profile, invite_token \\ nil, conn \\ nil)

  def sign_in(%{github_id: gid} = profile, invite_token, conn) do
    profile
    |> Map.delete(:github_id)
    |> Map.merge(%{provider: "github", uid: to_string(gid)})
    |> Map.put_new(:hd, nil)
    |> Annotate.Dashboard.OAuthLogin.sign_in(invite_token, conn)
  end

  def sign_in(profile, invite_token, conn),
    do: Annotate.Dashboard.OAuthLogin.sign_in(profile, invite_token, conn)
end
