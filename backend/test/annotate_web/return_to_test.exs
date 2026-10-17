defmodule AnnotateWeb.ReturnToTest do
  use ExUnit.Case, async: false

  alias AnnotateWeb.ReturnTo

  setup do
    prev = Application.get_env(:annotate, :mcp)

    Application.put_env(
      :annotate,
      :mcp,
      Keyword.put(prev || [], :issuer, "https://annotate.test")
    )

    on_exit(fn -> Application.put_env(:annotate, :mcp, prev) end)
  end

  test "same-origin relative paths are kept (with query)" do
    assert ReturnTo.safe("/oauth/authorize?login_state=abc") == "/oauth/authorize?login_state=abc"
    assert ReturnTo.safe("/dashboard") == "/dashboard"
  end

  test "absolute URLs on the issuer origin reduce to their path" do
    assert ReturnTo.safe("https://annotate.test/oauth/authorize?login_state=x") ==
             "/oauth/authorize?login_state=x"

    assert ReturnTo.safe("https://ANNOTATE.test/dashboard") == "/dashboard"
  end

  test "open-redirect shapes are rejected" do
    for bad <- [
          "//evil.test/x",
          "/\\evil.test",
          "https://evil.test/oauth/authorize",
          "https://annotate.test.evil.test/x",
          "http://annotate.test/x",
          "https://annotate.test:8443/x",
          "https://user@annotate.test/x",
          "javascript:alert(1)",
          "data:text/html,x",
          "oauth/authorize",
          "/x\n/y",
          "/x y",
          "/x#frag",
          "",
          nil,
          123,
          "/" <> String.duplicate("a", 3000)
        ] do
      assert ReturnTo.safe(bad) == nil, "expected #{inspect(bad)} to be rejected"
    end
  end
end
