defmodule StarterWeb.Hologram.Components.ColorSwatch do
  @moduledoc "StyleGuideColorSwatch."
  use Hologram.Component

  prop :name, :string, default: ""
  prop :hex, :string, default: "#000000"
  prop :color, :string, default: "var(--white)"
  prop :inline, :boolean, default: false

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    {%if @inline}
      <div class="color-primary-block" style={"background: #{@hex}; color: #{@color}"}>
        <span class="name">{@name}</span>
        <span class="hex">{@hex}</span>
      </div>
    {%else}
      <div class="color-swatch">
        <div class="color-swatch-preview" style={"background: #{@hex}"}></div>
        <div class="color-swatch-info">
          <div class="color-swatch-name">{@name}</div>
          <div class="color-swatch-hex">{@hex}</div>
        </div>
      </div>
    {/if}
    """
  end
end
