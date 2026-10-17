defmodule AnnotateWeb.Plugs.SsoSession do
  @moduledoc """
  The short-lived `_annotate_sso` flow cookie (OAuth/OIDC `state`, `nonce`,
  stashed invite): host-only, `SameSite=Lax` (the IdP redirect back is a
  top-level GET), 900 s, and `Secure` when `:secure_cookies` is set (prod).

  A module plug (rather than inline `Plug.Session` opts in the router) so the
  `Secure` flag is read from runtime config.
  """

  @behaviour Plug

  @impl true
  def init(_opts) do
    Plug.Session.init(
      store: :cookie,
      key: "_annotate_sso",
      signing_salt: "sso_session_salt",
      same_site: "Lax",
      max_age: 900,
      secure: Application.get_env(:annotate, :secure_cookies, false)
    )
  end

  @impl true
  def call(conn, opts), do: Plug.Session.call(conn, opts)
end
