defmodule Starter.StyleGuide.ThemeData do
  @moduledoc """
  Load theme YAML from `themes/theme-{slug}/` — color palette, semantic classes,
  and raw style-guide facet files for the Theme Config viewer.
  """

  # lib/styleguide → ../../themes
  @themes_root Path.expand("../../../themes", __DIR__)

  @doc "Absolute path to a theme directory (`theme-style-guide`, …)."
  # <REMOVED UUID HERE> theme_dir :: Absolute path to a theme directory (`theme-style-guide`, …).
  def theme_dir(slug) when is_binary(slug) do
    safe = slug |> String.replace(~r/[^a-z0-9-]/, "") |> String.trim("-")
    Path.join(@themes_root, "theme-#{safe}")
  end

  def theme_dir(_), do: theme_dir("style-guide")

  @doc """
  Color palette groups from `style-guide.color-palette.yaml`.

  Returns list of `%{id, group, description, colors, notes}` with atom keys.
  """
  # <REMOVED UUID HERE> color_palette :: Color palette groups from `style-guide.color-palette.yaml`.
  def color_palette(slug \\ "style-guide") do
    path = Path.join(theme_dir(slug), "style-guide.color-palette.yaml")

    case read_yaml_map(path) do
      %{"color-palette" => groups} when is_list(groups) ->
        groups
        |> Enum.with_index()
        |> Enum.map(fn {g, i} -> normalize_color_group(g, i) end)

      _ ->
        []
    end
  end

  @doc """
  Semantic classes as color groups (one group per semantic-groups entry).
  """
  # <REMOVED UUID HERE> semantic_color_groups :: Semantic classes as color groups (one group per semantic-groups entry).
  def semantic_color_groups(slug \\ "style-guide") do
    classes = semantic_classes(slug)

    if classes == [] do
      []
    else
      groups = semantic_groups(slug)

      built =
        groups
        |> Enum.with_index()
        |> Enum.map(fn {sg, i} ->
          matched = Enum.filter(classes, &(&1.group == sg.name))
          if matched == [], do: nil, else: color_group_from(sg.name, sg.description, matched, i)
        end)
        |> Enum.reject(&is_nil/1)

      if built != [] do
        built
      else
        # Themes without group fields (or mismatched groups): bucket by class.group
        classes
        |> Enum.group_by(& &1.group)
        |> Enum.with_index()
        |> Enum.map(fn {{name, matched}, i} ->
          color_group_from(name || "Other", nil, matched, i)
        end)
      end
    end
  end

  defp color_group_from(name, description, matched, index) do
    %{
      id: "sem-#{index}-#{slugify(name)}",
      group: name,
      description: description || "",
      colors: Enum.map(matched, &semantic_to_color/1),
      notes:
        matched
        |> Enum.filter(&(&1.note != nil and &1.note != ""))
        |> Enum.map(fn sc ->
          %{
            label: sc.title,
            text: sc.note,
            swatch: sc.accent,
            css_class: sc.class
          }
        end)
    }
  end

  @doc """
  Shell layouts from `style-guide.shell-layouts.yaml`.

  Each entry: `%{name, title, description, chrome, zones}` with atom keys.
  Chrome may include `:navbar`, `:sidebar`, `:aside`, `:footer` maps.
  """
  # <REMOVED UUID HERE> shell_layouts :: Shell layouts from `style-guide.shell-layouts.yaml`.
  def shell_layouts(slug \\ "style-guide") do
    path = Path.join(theme_dir(slug), "style-guide.shell-layouts.yaml")

    case read_yaml_map(path) do
      %{"shell-layouts" => list} when is_list(list) ->
        Enum.map(list, &normalize_shell/1)

      _ ->
        []
    end
  end

  @doc "Raw semantic class records."
  # <REMOVED UUID HERE> semantic_classes :: Raw semantic class records.
  def semantic_classes(slug \\ "style-guide") do
    path = Path.join(theme_dir(slug), "style-guide.semantic-classes.yaml")

    case read_yaml_map(path) do
      %{"semantic-classes" => list} when is_list(list) ->
        Enum.map(list, &normalize_semantic_class/1)

      _ ->
        []
    end
  end

  # <REMOVED UUID HERE> semantic_groups :: auto-generated pointer for public function semantic_groups
  def semantic_groups(slug \\ "style-guide") do
    path = Path.join(theme_dir(slug), "style-guide.semantic-groups.yaml")

    case read_yaml_map(path) do
      %{"semantic-groups" => list} when is_list(list) ->
        Enum.map(list, fn g ->
          %{
            name: Map.get(g, "name") || Map.get(g, :name) || "Group",
            description: Map.get(g, "description") || Map.get(g, :description) || ""
          }
        end)

      _ ->
        []
    end
  end

  @doc """
  List editable YAML facet files for a theme (style-guide.*.yaml + branding.yaml).

  Each entry: `%{name, short, content, line_count, saveable}`.
  """
  # <REMOVED UUID HERE> yaml_files :: List editable YAML facet files for a theme (style-guide.*.yaml + branding.yaml).
  def yaml_files(slug \\ "style-guide") do
    dir = theme_dir(slug)

    if File.dir?(dir) do
      style_files =
        dir
        |> File.ls!()
        |> Enum.filter(&style_guide_yaml?/1)
        |> Enum.sort()
        |> Enum.map(fn name ->
          content = File.read!(Path.join(dir, name))

          %{
            name: name,
            short: short_name(name),
            content: content,
            line_count: line_count(content),
            saveable: true
          }
        end)

      branding_path = Path.join(dir, "branding.yaml")

      branding =
        if File.exists?(branding_path) do
          content = File.read!(branding_path)

          [
            %{
              name: "branding.yaml",
              short: "branding",
              content: content,
              line_count: line_count(content),
              saveable: false
            }
          ]
        else
          []
        end

      style_files ++ branding
    else
      []
    end
  end

  # <REMOVED UUID HERE> find_yaml_file :: auto-generated pointer for public function find_yaml_file
  def find_yaml_file(slug, name) do
    Enum.find(yaml_files(slug), &(&1.name == name))
  end

  @doc """
  Save a named variant: `style-guide.{section}.{variant}.yaml`.

  Section is derived from the base file name (e.g. color-palette).
  """
  # <REMOVED UUID HERE> save_variant :: Save a named variant: `style-guide.{section}.{variant}.yaml`.
  def save_variant(slug, section, variant, content)
      when is_binary(section) and is_binary(variant) and is_binary(content) do
    section = section |> String.replace(~r/[^a-z0-9-]/, "") |> String.trim("-")
    variant = variant |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "-") |> String.trim("-")

    cond do
      section == "" ->
        {:error, "Invalid section"}

      variant == "" ->
        {:error, "Invalid variant name"}

      true ->
        dir = theme_dir(slug)

        if File.dir?(dir) do
          filename = "style-guide.#{section}.#{variant}.yaml"
          path = Path.join(dir, filename)

          if String.starts_with?(Path.expand(path), Path.expand(dir)) do
            case File.write(path, content) do
              :ok -> {:ok, filename}
              {:error, reason} -> {:error, "Write failed: #{inspect(reason)}"}
            end
          else
            {:error, "Invalid path"}
          end
        else
          {:error, "Theme directory not found"}
        end
    end
  end

  def save_variant(_, _, _, _), do: {:error, "Missing fields"}

  @doc "Extract section key from a style-guide filename."
  # <REMOVED UUID HERE> section_of :: Extract section key from a style-guide filename.
  def section_of("style-guide." <> rest) do
    rest
    |> String.replace(~r/\.yaml$/, "")
    # style-guide.color-palette.user.yaml → color-palette (base section)
    |> String.split(".")
    |> List.first()
  end

  def section_of(_), do: nil

  # ── private ──────────────────────────────────────────────────────────────

  defp style_guide_yaml?(name) do
    String.starts_with?(name, "style-guide.") and String.ends_with?(name, ".yaml") and
      name != "style-guide.overrides.yaml"
  end

  defp short_name("style-guide." <> rest), do: String.replace(rest, ~r/\.yaml$/, "")
  defp short_name(name), do: String.replace(name, ~r/\.yaml$/, "")

  defp line_count(content), do: content |> String.split("\n") |> length()

  defp read_yaml_map(path) do
    if File.exists?(path) do
      case YamlElixir.read_from_file(path) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp normalize_color_group(g, index) when is_map(g) do
    group_name = Map.get(g, "group") || Map.get(g, :group) || "Group #{index + 1}"
    colors = Map.get(g, "colors") || Map.get(g, :colors) || []
    notes = Map.get(g, "notes") || Map.get(g, :notes) || []

    %{
      id: "pal-#{index}-#{slugify(group_name)}",
      group: group_name,
      description: Map.get(g, "description") || Map.get(g, :description) || "",
      colors:
        Enum.map(List.wrap(colors), fn c ->
          %{
            name: Map.get(c, "name") || Map.get(c, :name) || "?",
            value: Map.get(c, "value") || Map.get(c, :value) || "#888",
            css_class: Map.get(c, "cssClass") || Map.get(c, "css_class") || Map.get(c, :css_class)
          }
        end),
      notes:
        Enum.map(List.wrap(notes), fn n ->
          css_class =
            Map.get(n, "cssClass") || Map.get(n, "css_class") || Map.get(n, :css_class)

          swatch =
            Map.get(n, "swatch") || Map.get(n, :swatch) ||
              if css_class, do: "var(--#{css_class})", else: "var(--border)"

          %{
            label: Map.get(n, "label") || Map.get(n, :label) || "",
            text: Map.get(n, "text") || Map.get(n, :text) || "",
            swatch: swatch,
            css_class: css_class
          }
        end)
    }
  end

  defp normalize_color_group(_, index) do
    %{id: "pal-#{index}", group: "Group", description: "", colors: [], notes: []}
  end

  defp normalize_shell(s) when is_map(s) do
    chrome = Map.get(s, "chrome") || Map.get(s, :chrome) || %{}
    zones = Map.get(s, "zones") || Map.get(s, :zones) || []

    %{
      name: Map.get(s, "name") || Map.get(s, :name) || "shell",
      title: Map.get(s, "title") || Map.get(s, :title) || "Shell",
      description: Map.get(s, "description") || Map.get(s, :description) || "",
      has_navbar: chrome_part?(chrome, "navbar"),
      has_sidebar: chrome_part?(chrome, "sidebar"),
      has_aside: chrome_part?(chrome, "aside"),
      has_footer: chrome_part?(chrome, "footer"),
      navbar: normalize_chrome_part(chrome, "navbar"),
      sidebar: normalize_chrome_part(chrome, "sidebar"),
      aside: normalize_chrome_part(chrome, "aside"),
      footer: normalize_chrome_part(chrome, "footer"),
      zones:
        Enum.map(List.wrap(zones), fn z ->
          %{
            label: Map.get(z, "label") || Map.get(z, :label) || "Zone",
            background: Map.get(z, "background") || Map.get(z, :background) || "var(--surface-alt)",
            color: Map.get(z, "color") || Map.get(z, :color) || "var(--text-muted)",
            ratio: Map.get(z, "ratio") || Map.get(z, :ratio) || 1
          }
        end)
    }
  end

  defp normalize_shell(_),
    do: %{
      name: "shell",
      title: "Shell",
      description: "",
      has_navbar: false,
      has_sidebar: false,
      has_aside: false,
      has_footer: false,
      navbar: nil,
      sidebar: nil,
      aside: nil,
      footer: nil,
      zones: []
    }

  defp chrome_part?(chrome, key) when is_map(chrome) do
    part = Map.get(chrome, key) || Map.get(chrome, String.to_atom(key))
    is_map(part)
  end

  defp chrome_part?(_, _), do: false

  defp normalize_chrome_part(chrome, key) when is_map(chrome) do
    part = Map.get(chrome, key) || Map.get(chrome, String.to_atom(key))

    if is_map(part) do
      %{
        label: Map.get(part, "label") || Map.get(part, :label) || String.capitalize(key),
        background: Map.get(part, "background") || Map.get(part, :background) || "var(--surface-alt)",
        color: Map.get(part, "color") || Map.get(part, :color) || "var(--text)",
        height: Map.get(part, "height") || Map.get(part, :height),
        width: Map.get(part, "width") || Map.get(part, :width)
      }
    else
      nil
    end
  end

  defp normalize_chrome_part(_, _), do: nil

  defp normalize_semantic_class(sc) when is_map(sc) do
    vars = normalize_vars(Map.get(sc, "vars") || Map.get(sc, :vars))

    %{
      name: Map.get(sc, "name") || Map.get(sc, :name) || "",
      class: Map.get(sc, "class") || Map.get(sc, :class) || "",
      group: Map.get(sc, "group") || Map.get(sc, :group) || "Other",
      title: Map.get(sc, "title") || Map.get(sc, :title) || Map.get(sc, "name") || "?",
      description: Map.get(sc, "description") || Map.get(sc, :description) || "",
      note: Map.get(sc, "note") || Map.get(sc, :note) || "",
      accent: Map.get(vars, "accent") || Map.get(vars, :accent) || "#888",
      background: Map.get(vars, "background") || Map.get(vars, :background) || "transparent"
    }
  end

  defp normalize_semantic_class(_),
    do: %{
      name: "",
      class: "",
      group: "Other",
      title: "?",
      description: "",
      note: "",
      accent: "#888",
      background: "transparent"
    }

  # style-guide theme: map of name => value
  # cyberpunk / sumi-e / swiss: list of %{name, value}
  defp normalize_vars(vars) when is_map(vars), do: vars

  defp normalize_vars(vars) when is_list(vars) do
    Enum.reduce(vars, %{}, fn
      entry, acc when is_map(entry) ->
        name = Map.get(entry, "name") || Map.get(entry, :name)
        value = Map.get(entry, "value") || Map.get(entry, :value)

        if is_binary(name) and not is_nil(value) do
          Map.put(acc, name, value)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp normalize_vars(_), do: %{}

  defp semantic_to_color(sc) do
    %{
      name: sc.title,
      value: sc.accent,
      css_class: sc.class
    }
  end

  defp slugify(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: "x"
end
