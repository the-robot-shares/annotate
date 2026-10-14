defmodule StarterWeb.Hologram.Components.Btn do
  @moduledoc "StyleGuideBtn — `btn` / `btn-{variant}` / `btn-{size}`."
  use Hologram.Component

  prop :variant, :string, default: "black"
  prop :size, :string, default: nil
  prop :label, :string, default: ""
  prop :type, :string, default: "button"
  prop :disabled, :boolean, default: false
  prop :href, :string, default: nil
  prop :class, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    {%if @href}
      <a href={@href} class={classes(@variant, @size, @class)}>{@label}<slot /></a>
    {%else}
      <button type={@type} class={classes(@variant, @size, @class)} disabled={@disabled}>
        {@label}<slot />
      </button>
    {/if}
    """
  end

  # <REMOVED UUID HERE> classes :: auto-generated pointer for public function classes
  def classes(variant, size, extra) do
    ["btn", variant && "btn-#{variant}", size && "btn-#{size}", extra]
    |> Enum.reject(&(is_nil(&1) or &1 == false or &1 == ""))
    |> Enum.join(" ")
  end
end
