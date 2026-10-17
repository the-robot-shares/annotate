defmodule Annotate.Dashboard.GoogleLogin do
  @moduledoc """
  Google → dashboard profile builder (`ueberauth_google`, OpenID userinfo).
  Sign-in itself is `Annotate.Dashboard.OAuthLogin`.

  - Keyed by Google's immutable `sub`, never email.
  - The email is accepted ONLY when Google asserts `email_verified: true`;
    otherwise `{:error, :no_verified_email}`.
  - `hd` (Workspace hosted domain), when present, rides along: the invite
    exemption requires it to be an exempt domain too
    (`Annotate.Dashboard.Access.exempt?/1`).
  """

  @doc "Extracts a verified profile from a Google `%Ueberauth.Auth{}`."
  def profile_from_auth(%{extra: %{raw_info: %{user: user}}} = auth) when is_map(user) do
    sub = user["sub"] || (auth.uid && to_string(auth.uid))
    email = user["email"]

    cond do
      not (is_binary(sub) and sub != "") ->
        {:error, :invalid_profile}

      not (user["email_verified"] in [true, "true"] and is_binary(email) and
               String.contains?(email, "@")) ->
        {:error, :no_verified_email}

      true ->
        {:ok,
         %{
           provider: "google",
           uid: sub,
           login: nil,
           email: email |> String.trim() |> String.downcase(),
           name: user["name"] || (auth.info && auth.info.name),
           avatar_url: user["picture"] || (auth.info && auth.info.image),
           hd: user["hd"]
         }}
    end
  end

  def profile_from_auth(_), do: {:error, :invalid_profile}
end
