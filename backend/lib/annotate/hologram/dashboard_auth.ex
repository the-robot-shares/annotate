defmodule Annotate.Hologram.DashboardAuth do
  @moduledoc """
  Server-side authorization for the owner dashboard.

  `RequireAuth` (page middleware) already redirects anonymous visitors to
  `/sign-in`. This adds the per-site role gate: **member** may view a site
  (overview + inbox reply/resolve), **admin** may change display settings and
  moderate, **owner** manages security settings, members and the service key
  (`Annotate.SiteMembers.role_at_least?/2`).

  Every site-scoped page runs `authorize_site/3` in `init/3` (render gate) AND
  at the top of every `command/2` (action gate), so a stale tab or a
  hand-driven command can never act on a site the user lost access to; the
  role is read from the DB on every call (decision Q1-b).
  """

  alias Annotate.Hologram.Auth
  alias Annotate.SiteMembers
  alias Annotate.Sites

  @doc """
  `{:ok, user, site, role}` when the session user holds at least `min_role`
  on the site with `slug`; else `{:error, :unauthenticated | :not_found |
  :forbidden}`. A site the user is not a member of is reported as
  `:not_found` (no existence oracle for other tenants' slugs).
  """
  def authorize_site(server, slug, min_role) do
    with {:user, %{id: user_id} = user} <- {:user, Auth.current_user(server)},
         {:site, %{} = site} <- {:site, is_binary(slug) && Sites.get_site_by_slug(slug)},
         {:member, role} when role != nil <- {:member, SiteMembers.member_role(site, user_id)} do
      if SiteMembers.role_at_least?(role, min_role),
        do: {:ok, user, site, role},
        else: {:error, :forbidden}
    else
      {:user, _} -> {:error, :unauthenticated}
      {:site, _} -> {:error, :not_found}
      {:member, _} -> {:error, :not_found}
    end
  end

  @doc "Human message for an authorization failure."
  def message(:unauthenticated), do: "Your session ended. Sign in again."
  def message(:not_found), do: "Site not found."
  def message(:forbidden), do: "Your role on this site does not allow that."
  def message(_), do: "Request failed."

  @doc "The shell's user chip (email + GitHub avatar), no other profile data."
  def shell_user(nil), do: nil

  def shell_user(%{id: user_id, email: email}) do
    avatar =
      case Annotate.Repo.get_by(Annotate.Schema.Annotate.GithubIdentity, user_id: user_id) do
        %{avatar_url: url, login: login} -> %{avatar_url: url, login: login}
        nil -> %{avatar_url: nil, login: nil}
      end

    Map.merge(%{email: email}, avatar)
  end
end
