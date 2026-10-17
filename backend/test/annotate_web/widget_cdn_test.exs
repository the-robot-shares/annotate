defmodule AnnotateWeb.WidgetCdnTest do
  use ExUnit.Case, async: true

  alias AnnotateWeb.WidgetCdn

  test "pinned and latest loaders live under the tobor-kit semver paths" do
    assert WidgetCdn.version() =~ ~r/^\d+\.\d+\.\d+$/

    assert WidgetCdn.pinned_src() ==
             "https://cdn.derobot.is/tobor-kit/v#{WidgetCdn.version()}/annotate.js"

    assert WidgetCdn.latest_src() == "https://cdn.derobot.is/tobor-kit/latest/annotate.js"
  end

  test "config defaults pin the same release as WidgetCdn" do
    # config.exs / runtime.exs cannot call the module; keep the literals in step.
    for file <- ["config/config.exs", "config/runtime.exs"] do
      assert File.read!(file) =~ WidgetCdn.pinned_src(),
             "#{file} must pin #{WidgetCdn.pinned_src()}"
    end
  end

  test "auth_src derives noizu-auth from either widget entry form" do
    auth = "https://cdn.derobot.is/tobor-kit/v1.0.1/components/auth/noizu-auth.js"
    assert WidgetCdn.auth_src("https://cdn.derobot.is/tobor-kit/v1.0.1/annotate.js") == auth

    assert WidgetCdn.auth_src(
             "https://cdn.derobot.is/tobor-kit/v1.0.1/components/page-comments/page-comments.js"
           ) == auth
  end
end
