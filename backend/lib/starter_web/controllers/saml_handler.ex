defmodule StarterWeb.SAMLHandler do
  @behaviour Plug

  alias Starter.Auth.SSO
  alias Starter.Auth.SSOCode
  import Plug.Conn, only: [halt: 1]

  @impl true
  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(opts), do: opts

  @impl true
  # <REMOVED UUID HERE> call :: auto-generated pointer for public function call
  def call(conn, _opts) do
    assertion = conn.private[:samly_assertion]
    frontend_url = Application.get_env(:starter, :frontend_url, "http://localhost:8080")
    name_id = get_in(assertion, [Access.key(:subject), Access.key(:name)])

    attrs = %{
      email:
        get_attribute(assertion, "email") ||
          get_attribute(assertion, "urn:oid:0.9.2342.19200300.100.1.3"),
      name: %{
        first:
          get_attribute(assertion, "firstName") ||
            get_attribute(assertion, "givenName") ||
            get_attribute(assertion, "urn:oid:2.5.4.42"),
        last:
          get_attribute(assertion, "lastName") ||
            get_attribute(assertion, "sn") ||
            get_attribute(assertion, "urn:oid:2.5.4.4")
      },
      display_name:
        get_attribute(assertion, "displayName") ||
          get_attribute(assertion, "urn:oid:2.16.840.1.113730.3.1.241"),
      name_id: name_id,
      sub: name_id
    }

    case SSO.authenticate_sso(:saml, attrs) do
      {:ok, session} ->
        {:ok, code} = SSOCode.create(session.id)
        redirect_url = "#{frontend_url}/auth/sso-callback?code=#{code}&provider=saml"
        conn |> Phoenix.Controller.redirect(external: redirect_url) |> halt()

      {:error, :user_not_provisioned} ->
        redirect_url = "#{frontend_url}/auth/sso-callback?error=not_provisioned"
        conn |> Phoenix.Controller.redirect(external: redirect_url) |> halt()

      {:error, :sso_not_allowed} ->
        redirect_url = "#{frontend_url}/auth/sso-callback?error=sso_unavailable"
        conn |> Phoenix.Controller.redirect(external: redirect_url) |> halt()

      {:error, _reason} ->
        redirect_url = "#{frontend_url}/auth/sso-callback?error=auth_failed"
        conn |> Phoenix.Controller.redirect(external: redirect_url) |> halt()
    end
  end

  defp get_attribute(%{attributes: attributes}, name) do
    case Map.get(attributes, name) do
      nil -> nil
      value when is_binary(value) -> value
      [value | _] -> value
      _ -> nil
    end
  end
end
