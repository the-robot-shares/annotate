defmodule AnnotateWeb.Hologram.Pages.StyleGuidePage do
  @moduledoc """
  Interactive style guide viewer at `/styleguide`.

  Visual Foundation, Structure, Interaction (incl. HUI submenu), Component Browser,
  and Reference. Tailwind Plus full catalog at `/styleguide/tailwind-plus`.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias Annotate.StyleGuide.Catalog

  alias AnnotateWeb.Hologram.Components.{
    Card,
    CardGrid,
    InputField,
    SectionHeader,
    SpacingScale,
    StatusIndicator,
    TokenCard,
    TypeSpecimen
  }

  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Pages.HomePage
  alias AnnotateWeb.Hologram.Pages.TailwindPlusPage

  alias AnnotateWeb.Hologram.Sections.{
    ColorPalette,
    ComponentBrowser,
    HuiShowcase,
    ShellLayouts,
    YamlConfig
  }

  route "/styleguide"
  layout MainLayout, page_title: "Style Guide — Hologram"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    group_id = Catalog.first_group_id()
    section_id = Catalog.first_section_id()
    group = Catalog.find_group(group_id)
    section = Catalog.find_section(group_id, section_id)
    theme_slug = Hologram.Server.get_cookie(server, "sg-theme", "style-guide")

    put_state(component,
      groups: Catalog.groups(),
      group_id: group_id,
      section_id: section_id,
      group: group,
      section: section,
      brand: Catalog.brand(),
      theme_slug: theme_slug,
      # subsection tabs within Visual Foundation sections
      sub_tab: "fonts",
      # local demo feedback (nav tabs, form demos, button clicks)
      flash: nil,
      nav_tab: "overview",
      btn_last: nil,
      form_note: "",
      spacing_steps: spacing_steps(),
      surface_tokens: surface_tokens(),
      brand_tokens: brand_tokens(),
      semantic_tokens: semantic_tokens(),
      type_tokens: type_tokens(),
      glyphs_ui: glyphs_ui()
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content">
      <div class="sg-hero">
        <p class="twp-back">
          <Link to={HomePage} class="btn btn-outline btn-sm">← Home</Link>
        </p>
        <h1>{@brand.title}</h1>
        <p>{@brand.description}</p>
        <p style="font-size: var(--font-size-sm); color: var(--text-muted)">
          Design tokens from YAML · CSS from the styleguide engine · UI in Hologram
        </p>
      </div>

      <nav class="sg-group-nav" aria-label="Section groups">
        {%for g <- @groups}
          <button
            type="button"
            class="btn btn-outline btn-sm"
            data-selected={if g.id == @group_id do "" end}
            $click={:select_group, id: g.id}
          >
            {g.group}
          </button>
        {/for}
      </nav>

      <p style="color: var(--text-secondary); margin-bottom: var(--space-2)">{@group.desc}</p>

      <nav class="sg-section-nav hui tab-list" aria-label="Sections">
        {%for s <- @group.sections}
          <button
            type="button"
            class="hui tab"
            data-selected={if s.id == @section_id do "" end}
            $click={:select_section, id: s.id}
          >
            <span style="opacity: 0.45; margin-right: 0.25rem">{s.number}</span>
            {s.title}
          </button>
        {/for}
      </nav>

      <SectionHeader number={@section.number} title={@section.title} desc={@section.desc} />

      {%if @flash}
        <p class="sg-flash" role="status">{@flash}</p>
      {/if}

      <div class="sg-section-panel">
        {%if @section_id == "typography"}
          <nav class="sg-subtabs hui tab-list" aria-label="Typography subsections">
            <button type="button" class="hui tab" data-selected={if @sub_tab == "fonts" do "" end} $click={:set_sub_tab, id: "fonts"}>Fonts &amp; Usage</button>
            <button type="button" class="hui tab" data-selected={if @sub_tab == "scale" do "" end} $click={:set_sub_tab, id: "scale"}>Type Scale</button>
            <button type="button" class="hui tab" data-selected={if @sub_tab == "colors" do "" end} $click={:set_sub_tab, id: "colors"}>Text Colors</button>
            <button type="button" class="hui tab" data-selected={if @sub_tab == "classes" do "" end} $click={:set_sub_tab, id: "classes"}>Classes</button>
          </nav>
          {%if @sub_tab == "fonts"}
            <div class="demo-block">
              <TypeSpecimen name="Space Grotesk — Sans" font="var(--font-sans)" weight="700" size="var(--font-size-3xl)" line_height="1.15" sample="Design systems at seed scale." usage="Headings, UI labels, body" />
              <TypeSpecimen name="IBM Plex Mono" font="var(--font-mono)" weight="500" size="var(--font-size-sm)" line_height="1.5" sample="--brand-blue: var(--blue); --space-3: calc(var(--unit) * 3);" usage="Code, tokens, metadata" />
              <TypeSpecimen name="Body" font="var(--font-sans)" weight="400" size="var(--font-size-md)" line_height="1.6" sample="YAML seeds expand into hundreds of tokens. Components consume CSS variables — not hard-coded values." usage="Body copy" />
            </div>
          {/if}
          {%if @sub_tab == "scale"}
            <div class="demo-block type-scale">
              <div class="type-scale-row"><span class="type-scale-label">display</span><span class="typography-display" style="font-family: var(--font-sans); font-size: var(--font-size-display, 3rem); font-weight: 700; letter-spacing: -0.03em; line-height: 1.05">Display</span></div>
              <div class="type-scale-row"><span class="type-scale-label">h1 / 3xl</span><span style="font-family: var(--font-sans); font-size: var(--font-size-3xl); font-weight: 700; line-height: 1.1">Heading One</span></div>
              <div class="type-scale-row"><span class="type-scale-label">h2 / 2xl</span><span style="font-family: var(--font-sans); font-size: var(--font-size-2xl); font-weight: 700; line-height: 1.2">Heading Two</span></div>
              <div class="type-scale-row"><span class="type-scale-label">h3 / xl</span><span style="font-family: var(--font-sans); font-size: var(--font-size-xl); font-weight: 600; line-height: 1.3">Heading Three</span></div>
              <div class="type-scale-row"><span class="type-scale-label">h4 / lg</span><span style="font-family: var(--font-sans); font-size: var(--font-size-lg); font-weight: 600">Heading Four</span></div>
              <div class="type-scale-row"><span class="type-scale-label">md</span><span style="font-family: var(--font-sans); font-size: var(--font-size-md)">Body medium</span></div>
              <div class="type-scale-row"><span class="type-scale-label">sm</span><span style="font-family: var(--font-sans); font-size: var(--font-size-sm); color: var(--text-secondary)">Body small / secondary</span></div>
              <div class="type-scale-row"><span class="type-scale-label">xs</span><span style="font-family: var(--font-mono); font-size: var(--font-size-xs); color: var(--text-muted)">Micro label / mono</span></div>
            </div>
          {/if}
          {%if @sub_tab == "colors"}
            <div class="demo-block">
              <p style="color: var(--text)">Primary text — <code>--text</code></p>
              <p style="color: var(--text-secondary)">Secondary text — <code>--text-secondary</code></p>
              <p style="color: var(--text-muted)">Muted text — <code>--text-muted</code></p>
              <p style="background: var(--surface-inverse); color: var(--text-inverse); padding: var(--space-2); border-radius: var(--radius)">Inverse text on inverse surface</p>
              <p style="color: var(--brand-blue); margin-top: var(--space-2)">Brand blue link / accent text</p>
              <p style="color: var(--error)">Error / destructive text</p>
            </div>
          {/if}
          {%if @sub_tab == "classes"}
            <div class="demo-block">
              <TokenCard title="Typography classes" tokens={@type_tokens} />
              <p class="sg-page-intro" style="color: var(--text-muted); margin-top: var(--space-2)">
                Classes map to CSS custom properties generated from <code>typography.yaml</code>.
              </p>
            </div>
          {/if}
        {/if}

        <!-- Full YAML color palette (always mounted for SSR init) -->
        <div class={if @section_id == "color" do "sg-section-active" else "sg-section-hidden" end}>
          <ColorPalette cid="color_palette" theme_slug={@theme_slug} />
        </div>

        {%if @section_id == "spacing"}
          <nav class="sg-subtabs hui tab-list" aria-label="Spacing subsections">
            <button type="button" class="hui tab" data-selected={if @sub_tab == "scale" do "" end} $click={:set_sub_tab, id: "scale"}>Scale</button>
            <button type="button" class="hui tab" data-selected={if @sub_tab == "grid" do "" end} $click={:set_sub_tab, id: "grid"}>12-Col Grid</button>
            <button type="button" class="hui tab" data-selected={if @sub_tab == "principles" do "" end} $click={:set_sub_tab, id: "principles"}>Principles</button>
          </nav>
          {%if @sub_tab == "scale"}
            <div class="demo-block">
              <SpacingScale steps={@spacing_steps} />
            </div>
          {/if}
          {%if @sub_tab == "grid"}
            <div class="demo-block">
              <div class="grid-visual" aria-hidden="true">
                <div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div>
                <div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div>
                <div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div><div class="grid-visual__col"></div>
              </div>
              <p style="color: var(--text-muted); font-size: var(--font-size-sm); margin-top: var(--space-2)">
                12-column grid with gutters from <code>--space-2</code> / theme spacing context.
              </p>
            </div>
          {/if}
          {%if @sub_tab == "principles"}
            <div class="demo-block">
              <CardGrid>
                <Card title="Unit scale" body="Spacing steps are multiples of a base unit so rhythm stays consistent across components." />
                <Card title="Stack vs inline" body="Vertical stacks use the scale; horizontal groups use tighter steps (space-1 / space-2)." />
                <Card title="Content width" body="Page content max-width and padding are tokenized — avoid one-off pixel margins." />
              </CardGrid>
            </div>
          {/if}
        {/if}

        {%if @section_id == "dividers"}
          <div class="demo-block dividers-demo">
            <p class="divider-label">Simple rule</p>
            <hr class="sg-divider" />
            <p class="divider-label">Labeled</p>
            <div class="sg-divider-labeled">
              <span class="sg-divider-line"></span>
              <span class="sg-divider-text">Continue</span>
              <span class="sg-divider-line"></span>
            </div>
            <p class="divider-label">Brand accent</p>
            <div class="sg-divider-brand"></div>
            <p class="divider-label">With action</p>
            <div class="sg-divider-action">
              <span class="sg-divider-line"></span>
              <button type="button" class="btn btn-outline btn-sm" $click={:demo_ping, msg: "Section added (demo)"}>
                + Add section
              </button>
              <span class="sg-divider-line"></span>
            </div>
          </div>
        {/if}

        {%if @section_id == "glyphs"}
          <div class="demo-block">
            <p class="sg-page-intro" style="color: var(--text-secondary); margin-bottom: var(--space-3)">
              Unicode glyphs are the primary symbol language — no icon fonts. Same glyph for the same action everywhere.
            </p>
            <div class="glyph-grid">
              {%for g <- @glyphs_ui}
                <div class="glyph-card">
                  <div class="glyph-card__glyph" aria-hidden="true">{g.glyph}</div>
                  <div class="glyph-card__name">{g.name}</div>
                  <code class="glyph-card__code">{g.code}</code>
                  <div class="glyph-card__use">{g.use}</div>
                  <div class="glyph-card__example">{g.example}</div>
                </div>
              {/for}
            </div>
          </div>
        {/if}

        <div class={if @section_id == "shell-layouts" do "sg-section-active" else "sg-section-hidden" end}>
          <ShellLayouts cid="shell_layouts" theme_slug={@theme_slug} />
        </div>

        {%if @section_id == "content-layouts"}
          <div class="demo-block content-layout-demos">
            <div class="content-layout-demo">
              <span class="content-layout-demo__label">Standard · max-w container</span>
              <div class="content-layout-demo__frame content-layout-demo__frame--standard"><div class="content-layout-demo__inner">Content</div></div>
            </div>
            <div class="content-layout-demo">
              <span class="content-layout-demo__label">Narrow · article</span>
              <div class="content-layout-demo__frame content-layout-demo__frame--narrow"><div class="content-layout-demo__inner">Article column</div></div>
            </div>
            <div class="content-layout-demo">
              <span class="content-layout-demo__label">Wide · dashboard</span>
              <div class="content-layout-demo__frame content-layout-demo__frame--wide"><div class="content-layout-demo__inner">Wide content</div></div>
            </div>
          </div>
        {/if}

        {%if @section_id == "navigation"}
          <div class="demo-block">
            <h3>Tabs</h3>
            <div class="hui tab-list" style="margin-bottom: var(--space-2)">
              <button type="button" class="hui tab" data-selected={if @nav_tab == "overview" do "" end} $click={:set_nav_tab, id: "overview"}>Overview</button>
              <button type="button" class="hui tab" data-selected={if @nav_tab == "activity" do "" end} $click={:set_nav_tab, id: "activity"}>Activity</button>
              <button type="button" class="hui tab" data-selected={if @nav_tab == "settings" do "" end} $click={:set_nav_tab, id: "settings"}>Settings</button>
            </div>
            <div class="hui tab-panel" style="margin-bottom: var(--space-4)">
              {%if @nav_tab == "overview"}Project summary and metrics.{/if}
              {%if @nav_tab == "activity"}Recent commits and deploys.{/if}
              {%if @nav_tab == "settings"}Repository configuration.{/if}
            </div>
            <h3>Breadcrumbs</h3>
            <nav class="sg-breadcrumbs" aria-label="Breadcrumb">
              <button type="button" class="sg-breadcrumb-btn" $click={:goto, group: "visual-foundation", section: "typography"}>Projects</button>
              <span aria-hidden="true">›</span>
              <button type="button" class="sg-breadcrumb-btn" $click={:goto, group: "interaction", section: "buttons"}>Nero</button>
              <span aria-hidden="true">›</span>
              <span aria-current="page">Settings</span>
            </nav>
            <p style="color: var(--text-muted); font-size: var(--font-size-sm); margin-top: var(--space-3)">
              Full widget variants:
              <button type="button" class="btn btn-outline btn-sm" $click={:goto, group: "reference", section: "tailwind-plus"}>Open Tailwind Plus section</button>
              or
              <a href="/styleguide/tailwind-plus" class="btn btn-black btn-sm">Full browser</a>
            </p>
          </div>
        {/if}

        {%if @section_id == "buttons"}
          <div class="demo-block">
            <p class="app-muted" style="margin-bottom: var(--space-2)">
              Click a button to confirm handlers work.
              {%if @btn_last} Last click: <strong>{@btn_last}</strong>{/if}
            </p>
            <h3>Variants</h3>
            <div class="btn-row-demo">
              <button type="button" class="btn btn-black" $click={:demo_btn, label: "Black"}>Black</button>
              <button type="button" class="btn btn-outline" $click={:demo_btn, label: "Outline"}>Outline</button>
              <button type="button" class="btn btn-ghost" $click={:demo_btn, label: "Ghost"}>Ghost</button>
            </div>
            <h3>Sizes</h3>
            <div class="btn-row-demo">
              <button type="button" class="btn btn-black btn-sm" $click={:demo_btn, label: "Small"}>Small</button>
              <button type="button" class="btn btn-black" $click={:demo_btn, label: "Default"}>Default</button>
              <button type="button" class="btn btn-black btn-lg" $click={:demo_btn, label: "Large"}>Large</button>
            </div>
            <h3>States</h3>
            <div class="btn-row-demo">
              <button type="button" class="btn btn-black" $click={:demo_btn, label: "Enabled"}>Enabled</button>
              <button type="button" class="btn btn-black" disabled>Disabled</button>
              <button type="button" class="btn btn-outline" disabled>Outline disabled</button>
            </div>
          </div>
        {/if}

        {%if @section_id == "cards"}
          <div class="demo-block">
            <p class="app-muted" style="margin-bottom: var(--space-2)">Cards with actions open related sections.</p>
            <div class="card-grid-actions">
              <button type="button" class="card card--link card--action" $click={:goto, group: "interaction", section: "forms"}>
                <div class="card-id">A</div>
                <div class="card-title">Accounts</div>
                <div class="card-body">Email/password, SSO, invites — open Forms section.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "interaction", section: "hui"}>
                <div class="card-id">B</div>
                <div class="card-title">Isomorphic UI</div>
                <div class="card-body">Hologram actions in the browser — open HUI Controls.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "reference", section: "tokens"}>
                <div class="card-id">C</div>
                <div class="card-title">YAML seeds</div>
                <div class="card-body">Facet YAML → tokens — open Design Tokens.</div>
              </button>
            </div>
          </div>
        {/if}

        {%if @section_id == "forms"}
          <div class="demo-block" style="max-width: 28rem">
            <InputField id="demo-email" label="Email" type="email" placeholder="you@example.com" />
            <InputField id="demo-name" label="Name" type="text" placeholder="Ada Lovelace" />
            <div class="field-group" style="margin-bottom: var(--space-2)">
              <label class="field-label">Region</label>
              <select class="field-select">
                <option>US East</option>
                <option>EU West</option>
                <option>AP South</option>
              </select>
            </div>
            <div class="field-group" style="margin-bottom: var(--space-3)">
              <label class="field-label">Notes</label>
              <textarea class="field-textarea" rows="3" placeholder="Optional notes…" $change={:set_form_note}></textarea>
            </div>
            <div class="btn-row-demo">
              <button type="button" class="btn btn-black" $click={:demo_form_submit}>Submit</button>
              <button type="button" class="btn btn-outline" $click={:demo_form_cancel}>Cancel</button>
            </div>
          </div>
        {/if}

        {%if @section_id == "status"}
          <div class="demo-block status-grid-demo">
            <StatusIndicator status="success" label="Success" desc="Completed" />
            <StatusIndicator status="warning" label="Warning" desc="Needs attention" />
            <StatusIndicator status="error" label="Error" desc="Failed" />
            <StatusIndicator status="info" label="Info" desc="Neutral update" />
          </div>
          <div class="demo-block" style="margin-top: var(--space-4)">
            <h3>Inline badges</h3>
            <div class="badge-row">
              <span class="sg-badge sg-badge--success">Active</span>
              <span class="sg-badge sg-badge--warning">Pending</span>
              <span class="sg-badge sg-badge--error">Blocked</span>
              <span class="sg-badge sg-badge--info">Draft</span>
              <span class="sg-badge">Default</span>
            </div>
          </div>
        {/if}

        <!-- Always mounted (with cid) so SSR init runs; toggled via display -->
        <div class={if @section_id == "hui" do "sg-section-active" else "sg-section-hidden" end}>
          <HuiShowcase cid="hui_showcase" />
        </div>

        <div class={if @section_id == "components" do "sg-section-active" else "sg-section-hidden" end}>
          <ComponentBrowser cid="component_browser" />
        </div>

        {%if @section_id == "tokens"}
          <div class="demo-block">
            <TokenCard title="Surfaces" tokens={@surface_tokens} />
            <TokenCard title="Brand" tokens={@brand_tokens} />
            <TokenCard title="Semantic" tokens={@semantic_tokens} />
            <TokenCard title="Typography classes" tokens={@type_tokens} />
            <p class="app-muted" style="margin-top: var(--space-3)">
              Full color swatches:
              <button type="button" class="btn btn-outline btn-sm" $click={:goto, group: "visual-foundation", section: "color"}>Open Color</button>
              · Edit YAML:
              <button type="button" class="btn btn-outline btn-sm" $click={:goto, group: "reference", section: "theme-config"}>Theme Config</button>
            </p>
          </div>
        {/if}

        <div class={if @section_id == "theme-config" do "sg-section-active" else "sg-section-hidden" end}>
          <YamlConfig cid="yaml_config" theme_slug={@theme_slug} />
        </div>

        {%if @section_id == "migration"}
          <div class="demo-block">
            <p class="app-muted" style="margin-bottom: var(--space-2)">Click a card to jump to the related section or open the catalog.</p>
            <div class="card-grid-actions">
              <button type="button" class="card card--link card--action" $click={:goto, group: "visual-foundation", section: "typography"}>
                <div class="card-title">Viewer</div>
                <div class="card-body">Elixir + Hologram only — no TypeScript runtime. Open Visual Foundation.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "reference", section: "tokens"}>
                <div class="card-title">Theme CSS</div>
                <div class="card-body">priv/static/themes/*.css — open Design Tokens.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "reference", section: "theme-config"}>
                <div class="card-title">Theme Config</div>
                <div class="card-body">Browse / edit YAML facets and save named variants.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "visual-foundation", section: "color"}>
                <div class="card-title">Full color palette</div>
                <div class="card-body">All swatches from color-palette.yaml (76+ tokens).</div>
              </button>
              <a href="/styleguide/tailwind-plus" class="card card--link">
                <div class="card-title">Tailwind Plus</div>
                <div class="card-body">686 static HTML demos — open full browser.</div>
              </a>
              <button type="button" class="card card--link card--action" $click={:goto, group: "interaction", section: "hui"}>
                <div class="card-title">HUI</div>
                <div class="card-body">Theme .hui classes + Hologram actions — open HUI Controls.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:goto, group: "component-library", section: "components"}>
                <div class="card-title">Component Browser</div>
                <div class="card-body">Live previews of exported primitives — open Component Library.</div>
              </button>
              <button type="button" class="card card--link card--action" $click={:demo_ping, msg: "Consumer: components/hologram-start-app (AnnotateWeb.Hologram.Components)"}>
                <div class="card-title">Consumer apps</div>
                <div class="card-body">hologram-start-app vendors primitives — click for path note.</div>
              </button>
            </div>
            <div class="legacy-note">
              This package does not depend on <code>components/styleguide/app</code> (Next/TS). That tree is optional historical tooling for npm consumers only.
            </div>
          </div>
        {/if}

        {%if @section_id == "tailwind-plus"}
          <div class="demo-block">
            <p class="sg-page-intro" style="color: var(--text-secondary); margin-bottom: var(--space-3)">
              686 static HTML widget previews (no TypeScript). Open the browser for section/group
              navigation and demos at /styleguide/tailwind-plus.
            </p>
            <div class="btn-row-demo" style="margin-bottom: var(--space-3); display: flex; flex-wrap: wrap; gap: 0.5rem">
              <a href="/styleguide/tailwind-plus" class="btn btn-black">Open Tailwind Plus browser</a>
              <Link to={TailwindPlusPage} class="btn btn-outline">Open (client nav)</Link>
            </div>
            <div class="twp-quick-links">
              <a href="/styleguide/tailwind-plus" class="card twp-quick-link">
                <div class="card-title">Elements</div>
                <div class="card-body">Avatars, badges, buttons, dropdowns</div>
              </a>
              <a href="/styleguide/tailwind-plus" class="card twp-quick-link">
                <div class="card-title">Forms</div>
                <div class="card-body">Inputs, selects, toggles, sign-in</div>
              </a>
              <a href="/styleguide/tailwind-plus" class="card twp-quick-link">
                <div class="card-title">Marketing</div>
                <div class="card-body">Heroes, pricing, CTAs, footers</div>
              </a>
              <a href="/styleguide/tailwind-plus" class="card twp-quick-link">
                <div class="card-title">Ecommerce</div>
                <div class="card-body">Product lists, carts, checkout</div>
              </a>
            </div>
          </div>
        {/if}
      </div>
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:select_group, params, component) do
    group = Catalog.find_group(params.id)
    section = List.first(group.sections)
    sub = default_sub_tab(section.id)

    put_state(component,
      group_id: group.id,
      group: group,
      section_id: section.id,
      section: section,
      sub_tab: sub,
      flash: nil
    )
  end

  def action(:select_section, params, component) do
    section = Catalog.find_section(component.state.group_id, params.id)

    put_state(component,
      section_id: section.id,
      section: section,
      sub_tab: default_sub_tab(section.id),
      flash: nil
    )
  end

  def action(:set_sub_tab, params, component) do
    put_state(component, sub_tab: params.id, flash: nil)
  end

  # Jump to any catalog group + section (migration cards, breadcrumbs, etc.)
  def action(:goto, params, component) do
    group = Catalog.find_group(params.group)
    section = Catalog.find_section(group.id, params.section)

    put_state(component,
      group_id: group.id,
      group: group,
      section_id: section.id,
      section: section,
      sub_tab: default_sub_tab(section.id),
      flash: nil
    )
  end

  def action(:demo_ping, params, component) do
    put_state(component, flash: params.msg || "OK")
  end

  def action(:demo_btn, params, component) do
    label = params.label || "button"
    put_state(component, btn_last: label, flash: "Clicked #{label}")
  end

  def action(:set_nav_tab, params, component) do
    put_state(component, nav_tab: params.id, flash: nil)
  end

  def action(:set_form_note, params, component) do
    put_state(component, form_note: params.event.value || "")
  end

  def action(:demo_form_submit, _params, component) do
    note = component.state.form_note || ""
    msg = if note == "", do: "Form submitted (demo).", else: "Submitted with notes: #{note}"
    put_state(component, flash: msg)
  end

  def action(:demo_form_cancel, _params, component) do
    put_state(component, flash: "Cancelled (demo).", form_note: "")
  end

  defp default_sub_tab("typography"), do: "fonts"
  defp default_sub_tab("color"), do: "palette"
  defp default_sub_tab("spacing"), do: "scale"
  defp default_sub_tab(_), do: "fonts"

  defp spacing_steps do
    [
      %{label: "space-1", width: "8px"},
      %{label: "space-2", width: "16px"},
      %{label: "space-3", width: "24px"},
      %{label: "space-4", width: "32px"},
      %{label: "space-5", width: "48px"},
      %{label: "space-6", width: "64px"},
      %{label: "space-8", width: "96px"}
    ]
  end

  defp surface_tokens do
    [
      %{name: "--surface", value: "var(--white)"},
      %{name: "--surface-alt", value: "var(--gray-50)"},
      %{name: "--surface-inverse", value: "var(--gray-900)"},
      %{name: "--text", value: "var(--gray-900)"},
      %{name: "--text-secondary", value: "var(--gray-600)"},
      %{name: "--border", value: "var(--gray-200)"}
    ]
  end

  defp brand_tokens do
    [
      %{name: "--brand-red", value: "seed"},
      %{name: "--brand-blue", value: "seed"},
      %{name: "--brand-yellow", value: "seed"},
      %{name: "--radius", value: "seed"}
    ]
  end

  defp semantic_tokens do
    [
      %{name: "--success", value: "semantic"},
      %{name: "--warning", value: "semantic"},
      %{name: "--error", value: "semantic"},
      %{name: "--info", value: "semantic"}
    ]
  end

  defp type_tokens do
    [
      %{name: ".typography-display", value: "font-size-display / 700"},
      %{name: ".typography-h1", value: "font-size-3xl / 700"},
      %{name: ".typography-h2", value: "font-size-2xl / 700"},
      %{name: ".typography-h3", value: "font-size-xl / 600"},
      %{name: ".typography-h4", value: "font-size-lg / 600"}
    ]
  end

  defp glyphs_ui do
    [
      %{
        glyph: "≡",
        name: "Hamburger",
        code: "U+2261",
        use: "Mobile nav toggle",
        example: "≡ Menu"
      },
      %{glyph: "⋮", name: "Kebab", code: "U+22EE", use: "More options", example: "⋮"},
      %{glyph: "⋯", name: "Overflow", code: "U+22EF", use: "Truncation", example: "Files ⋯"},
      %{glyph: "✕", name: "Close", code: "U+2715", use: "Dismiss / clear", example: "✕ Close"},
      %{glyph: "←", name: "Back", code: "U+2190", use: "Back navigation", example: "← Back"},
      %{glyph: "→", name: "Forward", code: "U+2192", use: "CTA / next", example: "Continue →"},
      %{glyph: "↑", name: "Up", code: "U+2191", use: "Scroll top", example: "↑ Top"},
      %{glyph: "↓", name: "Down", code: "U+2193", use: "Expand", example: "Show more ↓"},
      %{glyph: "↗", name: "External", code: "U+2197", use: "External link", example: "Docs ↗"},
      %{
        glyph: "›",
        name: "Chevron",
        code: "U+203A",
        use: "Breadcrumb",
        example: "Home › Settings"
      },
      %{glyph: "✓", name: "Check", code: "U+2713", use: "Success / selected", example: "✓ Done"},
      %{glyph: "●", name: "Bullet", code: "U+25CF", use: "Status dot", example: "● Live"}
    ]
  end
end
