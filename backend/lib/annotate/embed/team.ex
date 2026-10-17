defmodule Annotate.Embed.Team do
  @moduledoc """
  "Is this embed commenter on the site's team, and with what role?"

  Two sources, recorded on every token as `team_src`:

  - **`"bridge"`** (Authentik popup sign-in): `commenter.email` (IdP-verified)
    → verified dashboard `users` row → `site_members`
    (`Annotate.SiteMembers.team_role_for_commenter/3`).
  - **`"host"`** (host-assert): the host's own `team_role` claim, honoured only
    while the site's `comment_policy.trust_host_roles` is on.

  The `team_role` claim on an access token is a **hint** for the widget
  (`GET /config` → `team`). Authorization decisions call `current_role/3`,
  which re-derives the role from CURRENT membership / site policy on every
  team-gated request (decision Q1-b): a removed member, a demotion, or a site
  turning `trust_host_roles` off takes effect on the next request, not after
  the 15-minute access TTL.
  """

  alias Annotate.SiteMembers
  alias Annotate.Sites

  @roles ~w(owner admin member)

  @doc "Validates a host-asserted role string; nil when not a known role."
  def host_role(role) when role in @roles, do: role
  def host_role(_), do: nil

  @doc """
  Team spec for issuance: `:bridge`, `{:host, role}` or `:none`, from the
  persisted refresh-token `identity_claims` (rotation carry-over).
  """
  def spec_from_identity_claims(%{"team_src" => "host", "host_team_role" => role})
      when role in @roles,
      do: {:host, role}

  def spec_from_identity_claims(%{"team_src" => "bridge"}), do: :bridge
  def spec_from_identity_claims(_), do: :none

  @doc "identity_claims keys persisting the team source on a refresh token."
  def identity_claims_for(:bridge), do: %{"team_src" => "bridge"}

  def identity_claims_for({:host, role}) when role in @roles,
    do: %{"team_src" => "host", "host_team_role" => role}

  def identity_claims_for(_), do: %{}

  @doc """
  Role to embed in an access token for `spec` (computed NOW): `{src, role}`
  or nil. Host roles require the site to still trust host roles.
  """
  def claim_for(:bridge, site, commenter) do
    case SiteMembers.team_role_for_commenter(site, commenter) do
      nil -> nil
      role -> {"bridge", Atom.to_string(role)}
    end
  end

  def claim_for({:host, role}, site, _commenter) when role in @roles do
    if Sites.trust_host_roles?(site), do: {"host", role}, else: nil
  end

  def claim_for(_, _, _), do: nil

  @doc """
  The commenter's CURRENT team role on `site` (`:owner | :admin | :member |
  nil`), re-derived per request from the token's `team_src`.
  """
  def current_role(site, commenter, claims) do
    case claims do
      %{"team_src" => "host", "team_role" => role} when role in @roles ->
        if Sites.trust_host_roles?(site), do: String.to_existing_atom(role), else: nil

      _ ->
        if commenter, do: SiteMembers.team_role_for_commenter(site, commenter), else: nil
    end
  end

  @doc "True when the commenter may moderate (owner/admin) on `site` right now."
  def moderator?(site, commenter, claims),
    do: current_role(site, commenter, claims) in [:owner, :admin]
end
