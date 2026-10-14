defmodule StarterWeb.Plugs.Session do
  @moduledoc """
  `Plug.Session` with a boot-time signing salt.

  The salt lives in app config (`config/runtime.exs`): the
  `SESSION_SIGNING_SALT` env var when set, otherwise a strong random value
  generated per boot in dev/test. With `:plug_init_mode, :runtime`
  (config.exs), `init/1` runs when the endpoint serves rather than when it
  compiles, so the salt is never baked into a compiled artifact and no
  literal salt is committed.

  In :prod the variable is REQUIRED — runtime.exs raises when it is missing.
  In dev/test sessions do not survive a restart when the random fallback
  fires; that is intentional — do not "fix" it by committing a literal salt.
  """

  @behaviour Plug

  @impl true
  def init(_opts) do
    signing_salt =
      :starter
      |> Application.fetch_env!(StarterWeb.Endpoint)
      |> Keyword.fetch!(:session_signing_salt)

    Plug.Session.init(
      store: :cookie,
      key: "_starter_key",
      signing_salt: signing_salt,
      same_site: "Lax"
    )
  end

  @impl true
  def call(conn, opts), do: Plug.Session.call(conn, opts)
end
