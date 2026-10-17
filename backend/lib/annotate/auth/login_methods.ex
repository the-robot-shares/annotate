defmodule Annotate.Auth.LoginMethods do
  @moduledoc """
  Which dashboard sign-in methods this deployment accepts.

  annotate signs owners in with **GitHub or Google** (`config :annotate,
  :login_methods, ["github", "google"]`): sign-up and sign-in go through those
  OAuth providers only, and the scaffold's email
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

  @doc "Google OAuth credentials are present (else the UI shows \"not configured\")."
  def google_configured?, do: Application.get_env(:annotate, :google_enabled, false) == true

  @doc "Dashboard providers shown in the sign-in modal, in display order."
  def dashboard_providers, do: Enum.filter(~w(github google), &enabled?/1)

  @doc "Shown-but-unconfigured providers (rendered disabled, \"not configured\")."
  def unconfigured_providers do
    Enum.reject(dashboard_providers(), fn
      "github" -> github_configured?()
      "google" -> google_configured?()
    end)
  end

  @doc "Email/password-family sign-in (password, magic link, OTP, reset, email verify)."
  def password_enabled?, do: enabled?("password")

  @doc "Raises-free guard for context functions: `:ok` or `{:error, :login_method_disabled}`."
  def require(method), do: if(enabled?(method), do: :ok, else: {:error, :login_method_disabled})
end
