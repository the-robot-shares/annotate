defmodule StarterWeb.Hologram.Components.TypeSpecimen do
  @moduledoc "StyleGuideTypeSpecimen."
  use Hologram.Component

  prop :name, :string, default: ""
  prop :font, :string, default: "var(--font-sans)"
  prop :weight, :string, default: "400"
  prop :size, :string, default: "1rem"
  prop :line_height, :string, default: "1.5"
  prop :sample, :string, default: "The quick brown fox jumps over the lazy dog."
  prop :usage, :string, default: nil

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="type-specimen">
      <div class="type-meta">
        <strong>{@name}</strong><br />
        {@font} {@weight}<br />
        {@size} / {@line_height}
        {%if @usage}<div class="type-usage">{@usage}</div>{/if}
      </div>
      <div style={"font-family: #{@font}; font-weight: #{@weight}; font-size: #{@size}; line-height: #{@line_height}; color: var(--border-strong); max-width: 560px"}>
        {@sample}
      </div>
    </div>
    """
  end
end
