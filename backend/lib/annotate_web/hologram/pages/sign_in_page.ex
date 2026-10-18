defmodule AnnotateWeb.Hologram.Pages.SignInPage do
  @moduledoc """
  `/sign-in`: full-page GitHub / Google sign-in (the navbar modal is the usual
  path; this is the direct-entry and redirect target for `RequireAuth`,
  `/login`, `/signup`, and failed callbacks). The dashboard is invite-only;
  invite links land on `/sign-up?invite=…` (`SignUpPage`).
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias AnnotateWeb.Hologram.Components.ProviderButtons
  alias AnnotateWeb.Hologram.Layouts.AuthLayout

  route "/sign-in"
  layout AuthLayout, page_title: "Sign in — annotate"

  # `?return_to=` (MCP OAuth: `/oauth/authorize?login_state=…`) survives the
  # provider round trip; only a same-origin path is kept (ReturnTo.safe/1).
  def init(_params, component, server) do
    return_to =
      server |> Map.get(:query, %{}) |> query_value("return_to") |> AnnotateWeb.ReturnTo.safe()

    put_state(component,
      providers: ProviderButtons.providers(),
      signed_in: Auth.current_user(server) != nil,
      return_to: return_to || "",
      continue_path: return_to || "/dashboard"
    )
  end

  defp query_value(query, key) when is_map(query),
    do: Map.get(query, key) || Map.get(query, String.to_atom(key))

  defp query_value(_, _), do: nil

  def template do
    ~HOLO"""
    <div class="nd-auth" data-cy="sign-in-page">
      <h1 class="nd-auth__title">Sign in to annotate</h1>
      <p class="nd-auth__muted">
        Site owners sign in with GitHub or Google; we use your account's verified email.
        From the dashboard you can add a site, copy its embed snippet, and answer comments.
      </p>
      {%if @signed_in}
        <p><a class="nd-btn nd-btn--primary" href={@continue_path} data-cy="sign-in-dashboard">{%if @return_to != ""}Continue{%else}Go to your dashboard{/if}</a></p>
      {%else}
        <ProviderButtons providers={@providers} return_to={@return_to} />
      {/if}
      <p class="nd-auth__note" data-cy="sign-in-invite-only">
        annotate is invite-only. Have an invite link? Open it to sign up.
        No invite yet? <a href="/#waitlist">Join the waitlist</a>.
      </p>
      <p class="nd-auth__note" data-cy="sign-in-legal">By continuing you agree to the <a href="/terms">Terms of Service</a> and <a href="/privacy">Privacy Policy</a>.</p>
    </div>
    """
  end
end
