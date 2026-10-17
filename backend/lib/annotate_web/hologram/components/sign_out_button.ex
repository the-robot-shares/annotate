defmodule AnnotateWeb.Hologram.Components.SignOutButton do
  @moduledoc "Dashboard sign-out: clears the Hologram session, then navigates to `/`."

  use Hologram.Component
  use Hologram.JS

  alias Annotate.Hologram.Auth

  def init(_props, component, _server), do: component

  def template do
    ~HOLO"""
    <button type="button" class="dsh-btn dsh-btn--ghost dsh-btn--sm" $click={:logout} data-cy="dsh-sign-out">Sign out</button>
    """
  end

  def action(:logout, _params, component), do: put_command(component, :logout)

  def action(:logged_out, _params, component) do
    location = JS.get(:window, :location)
    JS.call(location, :assign, ["/"])
    component
  end

  def command(:logout, _params, server) do
    server
    |> Auth.logout()
    |> put_action(:logged_out)
  end
end
