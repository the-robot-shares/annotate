defmodule StarterWeb.Hologram.Components.CardGrid do
  use Hologram.Component
  prop :class, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class={"card-grid #{@class}"}><slot /></div>
    """
  end
end
