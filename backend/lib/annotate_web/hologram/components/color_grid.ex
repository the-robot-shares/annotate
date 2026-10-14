defmodule StarterWeb.Hologram.Components.ColorGrid do
  use Hologram.Component
  prop :class, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class={"swatch-row #{@class}"}><slot /></div>
    """
  end
end
