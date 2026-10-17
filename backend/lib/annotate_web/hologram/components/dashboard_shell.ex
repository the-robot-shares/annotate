defmodule AnnotateWeb.Hologram.Components.DashboardShell do
  @moduledoc """
  Owner-dashboard chrome: Night Desk sidebar (sites quick-nav, user chip,
  sign out) + main region.

  Props:
  - `user`: `%{email, avatar_url, login}` (`DashboardAuth.shell_user/1`).
  - `sites`: the user's sites (`%{slug, name}`), rendered as quick nav.
  - `site_slug`: the site this screen is scoped to (nil on the sites list).
  - `title` / `subtitle`: screen heading.

  **Stateless on purpose**: events in the slotted page content must target
  the page (a stateful shell would capture them). Sign-out lives in the
  stateful `SignOutButton`.
  """

  use Hologram.Component

  alias AnnotateWeb.Hologram.Components.SignOutButton
  alias AnnotateWeb.Hologram.Components.SiteFooter

  prop :user, :map, default: nil
  prop :sites, :list, default: []
  prop :site_slug, :string, default: nil
  prop :title, :string, default: nil
  prop :subtitle, :string, default: nil

  def template do
    ~HOLO"""
    <div class="dsh-shell">
      <aside class="dsh-sidebar" aria-label="Dashboard navigation">
        <div class="dsh-sidebar__brand">
          <a class="dsh-sidebar__mark" href="/">annotate</a>
          <span class="dsh-sidebar__kicker">owner dashboard</span>
        </div>
        <nav class="dsh-nav">
          <a href="/dashboard" class={site_class(@site_slug, nil)} data-cy="dsh-nav-sites">All sites</a>
          <a href="/dashboard/agents" class="dsh-nav__link" data-cy="dsh-nav-agents">Agents</a>
          <a href="/dashboard/billing" class="dsh-nav__link" data-cy="dsh-nav-billing">Billing</a>
          {%if @user && @user.can_invite}
            <a href="/dashboard/invites" class="dsh-nav__link" data-cy="dsh-nav-invites">Invites</a>
          {/if}
        </nav>
        {%if @sites != []}
          <div class="dsh-sidebar__sites">
            <div class="dsh-nav__section">Your sites</div>
            {%for s <- @sites}
              <a href={"/dashboard/sites/" <> s.slug} class={site_class(@site_slug, s.slug)}>{s.name}</a>
            {/for}
          </div>
        {/if}
        <div class="dsh-sidebar__foot">
          {%if @user}
            <span class="dsh-sidebar__user">
              {%if @user.avatar_url}
                <img class="dsh-avatar" src={@user.avatar_url} alt="" width="24" height="24" />
              {/if}
              {@user.email}
            </span>
          {/if}
          <SignOutButton cid="dsh_sign_out" />
        </div>
      </aside>
      <div class="dsh-main">
        {%if @title}
          <header class="dsh-main__header">
            <h1 class="dsh-main__title">{@title}</h1>
            {%if @subtitle}
              <p class="dsh-main__sub">{@subtitle}</p>
            {/if}
          </header>
        {/if}
        <main class="dsh-main__body" id="main">
          <slot />
        </main>
        <SiteFooter />
      </div>
    </div>
    """
  end

  def site_class(current, slug) when current == slug, do: "dsh-nav__link dsh-nav__link--active"
  def site_class(_, _), do: "dsh-nav__link"
end
