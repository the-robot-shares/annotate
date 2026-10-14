defmodule StarterWeb.Hologram.Components.SectionHeader do
  @moduledoc "StyleGuideSectionHeader."
  use Hologram.Component

  prop :number, :string, default: ""
  prop :title, :string, default: ""
  prop :desc, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-section-header">
      <div class="sg-section-number">{@number}</div>
      <div class="sg-section-title-group">
        <h2 class="sg-section-title">{@title}</h2>
        <p class="sg-section-desc">{@desc}</p>
      </div>
    </div>
    """
  end
end
