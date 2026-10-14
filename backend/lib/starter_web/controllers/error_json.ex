defmodule StarterWeb.ErrorJSON do
  # <REMOVED UUID HERE> render :: auto-generated pointer for public function render
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
