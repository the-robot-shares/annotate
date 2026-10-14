defmodule StarterWeb.Hologram.Components.SpacingScale do
  @moduledoc "StyleGuideSpacingScale — expects `steps` as list of maps `%{label, width}`."
  use Hologram.Component

  prop :steps, :list, default: []

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="spacing-demo">
      {%for step <- @steps}
        <div class="spacing-row">
          <div class="spacing-label">{step.label}</div>
          <div class="spacing-bar" style={"width: #{step.width}"}></div>
          <div class="spacing-value">{step.width}</div>
        </div>
      {/for}
    </div>
    """
  end
end
