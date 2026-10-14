defmodule StarterWeb.Hologram.Components.ButtonRow do
  use Hologram.Component
  prop :class, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class={"button-row #{@class}"}><slot /></div>
    """
  end
end
