defmodule Annotate.Dashboard.Access do
  @moduledoc """
  Who may use the owner dashboard — **invite-only** (user decision 2026-10-17).

  A brand-new dashboard account (any provider) is `:active` only when:

    * its provider-VERIFIED email is on an exempt domain — exactly
      `@noizu.com` (`config :annotate, :invite_exempt_domains`); subdomains
      (`x@eng.noizu.com`) and lookalikes (`noizu.com.evil.test`) do not count;
      for Google, a present `hd` (hosted domain) claim must also be exempt; or
    * the product is past invite-only (`Annotate.Auth.InviteGate.enabled?/0`
      false); or
    * it redeems a valid invite during sign-in (`InviteGate.redeem/3`, which
      consumes the invite and activates in one transaction).

  Everyone else is created `:pending`: signed in, but `RequireAuth`,
  `DashboardAuth`, the REST `RequireInvite` plug and the team bridge all
  treat them as outsiders until an invite is redeemed at
  `/auth/invite-required`. Embed commenters (Authentik `/embed/*`) are a
  different realm and are not gated.
  """

  alias Annotate.Auth.InviteGate

  @doc "Exempt domains (exact, lowercase)."
  def exempt_domains,
    do:
      Application.get_env(:annotate, :invite_exempt_domains, ["noizu.com"])
      |> Enum.map(&String.downcase/1)

  @doc "The domain part of `email`, lowercased; nil unless exactly one `@`."
  def email_domain(email) when is_binary(email) do
    case email |> String.trim() |> String.downcase() |> String.split("@") do
      [local, domain] when local != "" and domain != "" -> domain
      _ -> nil
    end
  end

  def email_domain(_), do: nil

  @doc """
  True when a provider profile qualifies for the invite exemption. The email
  must already be provider-verified (the login modules refuse anything else);
  Google's `hd`, when present, must also be an exempt domain.
  """
  def exempt?(%{email: email} = profile) do
    domain = email_domain(email)

    domain != nil and domain in exempt_domains() and
      case Map.get(profile, :hd) do
        nil -> true
        "" -> true
        hd when is_binary(hd) -> String.downcase(hd) in exempt_domains()
        _ -> false
      end
  end

  def exempt?(_), do: false

  @doc "Status for a NEW account from `profile` (before any invite redemption)."
  def initial_status(profile) do
    if exempt?(profile) or not InviteGate.enabled?(), do: :active, else: :pending
  end

  @doc "True when `user` (row, id or serialized map) may use the dashboard right now."
  def allowed?(user), do: user != nil and not InviteGate.required?(user)

  @doc """
  May issue dashboard invites: platform admins, or ACTIVE verified users on an
  exempt domain (staff).
  """
  def can_issue_invites?(%{admin: true}), do: true

  def can_issue_invites?(%{email: email, verified: true} = user),
    do: email_domain(email) in exempt_domains() and allowed?(user)

  def can_issue_invites?(_), do: false
end
