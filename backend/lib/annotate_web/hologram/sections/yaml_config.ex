defmodule AnnotateWeb.Hologram.Sections.YamlConfig do
  @moduledoc """
  Theme Config — browse / edit theme YAML facets and save named variants.

  Mirrors the Next.js YamlConfigViewer without Monaco (plain textarea + mono CSS).
  """
  use Hologram.Component

  alias Annotate.StyleGuide.ThemeData

  prop :theme_slug, :string, default: "style-guide"

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(props, component, _server), do: do_init(props, component)
  def init(props, component), do: do_init(props, component)

  defp do_init(props, component) do
    slug = Map.get(props, :theme_slug, "style-guide") || "style-guide"
    put_state(component, yaml_state(slug))
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-yaml-config">
      <p class="sg-page-intro" style="color: var(--text-secondary); margin-bottom: var(--space-3)">
        YAML source for theme <strong>{@theme_slug}</strong>. Edit and save as a named variant
        (<code>style-guide.section.variant.yaml</code>). Branding is view-only.
      </p>

      <div class="sg-yaml-toolbar">
        <label class="sg-yaml-label" for="yaml-file-select">File</label>
        <select id="yaml-file-select" class="field-select sg-yaml-select" $change={:select_file}>
          {%for f <- @files}
            <option value={f.name} selected={f.name == @active_name}>{f.short}</option>
          {/for}
        </select>

        <div class="sg-yaml-nav">
          <button type="button" class="btn btn-outline btn-sm" $click={:prev_file} disabled={if @at_start do true end}>‹</button>
          <button type="button" class="btn btn-outline btn-sm" $click={:next_file} disabled={if @at_end do true end}>›</button>
        </div>

        <span class="sg-yaml-meta">
          {@line_count} lines
          {%if @dirty}
            <span class="sg-yaml-dirty">unsaved</span>
          {/if}
        </span>

        <div class="sg-yaml-save-row">
          <input
            type="text"
            class="field-input sg-yaml-variant"
            placeholder="variant name (e.g. user)"
            value={@variant}
            $change={:set_variant}
          />
          <button
            type="button"
            class="btn btn-black btn-sm"
            $click={:save_variant}
            disabled={if @save_disabled do true end}
          >
            Save variant
          </button>
        </div>
      </div>

      {%if @status}
        <p class="sg-flash" role="status">{@status}</p>
      {/if}

      <textarea
        class="sg-yaml-editor"
        spellcheck="false"
        rows={@editor_rows}
        $change={:edit_content}
      >{@content}</textarea>

      <p style="color: var(--text-muted); font-size: var(--font-size-xs); margin-top: var(--space-2)">
        Active file: <code>{@active_name}</code>
        · {@file_count} files in <code>themes/theme-{@theme_slug}/</code>
      </p>
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:select_file, params, component) do
    apply_file(component, params.event.value)
  end

  def action(:prev_file, _params, component) do
    idx = max(component.state.file_index - 1, 0)
    name = Enum.at(component.state.files, idx).name
    apply_file(component, name)
  end

  def action(:next_file, _params, component) do
    max_i = max(component.state.file_count - 1, 0)
    idx = min(component.state.file_index + 1, max_i)
    name = Enum.at(component.state.files, idx).name
    apply_file(component, name)
  end

  def action(:edit_content, params, component) do
    content = params.event.value || ""
    original = component.state.original
    dirty = content != original
    rows = editor_rows(content)

    put_state(component,
      content: content,
      dirty: dirty,
      line_count: line_count(content),
      editor_rows: rows,
      status: nil
    )
  end

  def action(:set_variant, params, component) do
    put_state(component, variant: params.event.value || "", status: nil)
  end

  def action(:save_variant, _params, component) do
    if component.state.saveable do
      component
      |> put_state(status: "Saving…")
      |> put_command(:save_yaml_variant,
        slug: component.state.theme_slug,
        section: component.state.section,
        variant: component.state.variant,
        content: component.state.content
      )
    else
      put_state(component, status: "This file is view-only (or not a style-guide facet).")
    end
  end

  def action(:yaml_saved, params, component) do
    put_state(component,
      status: "Saved → #{params.file}",
      dirty: false,
      original: component.state.content
    )
  end

  def action(:yaml_error, params, component) do
    put_state(component, status: "Error: #{params.msg}")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:save_yaml_variant, params, server) do
    case ThemeData.save_variant(params.slug, params.section, params.variant, params.content) do
      {:ok, filename} ->
        put_action(server, :yaml_saved, file: filename)

      {:error, msg} ->
        put_action(server, :yaml_error, msg: msg)
    end
  end

  defp apply_file(component, name) do
    files = component.state.files
    {file, index} = find_file(files, name)
    count = length(files)

    put_state(component,
      active_name: file.name,
      short: file.short,
      content: file.content,
      original: file.content,
      line_count: file.line_count,
      editor_rows: editor_rows(file.content),
      saveable: file.saveable,
      save_disabled: not file.saveable,
      section: ThemeData.section_of(file.name) || file.short,
      file_index: index,
      at_start: index == 0,
      at_end: index >= count - 1 or count == 0,
      dirty: false,
      status: nil
    )
  end

  defp find_file(files, name) do
    case Enum.find_index(files, &(&1.name == name)) do
      nil ->
        f = List.first(files) || empty_file()
        {f, 0}

      i ->
        {Enum.at(files, i), i}
    end
  end

  defp yaml_state(slug) do
    files = ThemeData.yaml_files(slug)
    file = List.first(files) || empty_file()
    count = length(files)

    [
      theme_slug: slug,
      files: files,
      file_count: count,
      file_index: 0,
      at_start: true,
      at_end: count <= 1,
      active_name: file.name,
      short: file.short,
      content: file.content,
      original: file.content,
      line_count: file.line_count,
      editor_rows: editor_rows(file.content),
      saveable: file.saveable,
      save_disabled: not file.saveable,
      section: ThemeData.section_of(file.name) || file.short,
      variant: "user",
      dirty: false,
      status: nil
    ]
  end

  defp empty_file do
    %{
      name: "(none)",
      short: "none",
      content: "# No YAML files found for this theme\n",
      line_count: 1,
      saveable: false
    }
  end

  defp line_count(content), do: content |> String.split("\n") |> length()

  defp editor_rows(content) do
    n = line_count(content)

    cond do
      n < 16 -> 16
      n > 36 -> 36
      true -> n
    end
  end
end
