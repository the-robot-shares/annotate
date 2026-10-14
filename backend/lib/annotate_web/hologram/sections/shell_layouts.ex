defmodule AnnotateWeb.Hologram.Sections.ShellLayouts do
  @moduledoc """
  Shell layouts from YAML + Login / Dashboard screen demos.

  - **Shells** — every entry in `style-guide.shell-layouts.yaml` as a screen-frame wireframe
  - **Login** — auth form screen (email → password pattern)
  - **Dashboard** — app shell with sidebar, KPIs, and panels
  """
  use Hologram.Component

  alias Annotate.StyleGuide.ThemeData

  prop :theme_slug, :string, default: "style-guide"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(props, component, _server), do: do_init(props, component)
  def init(props, component), do: do_init(props, component)

  defp do_init(props, component) do
    slug = Map.get(props, :theme_slug, "style-guide") || "style-guide"
    shells = ThemeData.shell_layouts(slug)

    put_state(component,
      theme_slug: slug,
      tab: "shells",
      shells: shells,
      shell_count: length(shells),
      active_shell: nil,
      login_step: "email",
      login_email: "you@example.com"
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-shell-layouts">
      <nav class="sg-subtabs hui tab-list" aria-label="Shell subsections">
        <button type="button" class="hui tab" data-selected={if @tab == "shells" do "" end} $click={:set_tab, id: "shells"}>
          Shells ({@shell_count})
        </button>
        <button type="button" class="hui tab" data-selected={if @tab == "login" do "" end} $click={:set_tab, id: "login"}>
          Login
        </button>
        <button type="button" class="hui tab" data-selected={if @tab == "dashboard" do "" end} $click={:set_tab, id: "dashboard"}>
          Dashboard
        </button>
      </nav>

      <p class="sg-page-intro app-muted" style="font-size: var(--font-size-sm); margin: var(--space-2) 0 var(--space-3)">
        {%if @tab == "shells"}
          Wireframes from <code>style-guide.shell-layouts.yaml</code> · theme <strong>{@theme_slug}</strong>.
          Click a shell to expand the live chrome preview.
        {/if}
        {%if @tab == "login"}
          Auth screen pattern used by hologram-start-app <code>/login</code> — multi-step email then password/SSO.
        {/if}
        {%if @tab == "dashboard"}
          App shell matching YAML <code>dashboard</code> + start-app <code>/app</code> and <code>/app/:org_id</code>.
        {/if}
      </p>

      {%if @tab == "shells"}
        <div class="sg-shell-grid">
          {%for shell <- @shells}
            <button
              type="button"
              class="sg-shell-card"
              data-selected={if @active_shell == shell.name do "" end}
              $click={:select_shell, id: shell.name}
            >
              <div class="screen-frame sg-shell-frame">
                <div class="screen-titlebar">
                  <span class="screen-dot"></span>
                  <span class="screen-dot"></span>
                  <span class="screen-dot"></span>
                  <span class="screen-url">{shell.name}.app/</span>
                </div>
                <div class="screen-body">
                  <div class={"sg-wireframe sg-wireframe--#{shell.name}"}>
                    {%if shell.has_navbar}
                      <div class="sg-wireframe__nav" style={"background: #{shell.navbar.background}; color: #{shell.navbar.color}"}>
                        {shell.navbar.label}
                      </div>
                    {/if}
                    <div class="sg-wireframe__mid">
                      {%if shell.has_sidebar}
                        <div class="sg-wireframe__side" style={"background: #{shell.sidebar.background}; color: #{shell.sidebar.color}"}>
                          <span class="sg-wireframe__side-label">{shell.sidebar.label}</span>
                          <span class="sg-wireframe__bar"></span>
                          <span class="sg-wireframe__bar"></span>
                          <span class="sg-wireframe__bar"></span>
                        </div>
                      {/if}
                      <div class="sg-wireframe__content">
                        {%for z <- shell.zones}
                          <div class="sg-wireframe__zone" style={"background: #{z.background}; color: #{z.color}; flex: #{z.ratio}"}>
                            {z.label}
                          </div>
                        {/for}
                      </div>
                      {%if shell.has_aside}
                        <div class="sg-wireframe__aside" style={"background: #{shell.aside.background}; color: #{shell.aside.color}"}>
                          {shell.aside.label}
                        </div>
                      {/if}
                    </div>
                    {%if shell.has_footer}
                      <div class="sg-wireframe__foot" style={"background: #{shell.footer.background}; color: #{shell.footer.color}"}>
                        {shell.footer.label}
                      </div>
                    {/if}
                  </div>
                </div>
              </div>
              <div class="sg-shell-card__meta">
                <div class="sg-shell-card__title">
                  {shell.title}
                  {%if @active_shell == shell.name}
                    <span class="sg-shell-card__badge">active</span>
                  {/if}
                </div>
                <div class="sg-shell-card__desc">{shell.description}</div>
              </div>
            </button>
          {/for}
        </div>
        {%if @shell_count == 0}
          <p class="app-muted">No shell-layouts.yaml found for this theme.</p>
        {/if}
      {/if}

      {%if @tab == "login"}
        <div class="screen-frame sg-screen-demo">
          <div class="screen-titlebar">
            <span class="screen-dot"></span>
            <span class="screen-dot"></span>
            <span class="screen-dot"></span>
            <span class="screen-url">app.example.com/login</span>
            <span class="screen-label">Login</span>
          </div>
          <div class="screen-body sg-login-screen">
            <div class="sg-login-panel">
              <div class="sg-login-brand">NOIZU</div>
              <h2 class="sg-login-title">Log in</h2>
              <p class="sg-login-sub">Continue to your workspace</p>

              {%if @login_step == "email"}
                <div class="sg-login-form">
                  <label class="field-label" for="demo-login-email">Email</label>
                  <input
                    id="demo-login-email"
                    class="field-input"
                    type="email"
                    value={@login_email}
                    $change={:set_login_email}
                  />
                  <button type="button" class="btn btn-black" style="width: 100%; margin-top: var(--space-2)" $click={:login_continue}>
                    Continue
                  </button>
                  <p class="sg-login-footer">Don't have an account? <span class="sg-login-link">Sign up</span></p>
                </div>
              {/if}

              {%if @login_step == "password"}
                <div class="sg-login-form">
                  <p class="sg-login-email-chip">{@login_email}</p>
                  <label class="field-label" for="demo-login-pass">Password</label>
                  <input id="demo-login-pass" class="field-input" type="password" value="••••••••" readonly />
                  <button type="button" class="btn btn-black" style="width: 100%; margin-top: var(--space-2)" $click={:login_submit_demo}>
                    Log in
                  </button>
                  <button type="button" class="btn btn-outline" style="width: 100%; margin-top: var(--space-1)" $click={:login_back}>
                    Change email
                  </button>
                  <p class="sg-login-footer"><span class="sg-login-link">Forgot password?</span></p>
                </div>
              {/if}

              {%if @login_step == "done"}
                <div class="sg-login-form" style="text-align: center">
                  <p class="sg-login-success">✓ Authenticated</p>
                  <p class="app-muted">In the start-app this routes to <code>/app</code> (dashboard home).</p>
                  <button type="button" class="btn btn-outline btn-sm" $click={:set_tab, id: "dashboard"}>
                    View dashboard demo →
                  </button>
                  <button type="button" class="btn btn-ghost btn-sm" style="margin-top: var(--space-1)" $click={:login_reset}>
                    Reset demo
                  </button>
                </div>
              {/if}
            </div>
          </div>
        </div>
      {/if}

      {%if @tab == "dashboard"}
        <div class="screen-frame sg-screen-demo">
          <div class="screen-titlebar">
            <span class="screen-dot"></span>
            <span class="screen-dot"></span>
            <span class="screen-dot"></span>
            <span class="screen-url">app.example.com/app/org-1</span>
            <span class="screen-label">Dashboard</span>
          </div>
          <div class="screen-body">
            <div class="sg-dash-shell">
              <aside class="sg-dash-sidebar" aria-label="Demo navigation">
                <div class="sg-dash-sidebar__head">
                  <span class="sg-dash-sidebar__brand">Workspace</span>
                  <span class="sg-dash-sidebar__user">you@example.com</span>
                </div>
                <nav class="sg-dash-nav">
                  <span class="sg-dash-link">Home</span>
                  <span class="sg-dash-link">Profile</span>
                  <span class="sg-dash-nav-section">Organization</span>
                  <span class="sg-dash-link sg-dash-link--active">Dashboard</span>
                  <span class="sg-dash-link">Members</span>
                  <span class="sg-dash-nav-section">Organizations</span>
                  <span class="sg-dash-link">Acme Corp</span>
                  <span class="sg-dash-link">Nero Labs</span>
                </nav>
              </aside>
              <div class="sg-dash-main">
                <header class="sg-dash-header">
                  <h2 class="sg-dash-title">Acme Corp</h2>
                  <div class="sg-dash-header-actions">
                    <button type="button" class="btn btn-outline btn-sm">Invite</button>
                    <button type="button" class="btn btn-black btn-sm">New project</button>
                  </div>
                </header>
                <div class="sg-dash-body">
                  <div class="app-kpi-row">
                    <div class="app-kpi">
                      <div class="app-kpi__value">12</div>
                      <div class="app-kpi__label">Members</div>
                    </div>
                    <div class="app-kpi">
                      <div class="app-kpi__value">4</div>
                      <div class="app-kpi__label">Projects</div>
                    </div>
                    <div class="app-kpi">
                      <div class="app-kpi__value">Live</div>
                      <div class="app-kpi__label">Workspace</div>
                    </div>
                  </div>
                  <div class="sg-dash-panels">
                    <section class="sg-dash-panel">
                      <h3 class="sg-dash-panel__title">Quick actions</h3>
                      <div class="sg-dash-panel__body">
                        <button type="button" class="btn btn-black btn-sm">Manage members</button>
                        <p class="app-muted" style="margin-top: var(--space-1)">Invite users via admin tools. Membership is PBAC-scoped.</p>
                      </div>
                    </section>
                    <section class="sg-dash-panel">
                      <h3 class="sg-dash-panel__title">Overview</h3>
                      <div class="sg-dash-panel__body sg-dash-cards">
                        <div class="card">
                          <div class="card-title">Projects</div>
                          <div class="card-body">Scaffold project lists and detail screens here.</div>
                        </div>
                        <div class="card">
                          <div class="card-title">Activity</div>
                          <div class="card-body">Recent events, audits, and notifications.</div>
                        </div>
                      </div>
                    </section>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
        <p class="app-muted" style="margin-top: var(--space-2); font-size: var(--font-size-sm)">
          Live implementation: hologram-start-app <code>/app</code> (home) → <code>/app/:org_id</code> (org dashboard) via <code>AppShell</code>.
        </p>
      {/if}
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_tab, params, component) do
    put_state(component, tab: params.id)
  end

  def action(:select_shell, params, component) do
    id = params.id
    next = if component.state.active_shell == id, do: nil, else: id
    put_state(component, active_shell: next)
  end

  def action(:set_login_email, params, component) do
    put_state(component, login_email: params.event.value || "")
  end

  def action(:login_continue, _params, component) do
    put_state(component, login_step: "password")
  end

  def action(:login_back, _params, component) do
    put_state(component, login_step: "email")
  end

  def action(:login_submit_demo, _params, component) do
    put_state(component, login_step: "done")
  end

  def action(:login_reset, _params, component) do
    put_state(component, login_step: "email", login_email: "you@example.com")
  end
end
