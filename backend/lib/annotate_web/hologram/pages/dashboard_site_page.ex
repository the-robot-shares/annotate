defmodule AnnotateWeb.Hologram.Pages.DashboardSitePage do
  @moduledoc """
  One site (`/dashboard/sites/:site_slug`), tabbed:

  - **Overview** (member+): site code + embed snippet (copy button), API base,
    host-assert note.
  - **Settings**: display settings (admin+) · security settings: origins +
    comment policy (owner) · service-key rotation (owner, show-once modal).
  - **Members** (list: member+; add verified users / change role / remove:
    owner; last-owner lockout surfaced).

  Every command re-authorizes against the DB (`DashboardAuth.authorize_site/3`)
  before acting; a site the user is not a member of renders "not found".
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Hologram.DashboardAuth
  alias Annotate.SiteMembers
  alias Annotate.Sites
  alias AnnotateWeb.Hologram.Components.DashboardShell
  alias AnnotateWeb.Hologram.Components.InboxPanel
  alias AnnotateWeb.Hologram.Layouts.DashboardLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/dashboard/sites/:site_slug"
  param :site_slug, :string
  layout DashboardLayout, page_title: "Site — annotate dashboard"
  middleware RequireAuth

  def init(params, component, server) do
    user = Auth.current_user(server)

    base = [
      user: DashboardAuth.shell_user(user),
      nav: nav_sites(user),
      tab: "overview",
      flash: nil,
      error: nil,
      key_modal: nil,
      confirm_rotate: false,
      busy: false,
      snippet: snippet_parts()
    ]

    case DashboardAuth.authorize_site(server, params.site_slug, :member) do
      {:ok, user, site, role} ->
        counts = Annotate.Comments.site_thread_counts(site.id)

        put_state(
          component,
          base ++
            [
              status: "ok",
              # Owners land on the inbox when there is something to answer.
              tab: if(counts.open > 0, do: "inbox", else: "overview"),
              slug: site.slug,
              role: Atom.to_string(role),
              site: serialize_site(site),
              members: serialize_members(site, user),
              form: form_from_site(site),
              member_email: "",
              member_role: "member"
            ]
        )

      {:error, reason} ->
        put_state(
          component,
          base ++
            [status: "error", slug: params.site_slug, message: DashboardAuth.message(reason)]
        )
    end
  end

  def template do
    ~HOLO"""
    {%if @status == "ok"}
      <DashboardShell user={@user} sites={@nav} site_slug={@slug} title={@site.name}
        subtitle={"Site code " <> @slug <> " · your role: " <> @role}>
        {%if @flash}
          <p class="dsh-flash" role="status" data-cy="dsh-flash">{@flash}</p>
        {/if}
        {%if @error}
          <p class="dsh-error" role="alert" data-cy="dsh-error">{@error}</p>
        {/if}

        <div class="dsh-tabs" role="tablist" aria-label="Site sections">
          <button type="button" role="tab" class={tab_class(@tab, "inbox")} aria-selected={@tab == "inbox"} $click={action: :tab, params: %{tab: "inbox"}} data-cy="dsh-tab-inbox">Inbox</button>
          <button type="button" role="tab" class={tab_class(@tab, "overview")} aria-selected={@tab == "overview"} $click={action: :tab, params: %{tab: "overview"}} data-cy="dsh-tab-overview">Overview</button>
          <button type="button" role="tab" class={tab_class(@tab, "settings")} aria-selected={@tab == "settings"} $click={action: :tab, params: %{tab: "settings"}} data-cy="dsh-tab-settings">Settings</button>
          <button type="button" role="tab" class={tab_class(@tab, "members")} aria-selected={@tab == "members"} $click={action: :tab, params: %{tab: "members"}} data-cy="dsh-tab-members">Members<span class="dsh-tab__count">{length(@members)}</span></button>
        </div>

        <div class={pane_class(@tab, "inbox")}>
          <InboxPanel cid="dsh_inbox" slug={@slug} role={@role} />
        </div>

        {%if @tab == "overview"}
          <section class="dsh-panel" data-cy="dsh-snippet">
            <h2 class="dsh-panel__title">Embed snippet</h2>
            <div class="dsh-panel__body">
              <p class="dsh-hint">Paste this before <code>&lt;/body&gt;</code> on any page served from one of the site's allowed origins. The widget loads collapsed (a small comment-count pill); add <code>default-open</code> to start it expanded.</p>
              <h3 class="dsh-panel__subtitle">Latest (recommended)</h3>
              <pre class="dsh-code" tabindex="0" data-cy="dsh-snippet-latest"><code id="dsh-snippet-code">&lt;script type="module" src="{@snippet.latest_src}"&gt;&lt;/script&gt;
    &lt;noizu-page-comments site="{@slug}" api-base="{@snippet.api_base}"&gt;&lt;/noizu-page-comments&gt;</code></pre>
              <div class="dsh-actions">
                <button type="button" class="dsh-btn dsh-btn--primary" $click={:copy_snippet, which: "latest"} data-cy="dsh-copy-snippet">Copy snippet</button>
              </div>
              <h3 class="dsh-panel__subtitle">Pinned version ({@snippet.version})</h3>
              <pre class="dsh-code" tabindex="0" data-cy="dsh-snippet-pinned"><code id="dsh-snippet-code-pinned">&lt;script type="module" src="{@snippet.pinned_src}"&gt;&lt;/script&gt;
    &lt;noizu-page-comments site="{@slug}" api-base="{@snippet.api_base}"&gt;&lt;/noizu-page-comments&gt;</code></pre>
              <div class="dsh-actions">
                <button type="button" class="dsh-btn" $click={:copy_snippet, which: "pinned"} data-cy="dsh-copy-snippet-pinned">Copy pinned snippet</button>
              </div>
              <p class="dsh-hint" data-cy="dsh-snippet-tradeoff">Latest picks up widget fixes automatically (within minutes, up to a few hours in a cached browser); pinned never changes until you edit the version.</p>
              <dl class="dsh-kv">
                <dt>Site code</dt><dd data-cy="dsh-site-code">{@slug}</dd>
                <dt>API base</dt><dd>{@snippet.api_base}</dd>
                <dt>Allowed origins</dt><dd>{Enum.join(@site.allowed_origins, ", ")}</dd>
              </dl>
              <p class="dsh-hint">
                Visitors sign in through the widget's popup. If your own backend already knows
                who is signed in, it can vouch for them instead (host-assert, signed with the
                site's service key; see the API docs). The key is shown once at creation;
                rotate it in Settings to get a new one.
              </p>
            </div>
          </section>
        {/if}

        {%if @tab == "settings"}
          <section class="dsh-panel" data-cy="dsh-display-settings">
            <h2 class="dsh-panel__title">Display settings</h2>
            <div class="dsh-panel__body">
              {%if role_at_least(@role, "admin")}
                <form class="dsh-form" $submit.prevent_default={:save_display}>
                  <div class="dsh-grid-2">
                    <div class="dsh-field">
                      <label for="s-name">Name</label>
                      <input id="s-name" type="text" value={@form.name} maxlength="120" required $change={action: :set_form, params: %{field: "name"}} />
                    </div>
                    <div class="dsh-field">
                      <label for="s-public-read">Who can read comments</label>
                      <select id="s-public-read" $change={action: :set_form, params: %{field: "public_read"}}>
                        <option value="true" selected={@form.public_read == "true"}>Anyone on the page</option>
                        <option value="false" selected={@form.public_read == "false"}>Signed-in visitors only</option>
                      </select>
                    </div>
                    <div class="dsh-field">
                      <label for="s-max-upload">Max upload (MB)</label>
                      <input id="s-max-upload" type="number" min="1" max="100" value={@form.max_upload_mb} $change={action: :set_form, params: %{field: "max_upload_mb"}} />
                    </div>
                    <div class="dsh-field">
                      <label for="s-visibility">Default visibility</label>
                      <select id="s-visibility" $change={action: :set_form, params: %{field: "default_visibility"}}>
                        <option value="public" selected={@form.default_visibility == "public"}>Public</option>
                        <option value="internal" selected={@form.default_visibility == "internal"}>Internal (team only)</option>
                      </select>
                    </div>
                  </div>
                  <div class="dsh-actions">
                    <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@busy} data-cy="dsh-save-display">Save display settings</button>
                  </div>
                </form>
              {%else}
                <p class="dsh-hint">Admins and owners can change display settings.</p>
              {/if}
            </div>
          </section>

          <section class="dsh-panel" data-cy="dsh-security-settings">
            <h2 class="dsh-panel__title">Security settings</h2>
            <div class="dsh-panel__body">
              {%if @role == "owner"}
                <form class="dsh-form" $submit.prevent_default={:save_security}>
                  <div class="dsh-field">
                    <label for="s-origins">Allowed origins (one per line)</label>
                    <textarea id="s-origins" rows="3" $change={action: :set_form, params: %{field: "origins"}}>{@form.origins}</textarea>
                    <p class="dsh-hint">Exact <code>https://host[:port]</code> only. The widget and sign-in popup work only on these origins.</p>
                  </div>
                  <div class="dsh-field" data-cy="dsh-read-visibility">
                    <label for="s-readvis">Who can read comments</label>
                    <select id="s-readvis" data-cy="dsh-read-visibility-select" $change={action: :set_form, params: %{field: "read_visibility"}}>
                      <option value="public" selected={@form.read_visibility == "public"}>Everyone who can open the widget</option>
                      <option value="staff_only" selected={@form.read_visibility == "staff_only"}>Staff only (others see just their own threads)</option>
                    </select>
                    <p class="dsh-hint">Staff only: your team (owners, admins and members, plus host-asserted team roles when "Trust host-asserted team roles" is on) sees every thread. Everyone else sees only the threads they started and every reply in them, including yours. Anonymous visitors see none. Enforced by the server on every read and live update, not just in the widget.</p>
                  </div>
                  <div class="dsh-grid-2">
                    <div class="dsh-field">
                      <label for="s-anon">Anonymous threads</label>
                      <select id="s-anon" $change={action: :set_form, params: %{field: "allow_anonymous"}}>
                        <option value="false" selected={@form.allow_anonymous == "false"}>Off (sign-in required)</option>
                        <option value="true" selected={@form.allow_anonymous == "true"}>On</option>
                      </select>
                    </div>
                    <div class="dsh-field">
                      <label for="s-trust">Trust host-asserted team roles</label>
                      <select id="s-trust" $change={action: :set_form, params: %{field: "trust_host_roles"}}>
                        <option value="false" selected={@form.trust_host_roles == "false"}>Off</option>
                        <option value="true" selected={@form.trust_host_roles == "true"}>On (anyone holding the service key can mint team roles)</option>
                      </select>
                    </div>
                    <div class="dsh-field">
                      <label for="s-groups">Required groups (comma separated)</label>
                      <input id="s-groups" type="text" value={@form.required_groups} $change={action: :set_form, params: %{field: "required_groups"}} />
                    </div>
                    <div class="dsh-field">
                      <label for="s-domains">Allowed email domains (comma separated)</label>
                      <input id="s-domains" type="text" value={@form.allowed_email_domains} $change={action: :set_form, params: %{field: "allowed_email_domains"}} />
                    </div>
                  </div>
                  <div class="dsh-actions">
                    <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@busy} data-cy="dsh-save-security">Save security settings</button>
                  </div>
                </form>
              {%else}
                <p class="dsh-hint">Only owners can change origins and the comment policy.</p>
              {/if}
            </div>
          </section>

          {%if @role == "owner"}
            <section class="dsh-panel dsh-panel--danger" data-cy="dsh-rotate">
              <h2 class="dsh-panel__title">Service key</h2>
              <div class="dsh-panel__body">
                <p class="dsh-hint">Rotating issues a new key and invalidates the old one immediately; host-assert sign-ins fail until your backend uses the new key.</p>
                {%if @confirm_rotate}
                  <div class="dsh-actions">
                    <button type="button" class="dsh-btn dsh-btn--danger" $click={:rotate_key} disabled={@busy} data-cy="dsh-rotate-confirm">Yes, rotate the key</button>
                    <button type="button" class="dsh-btn dsh-btn--ghost" $click={:cancel_rotate}>Cancel</button>
                  </div>
                {%else}
                  <div class="dsh-actions">
                    <button type="button" class="dsh-btn dsh-btn--danger" $click={:ask_rotate} data-cy="dsh-rotate-start">Rotate service key</button>
                  </div>
                {/if}
              </div>
            </section>
          {/if}
        {/if}

        {%if @tab == "members"}
          <section class="dsh-panel" data-cy="dsh-members">
            <h2 class="dsh-panel__title">Members</h2>
            <div class="dsh-panel__body">
              <table class="dsh-table">
                <thead><tr><th>Member</th><th>Role</th><th></th></tr></thead>
                <tbody>
                  {%for m <- @members}
                    <tr data-cy="dsh-member-row">
                      <td>{m.email}{%if m.you} <span class="dsh-chip dsh-chip--muted">you</span>{/if}</td>
                      <td>
                        {%if @role == "owner"}
                          <select aria-label={"Role for " <> m.email} $change={action: :change_role, params: %{user_id: m.user_id}}>
                            <option value="owner" selected={m.role == "owner"}>owner</option>
                            <option value="admin" selected={m.role == "admin"}>admin</option>
                            <option value="member" selected={m.role == "member"}>member</option>
                          </select>
                        {%else}
                          <span class="dsh-role">{m.role}</span>
                        {/if}
                      </td>
                      <td>
                        {%if @role == "owner"}
                          <button type="button" class="dsh-btn dsh-btn--danger dsh-btn--sm" $click={action: :remove_member, params: %{user_id: m.user_id}}>Remove</button>
                        {/if}
                      </td>
                    </tr>
                  {/for}
                </tbody>
              </table>

              {%if @role == "owner"}
                <form class="dsh-form" $submit.prevent_default={:add_member}>
                  <div class="dsh-grid-2">
                    <div class="dsh-field">
                      <label for="m-email">Add a member by email</label>
                      <input id="m-email" type="email" value={@member_email} required $change={:set_member_email} />
                      <p class="dsh-hint">They must have signed in to annotate (GitHub or Google, verified email) and have access.</p>
                    </div>
                    <div class="dsh-field">
                      <label for="m-role">Role</label>
                      <select id="m-role" $change={:set_member_role}>
                        <option value="member" selected={@member_role == "member"}>member: view, reply, resolve</option>
                        <option value="admin" selected={@member_role == "admin"}>admin: + display settings, moderation</option>
                        <option value="owner" selected={@member_role == "owner"}>owner: + security, members, key</option>
                      </select>
                    </div>
                  </div>
                  <div class="dsh-actions">
                    <button type="submit" class="dsh-btn dsh-btn--primary" disabled={@busy} data-cy="dsh-add-member">Add member</button>
                  </div>
                </form>
              {/if}
            </div>
          </section>
        {/if}

        {%if @key_modal}
          <div class="dsh-modal-overlay" role="dialog" aria-modal="true" aria-labelledby="dsh-key-title" data-cy="dsh-key-modal">
            <div class="dsh-modal">
              <h2 class="dsh-modal__title" id="dsh-key-title">New service key for {@slug}</h2>
              <p class="dsh-modal__warn">Shown once. The previous key no longer works.</p>
              <code class="dsh-modal__key" id="dsh-service-key">{@key_modal}</code>
              <div class="dsh-modal__actions">
                <button type="button" class="dsh-btn dsh-btn--ghost" $click={:copy_key}>Copy</button>
                <button type="button" class="dsh-btn dsh-btn--primary" $click={:key_stored} data-cy="dsh-key-stored">I have stored it</button>
              </div>
            </div>
          </div>
        {/if}
      </DashboardShell>
    {%else}
      <DashboardShell user={@user} sites={@nav} title="Site not available">
        <section class="dsh-panel" data-cy="dsh-site-error">
          <div class="dsh-panel__body">
            <p>{@message}</p>
            <p><a class="dsh-btn" href="/dashboard">Back to your sites</a></p>
          </div>
        </section>
      </DashboardShell>
    {/if}
    """
  end

  # ── actions (client) ──────────────────────────────────────────

  def action(:tab, params, c), do: put_state(c, tab: params.tab, flash: nil, error: nil)

  def action(:set_form, params, c),
    do:
      put_state(
        c,
        :form,
        Map.put(c.state.form, String.to_existing_atom(params.field), params.event.value)
      )

  def action(:set_member_email, params, c), do: put_state(c, :member_email, params.event.value)
  def action(:set_member_role, params, c), do: put_state(c, :member_role, params.event.value)

  def action(:save_display, _params, c) do
    f = c.state.form

    c
    |> busy()
    |> put_command(:save_display,
      slug: c.state.slug,
      name: f.name,
      public_read: f.public_read,
      max_upload_mb: f.max_upload_mb,
      default_visibility: f.default_visibility
    )
  end

  def action(:save_security, _params, c) do
    f = c.state.form

    c
    |> busy()
    |> put_command(:save_security,
      slug: c.state.slug,
      origins: f.origins,
      read_visibility: f.read_visibility,
      allow_anonymous: f.allow_anonymous,
      trust_host_roles: f.trust_host_roles,
      required_groups: f.required_groups,
      allowed_email_domains: f.allowed_email_domains
    )
  end

  def action(:ask_rotate, _params, c), do: put_state(c, confirm_rotate: true)
  def action(:cancel_rotate, _params, c), do: put_state(c, confirm_rotate: false)

  def action(:rotate_key, _params, c),
    do: c |> busy() |> put_command(:rotate_key, slug: c.state.slug)

  def action(:key_stored, _params, c), do: put_state(c, key_modal: nil)

  def action(:add_member, _params, c),
    do:
      c
      |> busy()
      |> put_command(:add_member,
        slug: c.state.slug,
        email: c.state.member_email,
        role: c.state.member_role
      )

  def action(:change_role, params, c),
    do:
      c
      |> busy()
      |> put_command(:change_role,
        slug: c.state.slug,
        user_id: params.user_id,
        role: params.event.value
      )

  def action(:remove_member, params, c),
    do: c |> busy() |> put_command(:remove_member, slug: c.state.slug, user_id: params.user_id)

  def action(:copy_snippet, params, c) do
    # Read from the DOM: the multi-line snippet never rides in page state.
    {id, flash} =
      case Map.get(params, :which) do
        "pinned" -> {"dsh-snippet-code-pinned", "Pinned snippet copied."}
        _ -> {"dsh-snippet-code", "Snippet copied."}
      end

    Hologram.JS.exec(
      "var e=document.getElementById('#{id}');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    put_state(c, flash: flash)
  end

  def action(:copy_key, _params, c) do
    Hologram.JS.exec(
      "var e=document.getElementById('dsh-service-key');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    c
  end

  def action(:updated, params, c) do
    c
    |> put_state(
      busy: false,
      error: nil,
      flash: params.flash,
      site: params.site,
      members: params.members,
      form: params.form,
      confirm_rotate: false
    )
    |> maybe_member_reset(params)
  end

  def action(:key_rotated, params, c),
    do:
      put_state(c,
        busy: false,
        confirm_rotate: false,
        key_modal: params.key,
        flash: "Service key rotated.",
        error: nil
      )

  def action(:failed, params, c), do: put_state(c, busy: false, flash: nil, error: params.error)

  defp busy(c), do: put_state(c, busy: true, flash: nil, error: nil)

  defp maybe_member_reset(c, %{reset_member: true}),
    do: put_state(c, member_email: "", member_role: "member")

  defp maybe_member_reset(c, _), do: c

  # ── commands (server) ─────────────────────────────────────────

  def command(:save_display, params, server) do
    with_site(server, params.slug, :admin, fn _user, site ->
      attrs = %{
        "name" => to_string(params.name),
        "settings" => %{
          "public_read" => params.public_read == "true",
          "max_upload_mb" => parse_int(params.max_upload_mb),
          "default_visibility" => to_string(params.default_visibility)
        }
      }

      case Sites.update_site_display(site, attrs) do
        {:ok, site} -> {:ok, site, "Display settings saved."}
        {:error, :invalid_settings} -> {:error, "Check the values: upload size 1–100 MB."}
        {:error, %Ecto.Changeset{}} -> {:error, "Name is required (max 120 characters)."}
      end
    end)
  end

  def command(:save_security, params, server) do
    with_site(server, params.slug, :owner, fn _user, site ->
      attrs = %{
        "allowed_origins" => split_lines(params.origins),
        "comment_policy" =>
          %{
            "allow_anonymous" => params.allow_anonymous == "true",
            "trust_host_roles" => params.trust_host_roles == "true",
            "required_groups" => split_list(params.required_groups),
            "allowed_email_domains" => split_list(params.allowed_email_domains)
          }
          |> put_read_visibility(Map.get(params, :read_visibility))
      }

      case Sites.update_site_security(site, attrs) do
        {:ok, site} ->
          {:ok, site, "Security settings saved."}

        {:error, :invalid_origin} ->
          {:error, AnnotateWeb.Hologram.Pages.DashboardSitesPage.create_error(:invalid_origin)}

        {:error, _} ->
          {:error, "Could not save the policy."}
      end
    end)
  end

  def command(:rotate_key, params, server) do
    case DashboardAuth.authorize_site(server, params.slug, :owner) do
      {:ok, _user, site, _role} ->
        {:ok, _site, key} = Sites.rotate_service_key(site)
        put_action(server, :key_rotated, key: key)

      {:error, reason} ->
        put_action(server, :failed, error: DashboardAuth.message(reason))
    end
  end

  def command(:add_member, params, server) do
    with_site(server, params.slug, :owner, fn user, site ->
      case SiteMembers.add_member(site, to_string(params.email), to_string(params.role), user) do
        {:ok, _} ->
          {:ok, site, "Member added.", reset_member: true}

        {:error, :user_not_found} ->
          {:error,
           "No annotate account with that email. Ask them to sign in first (GitHub or Google)."}

        {:error, :user_not_verified} ->
          {:error, "That account's email is not verified."}

        {:error, :user_not_active} ->
          {:error, "That account hasn't been invited to annotate yet. Send them an invite first."}

        {:error, :already_member} ->
          {:error, "Already a member."}

        {:error, :invalid_role} ->
          {:error, "Pick a role."}

        {:error, _} ->
          {:error, "Could not add the member."}
      end
    end)
  end

  def command(:change_role, params, server) do
    with_site(server, params.slug, :owner, fn _user, site ->
      case SiteMembers.update_role(site, to_string(params.user_id), to_string(params.role)) do
        {:ok, _} ->
          {:ok, site, "Role updated."}

        {:error, :last_owner} ->
          {:error, "A site needs at least one owner. Promote someone else first."}

        {:error, _} ->
          {:error, "Could not change the role."}
      end
    end)
  end

  def command(:remove_member, params, server) do
    with_site(server, params.slug, :owner, fn _user, site ->
      case SiteMembers.remove_member(site, to_string(params.user_id)) do
        {:ok, _} ->
          {:ok, site, "Member removed."}

        {:error, :last_owner} ->
          {:error, "A site needs at least one owner. Promote someone else first."}

        {:error, _} ->
          {:error, "Could not remove the member."}
      end
    end)
  end

  # Authorize (DB, per command) then run `fun.(user, site)`; reply with the
  # refreshed site/members/form or an error. Members lists are only ever
  # rendered for the authorized site.
  defp with_site(server, slug, min_role, fun) do
    case DashboardAuth.authorize_site(server, slug, min_role) do
      {:ok, user, site, _role} ->
        case fun.(user, site) do
          {:ok, site, flash} -> reply_updated(server, user, site, flash, false)
          {:ok, site, flash, reset_member: true} -> reply_updated(server, user, site, flash, true)
          {:error, message} -> put_action(server, :failed, error: message)
        end

      {:error, reason} ->
        put_action(server, :failed, error: DashboardAuth.message(reason))
    end
  end

  defp reply_updated(server, user, site, flash, reset_member) do
    site = Sites.get_site!(site.id)

    put_action(server, :updated,
      flash: flash,
      site: serialize_site(site),
      members: serialize_members(site, user),
      form: form_from_site(site),
      reset_member: reset_member
    )
  end

  # ── helpers ───────────────────────────────────────────────────

  # The inbox stays mounted (its server init owns the realtime subscription);
  # other tabs just hide it.
  def pane_class(tab, tab), do: "dsh-pane"
  def pane_class(_, _), do: "dsh-pane dsh-hidden"

  def tab_class(tab, tab), do: "dsh-tab dsh-tab--active"
  def tab_class(_, _), do: "dsh-tab"

  def role_at_least(role, min) do
    rank = %{"owner" => 3, "admin" => 2, "member" => 1}
    Map.get(rank, role, 0) >= Map.get(rank, min, 99)
  end

  defp nav_sites(nil), do: []

  defp nav_sites(%{id: user_id}),
    do:
      user_id
      |> SiteMembers.list_sites_for_user()
      |> Enum.map(&%{slug: &1.site.slug, name: &1.site.name || &1.site.slug})

  defp serialize_site(site) do
    %{
      name: site.name || site.slug,
      allowed_origins: site.allowed_origins || []
    }
  end

  # Only an explicit, known value is written: a command without the key (a
  # page loaded before this field shipped) must never reset staff_only.
  defp put_read_visibility(policy, v) when v in ["public", "staff_only"],
    do: Map.put(policy, "read_visibility", v)

  defp put_read_visibility(policy, _), do: policy

  defp form_from_site(site) do
    policy = site.comment_policy || %{}

    %{
      name: site.name || "",
      public_read: to_string(Sites.public_read?(site)),
      max_upload_mb: to_string(Sites.max_upload_mb(site)),
      default_visibility: Atom.to_string(Sites.default_visibility(site)),
      # Single-line join: multi-line strings must not ride in page state.
      origins: Enum.join(site.allowed_origins || [], " "),
      read_visibility: Atom.to_string(Sites.read_visibility(site)),
      allow_anonymous: to_string(Sites.allow_anonymous?(site)),
      trust_host_roles: to_string(Sites.trust_host_roles?(site)),
      required_groups: Enum.join(List.wrap(policy["required_groups"]), ", "),
      allowed_email_domains: Enum.join(List.wrap(policy["allowed_email_domains"]), ", ")
    }
  end

  defp serialize_members(site, user) do
    site
    |> SiteMembers.list_members()
    |> Enum.map(fn m ->
      %{
        user_id: m.user_id,
        email: m.email,
        role: Atom.to_string(m.role),
        you: m.user_id == user.id
      }
    end)
  end

  defp snippet_parts do
    cfg = Application.get_env(:annotate, :marketing) || []

    %{
      latest_src: AnnotateWeb.WidgetCdn.latest_src(),
      pinned_src: AnnotateWeb.WidgetCdn.pinned_src(),
      version: AnnotateWeb.WidgetCdn.version(),
      api_base: Keyword.get(cfg, :api_base, "https://annotate-srv.therobotlives.com")
    }
  end

  defp split_lines(text), do: text |> to_string() |> String.split(~r/[\s,]+/, trim: true)

  defp split_list(text),
    do:
      text
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      :error -> 0
    end
  end
end
