defmodule StarterWeb.Hologram.Components.InputField do
  @moduledoc "StyleGuideInputField / sg-field."
  use Hologram.Component

  prop :id, :string
  prop :label, :string
  prop :name, :string, default: nil
  prop :type, :string, default: "text"
  prop :value, :string, default: ""
  prop :placeholder, :string, default: nil

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="sg-field">
      <label for={@id}>{@label}</label>
      <input id={@id} name={@name || @id} type={@type} value={@value} placeholder={@placeholder} />
    </div>
    """
  end
end
