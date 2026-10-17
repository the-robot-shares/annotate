defmodule AnnotateWeb.AnnotateAPI.DevLoginTest do
  use ExUnit.Case, async: true

  # The devbox "log in as" route must exist ONLY in :dev builds. Router
  # introspection + module presence, so this holds without a prod build.
  @paths ["/embed/dev-login"]

  test "dev-login routes and controller are absent outside :dev" do
    routes = Enum.map(AnnotateWeb.Router.__routes__(), & &1.path)

    if Mix.env() == :dev do
      assert Enum.all?(@paths, &(&1 in routes))
      assert Code.ensure_loaded?(AnnotateWeb.AnnotateAPI.DevLoginController)
    else
      assert Mix.env() in [:test, :prod]
      refute Enum.any?(@paths, &(&1 in routes))
      refute Code.ensure_loaded?(AnnotateWeb.AnnotateAPI.DevLoginController)
    end
  end
end
