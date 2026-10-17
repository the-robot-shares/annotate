defmodule Annotate.Config.RuntimeGithubTest do
  @moduledoc """
  Evaluates config/runtime.exs as :prod (dummy values only) and pins the
  Ueberauth providers shape. Regression for the 2026-10-17 prod 500: a bad
  binding made `providers` the GitHub client-id STRING ("" when unset).
  """
  use ExUnit.Case, async: false

  @prod_env %{
    "DATABASE_URL" => "ecto://u:p@localhost/db",
    "SECRET_KEY_BASE" => String.duplicate("k", 64),
    "SESSION_SIGNING_SALT" => "test-salt",
    "ANNOTATE_JWT_SECRET" => "test-jwt",
    "ANNOTATE_KEY_ENC_SECRET" => "test-enc",
    "GUARDIAN_SECRET_KEY" => String.duplicate("g", 40),
    "PHX_HOST" => "example.test"
  }

  defp read_prod(extra) do
    vars = Map.merge(@prod_env, extra)
    saved = Map.new(vars, fn {k, _} -> {k, System.get_env(k)} end)
    Enum.each(vars, fn {k, v} -> System.put_env(k, v) end)

    try do
      Config.Reader.read!(Path.expand("../../../config/runtime.exs", __DIR__),
        env: :prod,
        target: :host
      )
    after
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end
  end

  test "no GitHub creds → providers is an empty LIST, GitHub not enabled" do
    c =
      read_prod(%{
        "GITHUB_CLIENT_ID" => "",
        "GITHUB_CLIENT_SECRET" => "",
        "GOOGLE_CLIENT_ID" => "",
        "GOOGLE_CLIENT_SECRET" => ""
      })

    assert c[:ueberauth][Ueberauth][:providers] == []
    refute c[:annotate][:github_enabled]
  end

  test "Google creds → google strategy registered + enabled (and blanks stay off)" do
    c =
      read_prod(%{
        "GOOGLE_CLIENT_ID" => "test-gid",
        "GOOGLE_CLIENT_SECRET" => "test-gsecret",
        "GITHUB_CLIENT_ID" => "",
        "GITHUB_CLIENT_SECRET" => ""
      })

    assert [google: {Ueberauth.Strategy.Google, _}] = c[:ueberauth][Ueberauth][:providers]
    assert c[:annotate][:google_enabled] == true

    c =
      read_prod(%{
        "GOOGLE_CLIENT_ID" => " ",
        "GOOGLE_CLIENT_SECRET" => "",
        "GITHUB_CLIENT_ID" => "",
        "GITHUB_CLIENT_SECRET" => ""
      })

    assert c[:ueberauth][Ueberauth][:providers] == []
    refute c[:annotate][:google_enabled]
  end

  test "GitHub creds → github strategy registered + enabled" do
    c =
      read_prod(%{
        "GITHUB_CLIENT_ID" => "test-id",
        "GITHUB_CLIENT_SECRET" => "test-secret",
        "GOOGLE_CLIENT_ID" => "",
        "GOOGLE_CLIENT_SECRET" => ""
      })

    assert [github: {Ueberauth.Strategy.Github, _}] = c[:ueberauth][Ueberauth][:providers]
    assert c[:annotate][:github_enabled] == true
  end
end
