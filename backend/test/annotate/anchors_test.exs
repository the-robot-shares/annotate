defmodule Annotate.AnchorsTest do
  use ExUnit.Case, async: true
  alias Annotate.Anchors

  test "parse_url decomposes url into stored page context" do
    ctx =
      Anchors.parse_url("https://Good.example:8443/docs/intro/?b=2&a=1&a=0&utm_source=x#sec-3")

    assert ctx["origin"] == "https://good.example:8443"
    assert ctx["page_path"] == "/docs/intro"
    assert ctx["query_string"] == "b=2&a=1&a=0&utm_source=x"
    assert ctx["query_params"] == %{"a" => ["0", "1"], "b" => "2", "utm_source" => "x"}
    assert ctx["hash"] == "sec-3"
    assert Anchors.parse_url("javascript:alert(1)") == nil
  end

  test "deep-link token is not stored as page hash; deep_link replaces fragment" do
    assert Anchors.parse_url("https://a.example/p#annotate=abc")["hash"] == nil

    assert Anchors.deep_link("https://a.example/p?x=1#old", "t1") ==
             "https://a.example/p?x=1#annotate=t1"

    assert Anchors.deep_link(nil, "t1") == nil
  end

  test "normalize_path" do
    assert Anchors.normalize_path("") == "/"
    assert Anchors.normalize_path("/a/b/") == "/a/b"
    assert Anchors.normalize_path("a") == "/a"
  end

  test "query matching is order-insensitive, honours ignore globs and allow-list, legacy nil matches all" do
    t = %{"a" => "1", "b" => "2", "utm_source" => "x"}
    default = %{}
    assert Anchors.query_match?(t, %{"b" => "2", "a" => "1", "utm_source" => "x"}, default)
    refute Anchors.query_match?(t, %{"a" => "1", "b" => "2"}, default)

    ignore = %{"ignore_query_params" => ["utm_*", "fbclid"]}
    assert Anchors.query_match?(t, %{"a" => "1", "b" => "2", "fbclid" => "z"}, ignore)
    refute Anchors.query_match?(t, %{"a" => "9", "b" => "2"}, ignore)

    allow = %{"significant_query_params" => ["a"]}
    assert Anchors.query_match?(t, %{"a" => "1", "zzz" => "q"}, allow)

    assert Anchors.query_match?(nil, %{"anything" => "1"}, default)
  end
end
