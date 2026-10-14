defmodule StarterWeb.Hologram.Components.TokenCard do
  @moduledoc "StyleGuideTokenCard — `tokens` is list of `%{name, value}`."
  use Hologram.Component

  prop :title, :string, default: ""
  prop :tokens, :list, default: []

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="token-card">
      <div class="token-card-title">{@title}</div>
      {%for tok <- @tokens}
        <div class="token-row">
          <span class="token-name">{tok.name}</span>
          <span class="token-value">{tok.value}</span>
        </div>
      {/for}
    </div>
    """
  end
end
