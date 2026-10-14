defmodule StarterWeb.Hologram.Components.Card do
  @moduledoc "StyleGuideCard — optional href makes the whole card a link."
  use Hologram.Component

  prop :variant, :string, default: nil
  prop :title, :string, default: nil
  prop :body, :string, default: nil
  prop :id_label, :string, default: nil
  prop :href, :string, default: nil

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    {%if @href}
      <a href={@href} class={card_class(@variant, true)}>
        {%if @id_label}<div class="card-id">{@id_label}</div>{/if}
        {%if @title}<div class="card-title">{@title}</div>{/if}
        {%if @body}<div class="card-body">{@body}</div>{/if}
        <slot />
      </a>
    {%else}
      <div class={card_class(@variant, false)}>
        {%if @id_label}<div class="card-id">{@id_label}</div>{/if}
        {%if @title}<div class="card-title">{@title}</div>{/if}
        {%if @body}<div class="card-body">{@body}</div>{/if}
        <slot />
      </div>
    {/if}
    """
  end

  # <REMOVED UUID HERE> card_class :: auto-generated pointer for public function card_class
  def card_class(nil, true), do: "card card--link"
  def card_class("", true), do: "card card--link"
  def card_class(v, true) when is_binary(v), do: "card card-#{v} card--link"
  def card_class(nil, _), do: "card"
  def card_class("", _), do: "card"
  def card_class(v, _), do: "card card-#{v}"
end
