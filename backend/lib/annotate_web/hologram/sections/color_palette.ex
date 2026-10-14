defmodule AnnotateWeb.Hologram.Sections.ColorPalette do
  @moduledoc """
  Full YAML color palette + semantic class swatches.

  Loads groups from `style-guide.color-palette.yaml` and
  `style-guide.semantic-classes.yaml` for the active theme.
  """
  use Hologram.Component

  alias Annotate.StyleGuide.ThemeData

  prop :theme_slug, :string, default: "style-guide"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(props, component, _server), do: do_init(props, component)
  def init(props, component), do: do_init(props, component)

  defp do_init(props, component) do
    slug = Map.get(props, :theme_slug, "style-guide") || "style-guide"
    put_state(component, palette_state(slug))
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-color-palette">
      <nav class="sg-subtabs hui tab-list" aria-label="Color subsections">
        <button type="button" class="hui tab" data-selected={if @tab == "palette" do "" end} $click={:set_tab, id: "palette"}>
          Palette ({@palette_count})
        </button>
        <button type="button" class="hui tab" data-selected={if @tab == "semantic" do "" end} $click={:set_tab, id: "semantic"}>
          Semantic Colors ({@semantic_count})
        </button>
      </nav>

      <p class="sg-page-intro app-muted" style="font-size: var(--font-size-sm); margin: var(--space-2) 0 var(--space-3)">
        Full swatch set from theme YAML · <code>{@theme_slug}</code>
        · <code>style-guide.color-palette.yaml</code>
        {%if @tab == "semantic"} + <code>semantic-classes.yaml</code>{/if}
        · after changing theme in the header, refresh to reload group structure
      </p>

      {%if @tab == "palette"}
        {%for g <- @palette}
          <div class="sg-palette-group">
            <button type="button" class="sg-palette-group-toggle" $click={:toggle_group, id: g.id, which: "palette"}>
              <h3 class="sg-subsection-title">{g.group}</h3>
              <span class="sg-palette-count">{g.color_count}</span>
              <span class="sg-palette-chevron" data-open={if g.open do "" end}>›</span>
            </button>
            {%if g.description != ""}
              <p class="sg-description">{g.description}</p>
            {/if}
            {%if g.open}
              <div class="sg-palette-grid">
                {%for c <- g.colors}
                  <div class="sg-palette-swatch">
                    <div class="sg-palette-swatch-inner" style={"background: #{c.value}"}>
                      <span class="sg-palette-swatch-label">{c.name}</span>
                      <span class="sg-palette-swatch-value">{c.value}</span>
                    </div>
                  </div>
                {/for}
              </div>
              {%if g.has_notes}
                <div class="sg-palette-notes">
                  {%for n <- g.notes}
                    <div class="sg-palette-note">
                      <span class="sg-palette-note-dot" style={"background: #{n.swatch}"}></span>
                      <strong>{n.label}</strong>
                      <span>— {n.text}</span>
                    </div>
                  {/for}
                </div>
              {/if}
            {/if}
          </div>
        {/for}
        {%if @palette_empty}
          <p class="app-muted">No color-palette.yaml found for this theme.</p>
        {/if}
      {/if}

      {%if @tab == "semantic"}
        {%for g <- @semantic}
          <div class="sg-palette-group">
            <button type="button" class="sg-palette-group-toggle" $click={:toggle_group, id: g.id, which: "semantic"}>
              <h3 class="sg-subsection-title">{g.group}</h3>
              <span class="sg-palette-count">{g.color_count}</span>
              <span class="sg-palette-chevron" data-open={if g.open do "" end}>›</span>
            </button>
            {%if g.description != ""}
              <p class="sg-description">{g.description}</p>
            {/if}
            {%if g.open}
              <div class="sg-palette-grid">
                {%for c <- g.colors}
                  <div class="sg-palette-swatch">
                    <div class="sg-palette-swatch-inner" style={"background: #{c.value}"}>
                      <span class="sg-palette-swatch-label">{c.name}</span>
                      <span class="sg-palette-swatch-value">{c.value}</span>
                    </div>
                  </div>
                {/for}
              </div>
              {%if g.has_notes}
                <div class="sg-palette-notes">
                  {%for n <- g.notes}
                    <div class="sg-palette-note">
                      <span class="sg-palette-note-dot" style={"background: #{n.swatch}"}></span>
                      <strong>{n.label}</strong>
                      <span>— {n.text}</span>
                    </div>
                  {/for}
                </div>
              {/if}
            {/if}
          </div>
        {/for}
        {%if @semantic_empty}
          <p class="app-muted">No semantic-classes.yaml found for this theme.</p>
        {/if}
      {/if}
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_tab, params, component) do
    put_state(component, tab: params.id)
  end

  def action(:toggle_group, params, component) do
    id = params.id
    which = params.which || "palette"

    case which do
      "semantic" ->
        put_state(component, semantic: toggle_open(component.state.semantic, id))

      _ ->
        put_state(component, palette: toggle_open(component.state.palette, id))
    end
  end

  defp toggle_open(groups, id) do
    Enum.map(groups, fn g ->
      if g.id == id, do: %{g | open: !g.open}, else: g
    end)
  end

  defp palette_state(slug) do
    palette =
      slug
      |> ThemeData.color_palette()
      |> Enum.map(&with_ui_flags/1)

    semantic =
      slug
      |> ThemeData.semantic_color_groups()
      |> Enum.map(&with_ui_flags/1)

    [
      theme_slug: slug,
      tab: "palette",
      palette: palette,
      semantic: semantic,
      palette_count: Enum.reduce(palette, 0, fn g, acc -> acc + g.color_count end),
      semantic_count: Enum.reduce(semantic, 0, fn g, acc -> acc + g.color_count end),
      palette_empty: palette == [],
      semantic_empty: semantic == []
    ]
  end

  defp with_ui_flags(g) do
    g
    |> Map.put(:open, true)
    |> Map.put(:color_count, length(g.colors))
    |> Map.put(:has_notes, g.notes != [])
  end
end
