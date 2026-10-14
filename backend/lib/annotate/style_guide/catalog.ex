defmodule Annotate.StyleGuide.Catalog do
  @moduledoc """
  Theme list + page section structure for the Hologram viewer.

  **Themes are not hardcoded.** `themes/0` discovers `themes/theme-*/` directories
  and reads `style-guide.meta.yaml` (+ optional `branding.yaml`) at runtime.
  Theme CSS is served from `priv/static/themes/{slug}.css` (YAML → CSS offline
  via the styleguide engine). Color palettes, shells, and Theme Config load live
  YAML via `Annotate.StyleGuide.ThemeData`.
  """

  # lib/styleguide → ../../themes
  @themes_root Path.expand("../../../themes", __DIR__)
  @static_themes_root Path.expand("../../../priv/static/themes", __DIR__)

  @groups [
    %{
      id: "visual-foundation",
      group: "Visual Foundation",
      desc: "Type, color, space, dividers, and glyphs that every component is built from.",
      sections: [
        %{
          id: "typography",
          title: "Typography",
          number: "01",
          desc: "Typefaces, sizes, weights, decorations, and text color usage."
        },
        %{
          id: "color",
          title: "Color",
          number: "02",
          desc: "Brand palette, surfaces, and semantic states."
        },
        %{
          id: "spacing",
          title: "Spacing & Grid",
          number: "03",
          desc: "Scale, rhythm, column grid, and whitespace principles."
        },
        %{
          id: "dividers",
          title: "Dividers & Rules",
          number: "04",
          desc: "Horizontal separators — simple, labeled, branded."
        },
        %{
          id: "glyphs",
          title: "Glyph Language",
          number: "05",
          desc: "Unicode glyphs for UI controls and navigation."
        }
      ]
    },
    %{
      id: "structure",
      group: "Structure",
      desc: "How pages and shells are assembled — layouts and navigation patterns.",
      sections: [
        %{
          id: "shell-layouts",
          title: "Shell Layouts",
          number: "06",
          desc: "YAML shell wireframes plus Login and Dashboard screen demos."
        },
        %{
          id: "content-layouts",
          title: "Content Layouts",
          number: "07",
          desc: "Content width presets — standard, wide, narrow, article."
        },
        %{
          id: "navigation",
          title: "Navigation",
          number: "08",
          desc: "Wayfinding — tabs, breadcrumbs, side patterns."
        }
      ]
    },
    %{
      id: "interaction",
      group: "Interaction",
      desc: "Semantic controls, status signals, and interactive primitives.",
      sections: [
        %{
          id: "buttons",
          title: "Buttons",
          number: "09",
          desc: "btn variants, sizes, and states."
        },
        %{
          id: "cards",
          title: "Cards",
          number: "10",
          desc: "card / card-title / card-body compositions."
        },
        %{
          id: "forms",
          title: "Forms",
          number: "11",
          desc: "Field chrome, inputs, validation affordances."
        },
        %{
          id: "status",
          title: "Status Indicators",
          number: "12",
          desc: "Status dots, badges, and feedback signals."
        },
        %{
          id: "hui",
          title: "HUI Controls",
          number: "13",
          desc: "Checkbox, switch, radio, tabs, menu, dialog, and more."
        }
      ]
    },
    %{
      id: "component-library",
      group: "Component Library",
      desc: "Browse exported Hologram primitives with live previews.",
      sections: [
        %{
          id: "components",
          title: "Component Browser",
          number: "14",
          desc: "Interactive catalog — pick a category and component to preview."
        }
      ]
    },
    %{
      id: "reference",
      group: "Reference",
      desc: "Tokens, YAML config, migration notes, and the Tailwind Plus catalog.",
      sections: [
        %{
          id: "tokens",
          title: "Design Tokens",
          number: "15",
          desc: "CSS custom property samples from the active theme."
        },
        %{
          id: "theme-config",
          title: "Theme Config",
          number: "16",
          desc: "YAML source for this theme. Browse, edit, and save named variants."
        },
        %{
          id: "migration",
          title: "Migration",
          number: "17",
          desc: "Elixir-only stack notes."
        },
        %{
          id: "tailwind-plus",
          title: "Tailwind Plus",
          number: "18",
          desc: "Full catalog (686 static HTML demos) at /style-guide/tailwind-plus."
        }
      ]
    }
  ]

  @doc """
  Discover themes from `themes/theme-*/style-guide.meta.yaml`.

  Falls back to scanning `priv/static/themes/*.css` if no YAML themes exist.
  Prefer `style-guide` as the default (first) theme when present.
  """
  # <REMOVED UUID HERE> themes :: Discover themes from `themes/theme-*/style-guide.meta.yaml`.
  def themes do
    from_yaml = discover_themes_from_yaml()

    themes =
      if from_yaml == [] do
        discover_themes_from_css()
      else
        from_yaml
      end

    prefer_slug_first(themes, "style-guide")
  end

  # <REMOVED UUID HERE> theme_slugs :: auto-generated pointer for public function theme_slugs
  def theme_slugs, do: Enum.map(themes(), & &1.slug)

  # <REMOVED UUID HERE> get_theme :: auto-generated pointer for public function get_theme
  def get_theme(slug) when is_binary(slug) do
    list = themes()
    Enum.find(list, List.first(list), &(&1.slug == slug))
  end

  def get_theme(_), do: List.first(themes())

  # <REMOVED UUID HERE> groups :: auto-generated pointer for public function groups
  def groups, do: @groups

  # <REMOVED UUID HERE> first_group_id :: auto-generated pointer for public function first_group_id
  def first_group_id, do: hd(@groups).id

  # <REMOVED UUID HERE> first_section_id :: auto-generated pointer for public function first_section_id
  def first_section_id do
    hd(hd(@groups).sections).id
  end

  # <REMOVED UUID HERE> find_group :: auto-generated pointer for public function find_group
  def find_group(id) do
    Enum.find(@groups, List.first(@groups), &(&1.id == id))
  end

  # <REMOVED UUID HERE> find_section :: auto-generated pointer for public function find_section
  def find_section(group_id, section_id) do
    group = find_group(group_id)
    Enum.find(group.sections, List.first(group.sections), &(&1.id == section_id))
  end

  @doc "Brand copy — prefers `themes/theme-style-guide/branding.yaml` when present."
  # <REMOVED UUID HERE> brand :: Brand copy — prefers `themes/theme-style-guide/branding.yaml` when present.
  def brand do
    path = Path.join([@themes_root, "theme-style-guide", "branding.yaml"])

    case read_yaml(path) do
      map when is_map(map) and map_size(map) > 0 ->
        product = Map.get(map, "product") || Map.get(map, "brand") || map

        %{
          name: pick(product, ["name", "title"], "noizu.ink"),
          logo_text: pick(product, ["logo_text", "logo", "name"], "NOIZU.INK"),
          title: pick(product, ["title", "name"], "Style Guide"),
          description:
            pick(product, ["description", "tagline"], "YAML-driven design system viewer."),
          font_url:
            pick(
              product,
              ["font_url", "fonts_url"],
              "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&family=IBM+Plex+Mono:wght@400;500;700&display=swap"
            )
        }

      _ ->
        %{
          name: "noizu.ink",
          logo_text: "NOIZU.INK",
          title: "Style Guide",
          description: "YAML-driven design system viewer, rebuilt on Hologram.",
          font_url:
            "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&family=IBM+Plex+Mono:wght@400;500;700&display=swap"
        }
    end
  end

  # ── theme discovery ──────────────────────────────────────────

  defp discover_themes_from_yaml do
    root = @themes_root

    if File.dir?(root) do
      root
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "theme-"))
      |> Enum.sort()
      |> Enum.map(&load_theme_from_dir(Path.join(root, &1), &1))
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  rescue
    _ -> []
  end

  defp load_theme_from_dir(dir, folder_name) do
    meta_path = Path.join(dir, "style-guide.meta.yaml")
    meta = read_yaml(meta_path)

    slug_from_folder = String.replace_prefix(folder_name, "theme-", "")

    slug =
      (Map.get(meta, "slug") || Map.get(meta, "name") || slug_from_folder)
      |> to_string()
      |> String.trim()

    # Prefer display title; fall back to name / humanized slug
    title = Map.get(meta, "title")
    raw_name = Map.get(meta, "name")

    # Short UI label: prefer meta name when distinct, else first segment of title
    display_name =
      cond do
        is_binary(raw_name) and raw_name != "" and raw_name != slug ->
          raw_name

        is_binary(title) and String.contains?(to_string(title), "—") ->
          title |> to_string() |> String.split("—") |> List.last() |> String.trim()

        is_binary(title) and title != "" ->
          to_string(title)

        true ->
          humanize_slug(slug)
      end

    css_path = "/themes/#{slug}.css"
    css_file = Path.join(@static_themes_root, "#{slug}.css")

    # Prefer theme CSS that exists; fall back to style-guide.css
    css =
      cond do
        File.exists?(css_file) ->
          css_path

        File.exists?(Path.join(@static_themes_root, "style-guide.css")) ->
          "/themes/style-guide.css"

        true ->
          css_path
      end

    %{
      slug: slug,
      name: to_string(display_name),
      title: to_string(Map.get(meta, "title") || display_name),
      description: to_string(Map.get(meta, "description") || ""),
      css: css,
      dir: dir
    }
  rescue
    _ -> nil
  end

  defp discover_themes_from_css do
    root = @static_themes_root

    if File.dir?(root) do
      root
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".css"))
      |> Enum.sort()
      |> Enum.map(fn file ->
        slug = String.replace_suffix(file, ".css", "")

        %{
          slug: slug,
          name: humanize_slug(slug),
          title: humanize_slug(slug),
          description: "",
          css: "/themes/#{file}",
          dir: nil
        }
      end)
    else
      []
    end
  rescue
    _ -> []
  end

  defp prefer_slug_first(themes, slug) do
    case Enum.split_with(themes, &(&1.slug == slug)) do
      {[], rest} -> rest
      {match, rest} -> match ++ rest
    end
  end

  defp humanize_slug(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp pick(map, keys, default) when is_map(map) do
    Enum.find_value(keys, default, fn k ->
      case Map.get(map, k) do
        nil -> nil
        "" -> nil
        v -> to_string(v)
      end
    end)
  end

  defp pick(_, _, default), do: default

  defp read_yaml(path) do
    if File.exists?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end
    else
      %{}
    end
  end
end
