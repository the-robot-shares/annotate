defmodule AnnotateWeb.Hologram.Components.ProviderButtons do
  @moduledoc """
  Full-page GitHub / Google buttons for `/sign-in` and `/sign-up` (the navbar
  path is the tobor-kit modal). `invite` (raw token from the invite link) is
  appended as `?invite=` so it survives the OAuth round trip in the signed
  SSO flow cookie (`SSOController.prepare_oauth/2`). Stateless; `providers`
  is `[%{id, label, configured}]` computed by the page.
  """

  use Hologram.Component

  prop :providers, :list, default: []
  prop :invite, :string, default: ""
  # Same-origin post-sign-in path (already validated by the page with
  # AnnotateWeb.ReturnTo.safe/1); rides `?return_to=` into prepare_oauth.
  prop :return_to, :string, default: ""

  def template do
    ~HOLO"""
    <div class="sg-auth__providers" data-cy="provider-buttons">
      {%for p <- @providers}
        {%if p.configured}
          <p><a class="btn btn-black" href={href(p.id, @invite, @return_to)} data-cy={"sign-in-" <> p.id}>{p.label}</a></p>
        {%else}
          <p><button type="button" class="btn btn-black" disabled aria-disabled="true">{p.label}</button></p>
          <p class="sg-auth__note" role="status" data-cy={"sign-in-unconfigured-" <> p.id}>{p.name} sign-in is not configured yet.</p>
        {/if}
      {/for}
    </div>
    """
  end

  def href(id, invite), do: href(id, invite, "")

  def href(id, invite, return_to) do
    params =
      [{"invite", invite}, {"return_to", return_to}]
      |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
      |> Enum.map(fn {k, v} -> k <> "=" <> URI.encode_www_form(v) end)

    case params do
      [] -> "/auth/" <> id
      _ -> "/auth/" <> id <> "?" <> Enum.join(params, "&")
    end
  end

  @doc "Provider rows for the configured dashboard login methods."
  def providers do
    unconfigured = Annotate.Auth.LoginMethods.unconfigured_providers()

    Enum.map(Annotate.Auth.LoginMethods.dashboard_providers(), fn id ->
      name = if id == "github", do: "GitHub", else: "Google"
      %{id: id, name: name, label: "Continue with " <> name, configured: id not in unconfigured}
    end)
  end
end
