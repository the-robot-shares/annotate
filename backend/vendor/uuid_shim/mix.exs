defmodule UuidShim.MixProject do
  use Mix.Project

  # Shim for the OTP app `:uuid`.
  #
  # WHY THIS EXISTS
  # ---------------
  # `hologram ~> 0.10` depends on the hex package `uuid` (OTP app `:uuid`,
  # zyro/elixir-uuid 1.1.8). Our noizu libs (genai, genai_core, seed_helper,
  # smart_token, noizu_labs_entities) depend on the *renamed* hex package
  # `elixir_uuid` (OTP app `:elixir_uuid`, zyro/elixir-uuid 1.2.1).
  #
  # They are the SAME library under two package names, and BOTH define the
  # module `Elixir.UUID`. `mix compile` tolerates the collision; `mix release`
  # aborts with:
  #   ** (Mix) Duplicated modules: 'Elixir.UUID' specified in elixir_uuid and uuid
  #
  # `hex:` remapping does not work in either direction — Mix rejects it with
  # "Conflicting OTP application names" because the remap redirects the package
  # but not the OTP application name. Do not retry that.
  #
  # WHAT THIS DOES
  # --------------
  # This project provides an OTP app literally named `:uuid` that ships ZERO
  # modules and simply depends on `:elixir_uuid`. hologram's `{:uuid, "~> 1.0"}`
  # requirement and its `applications: [..., :uuid, ...]` entry are both
  # satisfied, `Elixir.UUID` is compiled exactly once (by :elixir_uuid 1.2.1,
  # which is a strict superset of 1.1.8), and the release assembles.
  #
  # If you remove this, `MIX_ENV=prod mix release` will start failing again.
  def project do
    [
      app: :uuid,
      version: "1.1.8",
      elixir: "~> 1.14",
      deps: [{:elixir_uuid, "~> 1.2"}]
    ]
  end

  def application do
    # Pure library app, exactly like the real :uuid / :elixir_uuid packages.
    [extra_applications: [], applications: [:elixir_uuid]]
  end
end
