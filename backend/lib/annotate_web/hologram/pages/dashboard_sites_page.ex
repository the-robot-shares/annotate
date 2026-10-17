defmodule AnnotateWeb.Hologram.Pages.DashboardSitesPage do
  @moduledoc """
  Dashboard home (`/dashboard`): the signed-in owner's sites + "Add site".

  States: list · empty ("Add your first site") · add form (idle / validation
  errors / submitting) · **show-once service key modal** · error. Any
  GitHub-signed-in (verified) user may add sites (self-serve, per-user cap
  `Annotate.Sites.max_owned_sites/0`); the creator becomes the first owner,
  atomically (`Annotate.Sites.create_site_with_owner/2`).
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Hologram.DashboardAuth
  alias Annotate.SiteMembers
  alias Annotate.Sites
  alias AnnotateWeb.Hologram.Components.DashboardShell
  alias AnnotateWeb.Hologram.Layouts.DashboardLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/dashboard"
  layout DashboardLayout, page_title: "Sites — annotate dashboard"
  middleware RequireAuth

  def init(_params, component, server) do
    user = Auth.current_user(server)

    put_state(component,
      user: DashboardAuth.shell_user(user),
      sites: load_sites(user),
      show_form: false,
      form_name: "",
      form_slug: "",
      form_origins: "",
      creating: false,
      form_error: nil,
      key_modal: nil
    )
  end

  def template do
    ~HOLO"""
    <DashboardShell user={@user} sites={nav_sites(@sites)} title="Your sites"
      subtitle="Each site is one embeddable comment rail with its own origins, policy and inbox.">
      {%if @form_error}
        <p class="dsh-error" role="alert" data-cy="dsh-form-error">{@form_error}</p>
      {/if}

      {%if @sites == [] && !@show_form}
        <section class="dsh-panel" data-cy="dsh-empty">
          <h2 class="dsh-panel__title">No sites yet</h2>
          <div class="dsh-panel__body">
            <p class="dsh-hint">
              Create a site to get its service key and embed snippet. Keys are bound
              to the origins you register.
            </p>
            <div class="dsh-actions">
              <button type="button" class="dsh-btn dsh-btn--primary" $click={:show_form} data-cy="dsh-add-site">Create your first site</button>
            </div>
          </div>
        </section>
      {/if}

      {%if @sites != []}
        <section class="dsh-panel">
          <h2 class="dsh-panel__title">Sites ({length(@sites)})</h2>
          <div class="dsh-panel__body">
            <table class="dsh-table" data-cy="dsh-sites-table">
              <thead>
                <tr>
                  <th>Site</th>
                  <th>Reading</th>
                  <th>Members</th>
                  <th>Your role</th>
                </tr>
              </thead>
              <tbody>
                {%for s <- @sites}
                  <tr>
                    <td>
                      <a href={"/dashboard/sites/" <> s.slug} class="dsh-link" data-cy="dsh-site-link">{s.name}</a>
                      <div class="dsh-hint">{s.slug}</div>
                    </td>
                    <td>
                      {%if s.public_read}
                        <span class="dsh-chip">public read</span>
                      {%else}
                        <span class="dsh-chip dsh-chip--muted">sign-in to read</span>
                      {/if}
                    </td>
                    <td>{s.member_count}</td>
                    <td><span class="dsh-role">{s.role}</span></td>
                  </tr>
                {/for}
              </tbody>
            </table>
            {%if !@show_form}
              <div class="dsh-actions">
                <button type="button" class="dsh-btn dsh-btn--primary" $click={:show_form} data-cy="dsh-add-site">Add site</button>
              </div>
            {/if}
          </div>
        </section>
      {/if}

      {%if @show_form}
        <section class="dsh-panel" data-cy="dsh-add-form">
          <h2 class="dsh-panel__title">Add a site</h2>
          <div class="dsh-panel__body">
            <form class="dsh-form" $submit.prevent_default={:create}>
              <div class="dsh-grid-2">
                <div class="dsh-field">
                  <label for="new-site-name">Name</label>
                  <input id="new-site-name" type="text" value={@form_name} required maxlength="120"
                         placeholder="Example Product" $change={:set_name} />
                </div>
                <div class="dsh-field">
                  <label for="new-site-slug">Site code</label>
                  <input id="new-site-slug" type="text" value={@form_slug} required maxlength="120"
                         pattern="[a-z0-9][a-z0-9-]*" placeholder="example-product" $change={:set_slug} />
                  <p class="dsh-hint">Lowercase letters, digits and dashes. It goes in the embed tag.</p>
                </div>
              </div>
              <div class="dsh-field">
                <label for="new-site-origins">Allowed origins (one per line)</label>
                <textarea id="new-site-origins" rows="3" placeholder="https://example.com" $change={:set_origins}>{@form_origins}</textarea>
                <p class="dsh-hint">Exact <code>https://host[:port]</code> matches; no wildcards, paths or trailing slashes. <code>http://</code> only for localhost.</p>
              </div>
              <div class="dsh-actions">
                <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@creating} data-cy="dsh-create-site">
                  {%if @creating}Creating…{%else}Create site{/if}
                </button>
                <button type="button" class="dsh-btn dsh-btn--ghost" $click={:hide_form}>Cancel</button>
              </div>
            </form>
          </div>
        </section>
      {/if}

      {%if @key_modal}
        <div class="dsh-modal-overlay" role="dialog" aria-modal="true" aria-labelledby="dsh-key-title" data-cy="dsh-key-modal">
          <div class="dsh-modal">
            <h2 class="dsh-modal__title" id="dsh-key-title">Service key for {@key_modal.site}</h2>
            <p class="dsh-modal__warn">
              Shown once. Only needed if your own backend signs visitors in
              (host-assert); the embed snippet does not use it. Lost it? Rotate it
              from the site's Settings.
            </p>
            <code class="dsh-modal__key" id="dsh-service-key">{@key_modal.key}</code>
            <div class="dsh-modal__actions">
              <button type="button" class="dsh-btn dsh-btn--ghost" $click={:copy_key}>Copy</button>
              <a class="dsh-btn dsh-btn--primary" href={"/dashboard/sites/" <> @key_modal.site} data-cy="dsh-key-stored">I have stored it — open the site</a>
            </div>
          </div>
        </div>
      {/if}
    </DashboardShell>
    """
  end

  # ── actions (client) ──────────────────────────────────────────

  def action(:show_form, _params, c), do: put_state(c, show_form: true, form_error: nil)
  def action(:hide_form, _params, c), do: put_state(c, show_form: false, form_error: nil)
  def action(:set_name, params, c), do: put_state(c, :form_name, params.event.value)
  def action(:set_slug, params, c), do: put_state(c, :form_slug, params.event.value)
  def action(:set_origins, params, c), do: put_state(c, :form_origins, params.event.value)

  def action(:create, _params, c) do
    c
    |> put_state(creating: true, form_error: nil)
    |> put_command(:create_site,
      name: c.state.form_name,
      slug: c.state.form_slug,
      origins: c.state.form_origins
    )
  end

  def action(:copy_key, _params, c) do
    # Read from the DOM: the key never needs to round-trip through JS state.
    Hologram.JS.exec(
      "var e=document.getElementById('dsh-service-key');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    c
  end

  def action(:site_created, params, c) do
    put_state(c,
      creating: false,
      show_form: false,
      sites: params.sites,
      key_modal: %{site: params.slug, key: params.key},
      form_name: "",
      form_slug: "",
      form_origins: "",
      form_error: nil
    )
  end

  def action(:create_failed, params, c),
    do: put_state(c, creating: false, form_error: params.error || "Could not create the site.")

  # ── commands (server) ─────────────────────────────────────────

  def command(:create_site, params, server) do
    case Auth.current_user(server) do
      nil ->
        put_action(server, :create_failed, error: DashboardAuth.message(:unauthenticated))

      %{verified: true} = user ->
        if Annotate.Dashboard.Access.allowed?(user),
          do: do_create_site(server, user, params),
          else: put_action(server, :create_failed, error: DashboardAuth.message(:invite_required))

      _unverified ->
        put_action(server, :create_failed,
          error: "Verify your account (sign in with GitHub or Google) to add sites."
        )
    end
  end

  defp do_create_site(server, user, params) do
    origins =
      params.origins
      |> to_string()
      |> String.split(~r/[\r\n,]+/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    attrs = %{
      "slug" => params.slug |> to_string() |> String.trim(),
      "name" => params.name |> to_string() |> String.trim(),
      "allowed_origins" => origins
    }

    case Sites.create_site_with_owner(attrs, user) do
      {:ok, site, key} ->
        put_action(server, :site_created,
          sites: load_sites(user),
          slug: site.slug,
          key: key
        )

      {:error, reason} ->
        put_action(server, :create_failed, error: create_error(reason))
    end
  end

  # ── helpers ───────────────────────────────────────────────────

  defp load_sites(nil), do: []

  defp load_sites(%{id: user_id}) do
    user_id
    |> SiteMembers.list_sites_for_user()
    |> Enum.map(fn %{site: site, role: role, member_count: count} ->
      %{
        slug: site.slug,
        name: site.name || site.slug,
        public_read: Sites.public_read?(site),
        member_count: count,
        role: Atom.to_string(role)
      }
    end)
  end

  defp nav_sites(sites), do: Enum.map(sites, &%{slug: &1.slug, name: &1.name})

  @doc false
  def create_error(:invalid_origin),
    do:
      "Origins must be exact https://host[:port] values (one per line; no paths, wildcards or trailing slashes)."

  def create_error(:invite_required), do: DashboardAuth.message(:invite_required)

  def create_error(:site_limit),
    do: "You have reached the limit of #{Sites.max_owned_sites()} sites."

  def create_error(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn
      {:slug, ["has already been taken" | _]} -> "That site code is taken."
      {:slug, _} -> "Site code: lowercase letters, digits and dashes."
      {field, messages} -> "#{field} #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join(" ")
  end

  def create_error(_), do: "Could not create the site."
end
