defmodule AnnotateWeb.Hologram.Pages.TailwindPlusPage do
  @moduledoc """
  Browse Tailwind Plus demos (iframe → static HTML under priv/static/twp/demos).

  Catalog is JSON + HTML only — no TypeScript. Prefers `Annotate.StyleGuide.TwpCatalog`
  at init; falls back to reading `priv/static/twp/registry.json`.

  Demos load `/twp/demo-bridge.js`, which:
  - follows the viewer theme (`data-design-theme` / `sg-theme` cookie) and color mode
  - maps theme CSS variables into the Tailwind CDN palette
  - enables toggles, tabs, overlays, and dropdowns

  Client actions only read from page state (no File I/O on the client).
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Pages.LandingPage
  alias AnnotateWeb.Hologram.Pages.StyleGuidePage

  route "/styleguide/tailwind-plus"
  layout MainLayout, page_title: "Tailwind Plus"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    sections = catalog_sections()
    stats = catalog_stats()
    theme_slug = Hologram.Server.get_cookie(server, "sg-theme", "style-guide")
    color_mode = Hologram.Server.get_cookie(server, "color-mode", "system")

    case catalog_first_entry() || first_from_sections(sections) do
      {section_id, group_label, entry} ->
        groups = groups_from_sections(sections, section_id)
        entries = entries_for_group(groups, group_label)
        href = Map.get(entry, "href", "")

        put_state(component,
          sections: sections,
          stats: stats,
          section_id: section_id,
          group_label: group_label,
          groups: groups,
          entries: entries,
          export_name: Map.get(entry, "exportName"),
          entry: entry,
          theme_slug: theme_slug,
          color_mode: color_mode,
          iframe_src: demo_src(href, theme_slug, color_mode),
          search: ""
        )

      nil ->
        put_state(component,
          sections: sections,
          stats: stats,
          section_id: nil,
          group_label: nil,
          groups: [],
          entries: [],
          export_name: nil,
          entry: %{},
          theme_slug: theme_slug,
          color_mode: color_mode,
          iframe_src: "",
          search: ""
        )
    end
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content twp-browser">
      <div class="sg-hero">
        <p class="twp-back">
          <Link to={StyleGuidePage} class="btn btn-outline btn-sm">← Style Guide</Link>
          <Link to={LandingPage} class="btn btn-outline btn-sm">Home</Link>
        </p>
        <h1>Tailwind Plus</h1>
        <p>
          HTML widget catalog under <code>priv/static/twp/</code>
          ({Map.get(@stats, "total", 0)} components). Demos follow the viewer
          <strong>theme</strong> and <strong>color mode</strong> (bar above) and
          support basic interactivity (toggles, tabs, modals/drawers, dropdowns).
        </p>
      </div>

      <nav class="sg-group-nav twp-section-tabs" aria-label="Catalog sections">
        {%for s <- @sections}
          <button
            type="button"
            class="btn btn-outline btn-sm"
            data-selected={if Map.get(s, "id") == @section_id do "" end}
            $click={:select_section, id: Map.get(s, "id")}
          >
            {Map.get(s, "label")}
          </button>
        {/for}
      </nav>

      <div class="twp-browser__layout">
        <aside class="twp-browser__sidebar" aria-label="Groups and entries">
          <input
            type="search"
            class="twp-search"
            placeholder="Filter entries…"
            value={@search}
            $change={:update_search}
          />

          <nav class="twp-group-list" aria-label="Component groups">
            {%for g <- @groups}
              <button
                type="button"
                class="twp-group-btn"
                data-selected={if Map.get(g, "label") == @group_label do "" end}
                $click={:select_group, label: Map.get(g, "label")}
              >
                <span class="twp-group-btn__label">{Map.get(g, "label")}</span>
                <span class="twp-group-btn__count">{Enum.count(Map.get(g, "entries", []))}</span>
              </button>
            {/for}
          </nav>

          <nav class="twp-entry-list" aria-label="Component entries">
            {%for e <- @entries}
              <button
                type="button"
                class="twp-entry-btn"
                data-selected={if Map.get(e, "exportName") == @export_name do "" end}
                $click={:select_entry, export_name: Map.get(e, "exportName")}
              >
                {Map.get(e, "name")}
                {%if Map.get(e, "stub")}
                  <span class="twp-stub">stub</span>
                {/if}
              </button>
            {/for}
          </nav>
        </aside>

        <section class="twp-browser__main">
          {%if @export_name}
            <div class="twp-preview-meta">
              <h2 class="twp-preview-title">
                {Map.get(@entry, "name")}
                {%if Map.get(@entry, "stub")}
                  <span class="twp-stub">stub</span>
                {/if}
              </h2>
              <p class="twp-preview-path">{Map.get(@entry, "path")}</p>
            </div>
            <iframe
              class="twp-iframe"
              src={@iframe_src}
              title={Map.get(@entry, "name")}
            />
          {%else}
            <div class="twp-empty">← Select a component from the sidebar</div>
          {/if}
        </section>
      </div>
    </div>
    """
  end

  # Client-side only: navigate using data already in state.

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:select_section, params, component) do
    section_id = params.id
    groups = groups_from_sections(component.state.sections, section_id)
    group = List.first(groups) || %{}
    group_label = Map.get(group, "label")
    all_entries = Map.get(group, "entries", [])
    entries = filter_entries(all_entries, component.state.search)
    entry = List.first(entries) || List.first(all_entries) || %{}

    put_state(component,
      section_id: section_id,
      groups: groups,
      group_label: group_label,
      entries: entries,
      export_name: Map.get(entry, "exportName"),
      entry: entry,
      iframe_src:
        demo_src(
          Map.get(entry, "href", ""),
          component.state.theme_slug,
          component.state.color_mode
        )
    )
  end

  def action(:select_group, params, component) do
    group_label = params.label
    all_entries = entries_for_group(component.state.groups, group_label)
    entries = filter_entries(all_entries, component.state.search)
    entry = List.first(entries) || List.first(all_entries) || %{}

    put_state(component,
      group_label: group_label,
      entries: entries,
      export_name: Map.get(entry, "exportName"),
      entry: entry,
      iframe_src:
        demo_src(
          Map.get(entry, "href", ""),
          component.state.theme_slug,
          component.state.color_mode
        )
    )
  end

  def action(:select_entry, params, component) do
    export_name = params.export_name
    entry = find_entry_in_list(component.state.entries, export_name) || %{}

    put_state(component,
      export_name: Map.get(entry, "exportName", export_name),
      entry: entry,
      iframe_src:
        demo_src(
          Map.get(entry, "href", ""),
          component.state.theme_slug,
          component.state.color_mode
        )
    )
  end

  def action(:update_search, params, component) do
    search = params.event.value || ""
    all_entries = entries_for_group(component.state.groups, component.state.group_label)
    entries = filter_entries(all_entries, search)

    put_state(component, search: search, entries: entries)
  end

  # --- Shared pure helpers (safe on client) ---

  # Append theme + mode so first paint matches the viewer even before parent DOM sync.
  defp demo_src(href, _theme, _mode) when href in [nil, ""], do: ""

  defp demo_src(href, theme_slug, color_mode) do
    # Client-safe (no URI module): theme slugs / modes are controlled enums.
    theme = theme_slug || "style-guide"
    mode = color_mode || "system"
    sep = if String.contains?(href, "?"), do: "&", else: "?"
    href <> sep <> "theme=" <> theme <> "&mode=" <> mode
  end

  defp groups_from_sections(sections, section_id) when is_binary(section_id) do
    case Enum.find(sections, &(Map.get(&1, "id") == section_id)) do
      nil -> []
      sec -> Map.get(sec, "groups", [])
    end
  end

  defp groups_from_sections(_, _), do: []

  defp entries_for_group(groups, group_label) when is_binary(group_label) do
    case Enum.find(groups, &(Map.get(&1, "label") == group_label)) do
      nil -> []
      group -> Map.get(group, "entries", [])
    end
  end

  defp entries_for_group(_, _), do: []

  defp find_entry_in_list(entries, export_name)
       when is_list(entries) and is_binary(export_name) do
    Enum.find(entries, &(Map.get(&1, "exportName") == export_name))
  end

  defp find_entry_in_list(_, _), do: nil

  defp filter_entries(entries, search) when is_list(entries) and is_binary(search) do
    q = search |> String.trim() |> String.downcase()

    if q == "" do
      entries
    else
      Enum.filter(entries, fn e ->
        name = e |> Map.get("name", "") |> String.downcase()
        export = e |> Map.get("exportName", "") |> String.downcase()
        String.contains?(name, q) or String.contains?(export, q)
      end)
    end
  end

  defp filter_entries(entries, _) when is_list(entries), do: entries
  defp filter_entries(_, _), do: []

  defp first_from_sections(sections) do
    with [sec | _] <- sections,
         section_id when is_binary(section_id) <- Map.get(sec, "id"),
         [group | _] <- Map.get(sec, "groups", []),
         group_label when is_binary(group_label) <- Map.get(group, "label"),
         [entry | _] <- Map.get(group, "entries", []) do
      {section_id, group_label, entry}
    else
      _ -> nil
    end
  end

  # --- Server-only catalog load (init) ---

  defp catalog_sections do
    if catalog_available?() do
      Annotate.StyleGuide.TwpCatalog.sections()
    else
      Map.get(load_registry(), "sections", [])
    end
  end

  defp catalog_stats do
    if catalog_available?() and function_exported?(Annotate.StyleGuide.TwpCatalog, :stats, 0) do
      Annotate.StyleGuide.TwpCatalog.stats()
    else
      Map.get(load_registry(), "stats", %{"ok" => 0, "stub" => 0, "total" => 0})
    end
  end

  defp catalog_first_entry do
    if catalog_available?() and
         function_exported?(Annotate.StyleGuide.TwpCatalog, :first_entry, 0) do
      Annotate.StyleGuide.TwpCatalog.first_entry()
    else
      nil
    end
  end

  defp catalog_available? do
    Code.ensure_loaded?(Annotate.StyleGuide.TwpCatalog) and
      function_exported?(Annotate.StyleGuide.TwpCatalog, :sections, 0)
  end

  defp load_registry do
    path = Path.join(:code.priv_dir(:styleguide), "static/twp/registry.json")

    case File.read(path) do
      {:ok, body} -> Jason.decode!(body)
      {:error, _} -> %{"sections" => [], "stats" => %{"ok" => 0, "stub" => 0, "total" => 0}}
    end
  end
end
