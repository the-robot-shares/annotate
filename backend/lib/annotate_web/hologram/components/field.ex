defmodule AnnotateWeb.Hologram.Components.Field do
  @moduledoc """
  Form field chrome matching start-app `sg-field` + HUI field tokens.

  Use synchronized bindings from the parent page; this component is presentational
  when used with named inputs inside a form `$submit`.
  """
  use Hologram.Component

  prop :id, :string
  prop :label, :string
  prop :name, :string, default: nil
  prop :type, :string, default: "text"
  prop :value, :string, default: ""
  prop :required, :boolean, default: false
  prop :autocomplete, :string, default: nil
  prop :placeholder, :string, default: nil

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-field">
      <label for={@id}>{@label}</label>
      <input
        id={@id}
        name={@name || @id}
        type={@type}
        value={@value}
        required={@required}
        autocomplete={@autocomplete}
        placeholder={@placeholder}
      />
      <slot />
    </div>
    """
  end
end
