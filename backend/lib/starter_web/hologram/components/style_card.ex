defmodule StarterWeb.Hologram.Components.StyleCard do
  @moduledoc "StyleGuideStyleCard — documentation card for principles / notes."
  use Hologram.Component

  prop :title, :string, default: ""
  prop :body, :string, default: ""

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="style-card card">
      <div class="card-title">{@title}</div>
      <div class="card-body">{@body}</div>
      <slot />
    </div>
    """
  end
end
