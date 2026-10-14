defmodule StarterWeb.Hologram.Sections.HuiShowcase do
  @moduledoc """
  Interactive HUI (Headless-UI-styled) control gallery.

  Submenu selects which control family to demo. State toggles use
  `data-checked` / `data-selected` / `data-open` attributes expected by theme CSS.
  """
  use Hologram.Component

  @submenu [
    %{id: "checkbox", label: "Checkbox"},
    %{id: "switch", label: "Switch"},
    %{id: "radio", label: "Radio"},
    %{id: "tabs", label: "Tabs"},
    %{id: "disclosure", label: "Disclosure"},
    %{id: "menu", label: "Menu"},
    %{id: "listbox", label: "Listbox"},
    %{id: "combobox", label: "Combobox"},
    %{id: "popover", label: "Popover"},
    %{id: "dialog", label: "Dialog"},
    %{id: "fields", label: "Fields"}
  ]

  # SSR (only if already on HUI section at first paint)
  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(props, component, _server), do: do_init(props, component)

  # Client mount when user navigates to HUI after page load (required)
  def init(props, component), do: do_init(props, component)

  defp do_init(_props, component) do
    put_state(component,
      submenu: @submenu,
      panel: "checkbox",
      checks: %{"notifs" => true, "dark" => false, "beta" => true},
      switches: %{"wifi" => true, "bt" => false, "vpn" => true},
      radio: "edit",
      tab: "overview",
      disc_open: %{"q1" => true, "q2" => false},
      menu_open: false,
      listbox_open: false,
      listbox_value: "Default",
      combo_open: false,
      combo_query: "",
      combo_value: "Alice Chen",
      popover_open: false,
      dialog_open: false
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="hui-showcase-root">
      <p class="sg-page-intro" style="color: var(--text-secondary); margin-bottom: var(--space-3)">
        HUI shells use design-system classes (<code>.hui</code> + control modifiers).
        Submenu selects a control family; each demo is interactive via Hologram actions.
      </p>

      <nav class="hui-subnav hui tab-list" aria-label="HUI control families">
        {%for item <- @submenu}
          <button
            type="button"
            class="hui tab"
            data-selected={if item.id == @panel do "" end}
            $click={:select_panel, id: item.id}
          >
            {item.label}
          </button>
        {/for}
      </nav>

      <div class="hui-panel-body">
        {%if @panel == "checkbox"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Checkbox</div>
              <div class="hui-stage__content">
                <div
                  class="hui checkbox-wrap"
                  data-checked={if Map.get(@checks, "notifs") do "" end}
                  $click={:toggle_check, id: "notifs"}
                >
                  <div class="checkbox-visual"></div>
                  <span class="checkbox-label">Notifications</span>
                </div>
                <div
                  class="hui checkbox-wrap"
                  data-checked={if Map.get(@checks, "dark") do "" end}
                  $click={:toggle_check, id: "dark"}
                >
                  <div class="checkbox-visual"></div>
                  <span class="checkbox-label">Dark mode default</span>
                </div>
                <div
                  class="hui checkbox-wrap"
                  data-checked={if Map.get(@checks, "beta") do "" end}
                  $click={:toggle_check, id: "beta"}
                >
                  <div class="checkbox-visual"></div>
                  <span class="checkbox-label">Beta access</span>
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "switch"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Switch</div>
              <div class="hui-stage__content">
                <div
                  class="hui switch-wrap"
                  data-checked={if Map.get(@switches, "wifi") do "" end}
                  $click={:toggle_switch, id: "wifi"}
                >
                  <span class="switch-label">Wi-Fi</span>
                  <div class="switch-track"><div class="switch-thumb"></div></div>
                </div>
                <div
                  class="hui switch-wrap"
                  data-checked={if Map.get(@switches, "bt") do "" end}
                  $click={:toggle_switch, id: "bt"}
                >
                  <span class="switch-label">Bluetooth</span>
                  <div class="switch-track"><div class="switch-thumb"></div></div>
                </div>
                <div
                  class="hui switch-wrap"
                  data-checked={if Map.get(@switches, "vpn") do "" end}
                  $click={:toggle_switch, id: "vpn"}
                >
                  <span class="switch-label">VPN</span>
                  <div class="switch-track"><div class="switch-thumb"></div></div>
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "radio"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Radio Group</div>
              <div class="hui-stage__content">
                <div
                  class="hui radio-option"
                  data-checked={if @radio == "read" do "" end}
                  $click={:set_radio, value: "read"}
                >
                  <div class="radio-dot"><div class="radio-dot-inner"></div></div>
                  <span class="radio-label">Read only</span>
                </div>
                <div
                  class="hui radio-option"
                  data-checked={if @radio == "edit" do "" end}
                  $click={:set_radio, value: "edit"}
                >
                  <div class="radio-dot"><div class="radio-dot-inner"></div></div>
                  <span class="radio-label">Can edit</span>
                </div>
                <div
                  class="hui radio-option"
                  data-checked={if @radio == "admin" do "" end}
                  $click={:set_radio, value: "admin"}
                >
                  <div class="radio-dot"><div class="radio-dot-inner"></div></div>
                  <span class="radio-label">Admin</span>
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "tabs"}
          <div class="hui-stage">
            <div class="hui-stage__panel" style="grid-column: 1 / -1">
              <div class="hui-stage__label">Tabs</div>
              <div class="hui-stage__content">
                <div class="hui tab-list" role="tablist">
                  <button type="button" class="hui tab" data-selected={if @tab == "overview" do "" end} $click={:set_tab, id: "overview"}>Overview</button>
                  <button type="button" class="hui tab" data-selected={if @tab == "activity" do "" end} $click={:set_tab, id: "activity"}>Activity</button>
                  <button type="button" class="hui tab" data-selected={if @tab == "settings" do "" end} $click={:set_tab, id: "settings"}>Settings</button>
                </div>
                <div class="hui tab-panel">
                  {%if @tab == "overview"}Project summary and metrics.{/if}
                  {%if @tab == "activity"}Recent commits and deploys.{/if}
                  {%if @tab == "settings"}Repository configuration.{/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "disclosure"}
          <div class="hui-stage">
            <div class="hui-stage__panel" style="grid-column: 1 / -1">
              <div class="hui-stage__label">Disclosure</div>
              <div class="hui-stage__content">
                <div>
                  <button
                    type="button"
                    class="hui disclosure-btn"
                    data-open={if Map.get(@disc_open, "q1") do "" end}
                    $click={:toggle_disc, id: "q1"}
                  >
                    <span>What is included?</span>
                    <span class="disclosure-chevron">↓</span>
                  </button>
                  {%if Map.get(@disc_open, "q1")}
                    <div class="hui disclosure-panel">Full source code, documentation, and 12 months of updates.</div>
                  {/if}
                </div>
                <div>
                  <button
                    type="button"
                    class="hui disclosure-btn"
                    data-open={if Map.get(@disc_open, "q2") do "" end}
                    $click={:toggle_disc, id: "q2"}
                  >
                    <span>Refund policy?</span>
                    <span class="disclosure-chevron">↓</span>
                  </button>
                  {%if Map.get(@disc_open, "q2")}
                    <div class="hui disclosure-panel">30-day money-back guarantee, no questions asked.</div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "menu"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Dropdown Menu</div>
              <div class="hui-stage__content">
                <div class="hui-menu-host" style="position: relative; display: inline-block">
                  <button
                    type="button"
                    class="hui menu-btn"
                    data-open={if @menu_open do "" end}
                    $click={:toggle_menu}
                  >
                    Actions ▾
                  </button>
                  {%if @menu_open}
                    <div class="hui menu-items">
                      <div class="hui menu-item" $click={:close_menu}>Edit</div>
                      <div class="hui menu-item" $click={:close_menu}>Duplicate</div>
                      <div class="hui menu-sep"></div>
                      <div class="hui menu-item" $click={:close_menu}>Archive</div>
                      <div class="hui menu-item" data-disabled="">Delete</div>
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "listbox"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Listbox</div>
              <div class="hui-stage__content">
                <div class="hui listbox-wrap">
                  <button
                    type="button"
                    class="hui listbox-btn"
                    data-open={if @listbox_open do "" end}
                    $click={:toggle_listbox}
                  >
                    {@listbox_value}
                  </button>
                  {%if @listbox_open}
                    <div class="hui listbox-options">
                      <div class="hui listbox-option" data-selected={if @listbox_value == "Default" do "" end} $click={:pick_listbox, value: "Default"}>Default</div>
                      <div class="hui listbox-option" data-selected={if @listbox_value == "Comfortable" do "" end} $click={:pick_listbox, value: "Comfortable"}>Comfortable</div>
                      <div class="hui listbox-option" data-selected={if @listbox_value == "Compact" do "" end} $click={:pick_listbox, value: "Compact"}>Compact</div>
                      <div class="hui listbox-option" data-selected={if @listbox_value == "Cozy" do "" end} $click={:pick_listbox, value: "Cozy"}>Cozy</div>
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "combobox"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Combobox</div>
              <div class="hui-stage__content">
                <div class="hui combo-wrap">
                  <input
                    type="text"
                    class="hui combo-input"
                    value={@combo_value}
                    placeholder="Search people…"
                    $change={:combo_query}
                    $focus={:open_combo}
                  />
                  <button type="button" class="hui combo-btn" $click={:toggle_combo}>▾</button>
                  {%if @combo_open}
                    <div class="hui combo-options">
                      <div class="hui combo-option" data-selected={if @combo_value == "Alice Chen" do "" end} $click={:pick_combo, value: "Alice Chen"}>Alice Chen</div>
                      <div class="hui combo-option" data-selected={if @combo_value == "Bob Kim" do "" end} $click={:pick_combo, value: "Bob Kim"}>Bob Kim</div>
                      <div class="hui combo-option" data-selected={if @combo_value == "Carol Day" do "" end} $click={:pick_combo, value: "Carol Day"}>Carol Day</div>
                      <div class="hui combo-option" data-selected={if @combo_value == "Dave Park" do "" end} $click={:pick_combo, value: "Dave Park"}>Dave Park</div>
                      <div class="hui combo-option" data-selected={if @combo_value == "Eve Lam" do "" end} $click={:pick_combo, value: "Eve Lam"}>Eve Lam</div>
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "popover"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Popover</div>
              <div class="hui-stage__content">
                <div class="hui popover-wrap">
                  <button
                    type="button"
                    class="hui popover-btn"
                    data-open={if @popover_open do "" end}
                    $click={:toggle_popover}
                  >
                    More info
                  </button>
                  {%if @popover_open}
                    <div class="hui popover-panel">
                      <div style="font-weight: 600; margin-bottom: 0.35rem">Pro plan</div>
                      <div style="font-size: var(--font-size-sm); color: var(--text-muted); line-height: 1.5">
                        Includes unlimited projects, priority support, and team seats.
                      </div>
                    </div>
                  {/if}
                </div>
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "dialog"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Dialog</div>
              <div class="hui-stage__content">
                <button type="button" class="hui menu-btn" $click={:open_dialog}>Open Dialog</button>
                {%if @dialog_open}
                  <div class="hui dialog-backdrop" $click={:close_dialog}></div>
                  <div class="hui dialog-positioner">
                    <div class="hui dialog-panel">
                      <div class="hui dialog-title">Confirm action</div>
                      <div class="hui dialog-body">
                        This will permanently delete the selected items. This action cannot be undone.
                      </div>
                      <div class="hui dialog-actions">
                        <button type="button" class="btn btn-outline btn-sm" $click={:close_dialog}>Cancel</button>
                        <button type="button" class="btn btn-sm" style="background: var(--error); color: #fff; border: none; border-radius: var(--radius); padding: 0.35rem 0.75rem; cursor: pointer" $click={:close_dialog}>Delete</button>
                      </div>
                    </div>
                  </div>
                {/if}
              </div>
            </div>
          </div>
        {/if}

        {%if @panel == "fields"}
          <div class="hui-stage">
            <div class="hui-stage__panel">
              <div class="hui-stage__label">Fields</div>
              <div class="hui-stage__content">
                <div class="field-group">
                  <label class="field-label">Email address</label>
                  <input type="email" class="field-input" placeholder="you@example.com" />
                </div>
                <div class="field-group">
                  <label class="field-label">Region</label>
                  <select class="field-select">
                    <option>US East</option>
                    <option>US West</option>
                    <option>EU West</option>
                  </select>
                </div>
                <div class="field-group">
                  <label class="field-label">Description</label>
                  <textarea class="field-textarea" rows="3" placeholder="Write a short description…"></textarea>
                  <p class="field-hint">Max 280 characters</p>
                </div>
              </div>
            </div>
          </div>
        {/if}
      </div>
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:select_panel, params, component) do
    put_state(component, panel: params.id)
  end

  def action(:toggle_check, params, component) do
    id = params.id
    checks = component.state.checks
    put_state(component, checks: Map.put(checks, id, !Map.get(checks, id, false)))
  end

  def action(:toggle_switch, params, component) do
    id = params.id
    switches = component.state.switches
    put_state(component, switches: Map.put(switches, id, !Map.get(switches, id, false)))
  end

  def action(:set_radio, params, component), do: put_state(component, radio: params.value)
  def action(:set_tab, params, component), do: put_state(component, tab: params.id)

  def action(:toggle_disc, params, component) do
    id = params.id
    d = component.state.disc_open
    put_state(component, disc_open: Map.put(d, id, !Map.get(d, id, false)))
  end

  def action(:toggle_menu, _params, component),
    do: put_state(component, menu_open: !component.state.menu_open)

  def action(:close_menu, _params, component), do: put_state(component, menu_open: false)

  def action(:toggle_listbox, _params, component),
    do: put_state(component, listbox_open: !component.state.listbox_open)

  def action(:pick_listbox, params, component) do
    put_state(component, listbox_value: params.value, listbox_open: false)
  end

  def action(:toggle_combo, _params, component),
    do: put_state(component, combo_open: !component.state.combo_open)

  def action(:open_combo, _params, component), do: put_state(component, combo_open: true)

  def action(:combo_query, params, component) do
    put_state(component, combo_value: params.event.value || "", combo_open: true)
  end

  def action(:pick_combo, params, component) do
    put_state(component, combo_value: params.value, combo_open: false)
  end

  def action(:toggle_popover, _params, component),
    do: put_state(component, popover_open: !component.state.popover_open)

  def action(:open_dialog, _params, component), do: put_state(component, dialog_open: true)
  def action(:close_dialog, _params, component), do: put_state(component, dialog_open: false)
end
