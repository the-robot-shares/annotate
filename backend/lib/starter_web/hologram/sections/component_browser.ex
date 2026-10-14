defmodule StarterWeb.Hologram.Sections.ComponentBrowser do
  @moduledoc """
  Interactive Component Browser — category sidebar + entry list + live preview.
  Mirrors the source ComponentBrowser navigation pattern (without React).
  """
  use Hologram.Component

  alias Starter.StyleGuide.ComponentCatalog

  alias StarterWeb.Hologram.Components.{
    Btn,
    ButtonRow,
    Card,
    CardGrid,
    ColorGrid,
    ColorSwatch,
    InputField,
    SectionHeader,
    SpacingScale,
    StatusIndicator,
    StyleCard,
    TokenCard,
    TypeSpecimen
  }

  # SSR (if Component Library is the initial section)
  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(props, component, _server), do: do_init(props, component)

  # Client mount when navigating to this section after first paint
  def init(props, component), do: do_init(props, component)

  defp do_init(_props, component) do
    cat = ComponentCatalog.first_category()
    entry = List.first(cat.entries)

    put_state(component,
      categories: ComponentCatalog.categories(),
      category_slug: cat.slug,
      category: cat,
      entry_id: entry.id,
      entry: entry,
      search: "",
      entries: cat.entries,
      spacing_steps: [
        %{label: "space-1", width: "8px"},
        %{label: "space-2", width: "16px"},
        %{label: "space-3", width: "24px"},
        %{label: "space-4", width: "32px"},
        %{label: "space-6", width: "48px"}
      ],
      sample_tokens: [
        %{name: "--surface", value: "var(--white)"},
        %{name: "--brand-blue", value: "var(--blue)"},
        %{name: "--radius", value: "seed"}
      ]
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="cb-browser">
      <aside class="cb-sidebar" aria-label="Component categories">
        <input
          type="search"
          class="cb-search"
          placeholder="Filter components…"
          value={@search}
          $change={:update_search}
        />
        <nav class="cb-cat-list" aria-label="Categories">
          {%for c <- @categories}
            <button
              type="button"
              class="cb-cat-btn"
              data-selected={if c.slug == @category_slug do "" end}
              $click={:select_category, slug: c.slug}
            >
              <span class="cb-cat-btn__label">{c.label}</span>
              <span class="cb-cat-btn__count">{c.count}</span>
            </button>
          {/for}
        </nav>
        <nav class="cb-entry-list" aria-label="Components">
          {%for e <- @entries}
            <button
              type="button"
              class="cb-entry-btn"
              data-selected={if e.id == @entry_id do "" end}
              $click={:select_entry, id: e.id}
            >
              {e.name}
            </button>
          {/for}
        </nav>
      </aside>

      <section class="cb-main">
        {%if @entry}
          <header class="cb-preview-meta">
            <h3 class="cb-preview-title">{@entry.name}</h3>
            <code class="cb-preview-module">{@entry.module}</code>
            <p class="cb-preview-desc">{@entry.description}</p>
          </header>

          <div class="cb-preview-stage demo-block">
            {%if @entry_id == "btn"}
              <ButtonRow class="btn-row-demo">
                <Btn variant="black" label="Default" />
                <Btn variant="black" size="sm" label="Small" />
                <Btn variant="black" size="lg" label="Large" />
                <Btn variant="outline" label="Outline" />
                <Btn variant="ghost" label="Ghost" />
              </ButtonRow>
            {/if}

            {%if @entry_id == "button-row"}
              <ButtonRow>
                <Btn variant="black" label="Primary" />
                <Btn variant="outline" label="Secondary" />
              </ButtonRow>
            {/if}

            {%if @entry_id == "card"}
              <Card title="Example Card" body="Card with title, body, and design-system chrome." id_label="01" />
            {/if}

            {%if @entry_id == "card-grid"}
              <CardGrid>
                <Card title="Card 1" body="First card in the grid." />
                <Card title="Card 2" body="Second card in the grid." />
                <Card title="Card 3" body="Third card in the grid." />
              </CardGrid>
            {/if}

            {%if @entry_id == "section-header"}
              <SectionHeader number="01" title="Example Section" desc="Numbered header with description." />
            {/if}

            {%if @entry_id == "type-specimen"}
              <TypeSpecimen name="Display" font="var(--font-sans)" weight="700" size="var(--font-size-3xl)" line_height="1.15" sample="Design systems at seed scale." usage="Hero titles" />
              <TypeSpecimen name="Body" font="var(--font-sans)" weight="400" size="var(--font-size-md)" line_height="1.6" sample="Components consume CSS variables — not hard-coded values." usage="Body copy" />
            {/if}

            {%if @entry_id == "color-swatch"}
              <ColorGrid>
                <ColorSwatch name="Brand Blue" hex="var(--brand-blue)" inline={true} />
                <ColorSwatch name="Brand Red" hex="var(--brand-red)" inline={true} />
                <ColorSwatch name="Surface" hex="var(--surface)" />
              </ColorGrid>
            {/if}

            {%if @entry_id == "color-grid"}
              <ColorGrid>
                <ColorSwatch name="Success" hex="var(--success)" />
                <ColorSwatch name="Warning" hex="var(--warning)" />
                <ColorSwatch name="Error" hex="var(--error)" />
                <ColorSwatch name="Info" hex="var(--info)" />
              </ColorGrid>
            {/if}

            {%if @entry_id == "spacing-scale"}
              <SpacingScale steps={@spacing_steps} />
            {/if}

            {%if @entry_id == "status-indicator"}
              <div class="status-grid-demo">
                <StatusIndicator status="success" label="Success" desc="Completed" />
                <StatusIndicator status="warning" label="Warning" desc="Needs attention" />
                <StatusIndicator status="error" label="Error" desc="Failed" />
                <StatusIndicator status="info" label="Info" desc="Neutral" />
              </div>
            {/if}

            {%if @entry_id == "token-card"}
              <TokenCard title="Sample tokens" tokens={@sample_tokens} />
            {/if}

            {%if @entry_id == "input-field"}
              <div style="max-width: 20rem">
                <InputField id="cb-email" label="Email" type="email" placeholder="you@example.com" />
                <InputField id="cb-name" label="Name" type="text" placeholder="Ada Lovelace" />
              </div>
            {/if}

            {%if @entry_id == "style-card"}
              <StyleCard title="Style note" body="Use semantic tokens for all surface and text colors." />
            {/if}

            {%if @entry_id == "hui-checkbox"}
              <div class="hui checkbox-wrap" data-checked="">
                <div class="checkbox-visual"></div>
                <span class="checkbox-label">Checked example</span>
              </div>
              <div class="hui checkbox-wrap" style="margin-top: 0.5rem">
                <div class="checkbox-visual"></div>
                <span class="checkbox-label">Unchecked example</span>
              </div>
              <p class="cb-hint">Full interactive suite: Interaction → HUI Controls → Checkbox</p>
            {/if}

            {%if @entry_id == "hui-switch"}
              <div class="hui switch-wrap" data-checked="">
                <span class="switch-label">Enabled</span>
                <div class="switch-track"><div class="switch-thumb"></div></div>
              </div>
              <p class="cb-hint">Full interactive suite: Interaction → HUI Controls → Switch</p>
            {/if}

            {%if @entry_id == "hui-tabs"}
              <div class="hui tab-list">
                <button type="button" class="hui tab" data-selected="">One</button>
                <button type="button" class="hui tab">Two</button>
                <button type="button" class="hui tab">Three</button>
              </div>
              <p class="cb-hint">Full interactive suite: Interaction → HUI Controls → Tabs</p>
            {/if}

            {%if @entry_id == "tailwind-plus"}
              <p style="color: var(--text-secondary); margin-bottom: var(--space-2)">
                686 static HTML widget demos (App UI, Marketing, Ecommerce).
              </p>
              <a href="/style-guide/tailwind-plus" class="btn btn-black">Open Tailwind Plus browser</a>
            {/if}
          </div>
        {%else}
          <div class="cb-empty">Select a component from the sidebar</div>
        {/if}
      </section>
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:select_category, params, component) do
    cat = ComponentCatalog.find_category(params.slug)
    entries = filter_entries(cat.entries, component.state.search)
    entry = List.first(entries) || List.first(cat.entries)

    put_state(component,
      category_slug: cat.slug,
      category: cat,
      entries: entries,
      entry_id: entry && entry.id,
      entry: entry
    )
  end

  def action(:select_entry, params, component) do
    entry = ComponentCatalog.find_entry(component.state.category_slug, params.id)
    put_state(component, entry_id: entry.id, entry: entry)
  end

  def action(:update_search, params, component) do
    search = params.event.value || ""
    entries = filter_entries(component.state.category.entries, search)
    entry = List.first(entries) || component.state.entry

    put_state(component,
      search: search,
      entries: entries,
      entry_id: entry && entry.id,
      entry: entry
    )
  end

  defp filter_entries(entries, search) when is_list(entries) and is_binary(search) do
    q = search |> String.trim() |> String.downcase()

    if q == "" do
      entries
    else
      Enum.filter(entries, fn e ->
        String.contains?(String.downcase(e.name), q) or
          String.contains?(String.downcase(e.id), q)
      end)
    end
  end

  defp filter_entries(entries, _), do: entries
end
