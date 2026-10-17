defmodule Annotate.Auth.LoginMethods do
  @moduledoc """
  Which dashboard sign-in methods this deployment accepts.

  annotate is **GitHub-only** (`config :annotate, :login_methods, ["github"]`):
  sign-up and sign-in both go through GitHub OAuth, and the scaffold's email
  (password / magic link / OTP / reset), OIDC, SAML and other social routes
  are refused. Tests run the scaffold suite with `:all`.

  Embed commenters are a different realm (Authentik popup broker at
  `/embed/*`) and are not governed by this setting.
  """

  @doc "Configured methods: `:all` or a list of method names."
  def methods, do: Application.get_env(:annotate, :login_methods, :all)

  @doc "True when `method` (`\"password\" | \"github\" | \"oidc\" | \"saml\" | provider`) is enabled."
  def enabled?(method) do
    case methods() do
      :all -> true
      list when is_list(list) -> to_string(method) in list
      _ -> false
    end
  end

  @doc "GitHub OAuth credentials are present (else the UI shows \"not configured\")."
  def github_configured?, do: Application.get_env(:annotate, :github_enabled, false) == true

  @doc "Email/password-family sign-in (password, magic link, OTP, reset, email verify)."
  def password_enabled?, do: enabled?("password")

  @doc "Raises-free guard for context functions: `:ok` or `{:error, :login_method_disabled}`."
  def require(method), do: if(enabled?(method), do: :ok, else: {:error, :login_method_disabled})
end
