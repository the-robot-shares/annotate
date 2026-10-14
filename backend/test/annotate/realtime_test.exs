defmodule Annotate.RealtimeTest do
  @moduledoc """
  Pure topic-hashing tests for `Annotate.Realtime` (no DB, no socket).
  """

  use ExUnit.Case, async: true

  describe "page_hash/1" do
    test "sha256 lowercase hex — parity vector pins the algorithm" do
      # PARITY VECTOR: the widget and any other client must derive the exact
      # same topic hash. sha256("phase5-parity-vector"), lowercase hex.
      assert Annotate.Realtime.page_hash("phase5-parity-vector") ==
               "63b1124d51c9c48fe33623ab2755b4959deaf5bdb2d4426a002c24ddb52b17f5"
    end

    test "always 64 lowercase hex chars" do
      for page_key <- ["/p/1", "", String.duplicate("x", 10_000), "/p/ünïcode"] do
        hash = Annotate.Realtime.page_hash(page_key)
        assert String.length(hash) == 64
        assert hash =~ ~r/^[0-9a-f]{64}$/
      end
    end
  end

  describe "page_topic/2" do
    test "formats as page:<slug>:<hash>" do
      assert Annotate.Realtime.page_topic("acme", "/products/42") ==
               "page:acme:" <> Annotate.Realtime.page_hash("/products/42")
    end
  end
end
