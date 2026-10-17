defmodule AnnotateWeb.Hologram.Components.GithubAuth do
  @moduledoc """
  Navbar "Sign in" / "Sign up" triggers + the tobor-kit `<noizu-auth>` modal in
  **provider-redirect mode** (`redirect-providers="github"`): GitHub is the only
  dashboard sign-in (`Annotate.Auth.LoginMethods`), and the GitHub button is a
  same-origin top-level redirect to `/auth/github` (server-side OAuth). Sign-up
  and sign-in are the same round trip; the first sign-in creates the account.

  The modal (centred dialog, backdrop, title per flow, close ×, Esc,
  click-outside, focus trap + return, scroll lock, `aria-modal`) is the kit's;
  the buttons open it declaratively (`aria-controls` + `data-auth-open`), so no
  host JavaScript runs. Night Desk styling comes from the kit's `--auth-*`
  custom properties (css/app.css, css/landing.css). Titles are set by the
  CSP-safe `/js/annotate-auth.js`. Until GitHub credentials are deployed the
  provider renders "not configured" (`unavailable-providers`).

  Stateful (needs a `cid`): `configured` and the CDN `src` are read
  server-side. `variant`: `"sg"` (style-guide buttons) or `"nd"` (Night Desk).
  """

  use Hologram.Component

  alias Annotate.Auth.LoginMethods

  prop :variant, :string, default: "sg"

  @dialog_id "annotate-auth"

  def init(_props, component, _server) do
    put_state(component,
      unavailable: if(LoginMethods.github_configured?(), do: "", else: "github"),
      src: kit_src(),
      dialog_id: @dialog_id
    )
  end

  def template do
    ~HOLO"""
    <div class="sg-auth" data-cy="github-auth">
      <button type="button" class={trigger_class(@variant, "secondary")} aria-controls={@dialog_id} aria-haspopup="dialog" data-auth-open="login" data-cy="github-auth-signin">Sign in</button>
      <button type="button" class={trigger_class(@variant, "primary")} aria-controls={@dialog_id} aria-haspopup="dialog" data-auth-open="signup" data-cy="github-auth-signup">Sign up</button>
      <noizu-auth id={@dialog_id} class={"annotate-auth annotate-auth--" <> @variant} mode="modal" backdrop-close redirect-providers="github" redirect-base="/auth" unavailable-providers={@unavailable} data-annotate-auth></noizu-auth>
      <script type="module" src={@src}></script>
      <script type="module" src="/js/annotate-auth.js"></script>
    </div>
    """
  end

  @doc "The kit's `noizu-auth` bundle, pinned to the same CDN sha as the comment widget."
  def kit_src do
    widget =
      Keyword.get(
        Application.get_env(:annotate, :marketing) || [],
        :widget_src,
        "https://cdn.derobot.is/tobor-kit/sha-0e5a20e04fefcb400f9f395795c438a7312f27ec/components/page-comments/page-comments.js"
      )

    String.replace(
      widget,
      "components/page-comments/page-comments.js",
      "components/auth/noizu-auth.js"
    )
  end

  defp trigger_class("nd", "primary"), do: "nd-btn nd-btn--primary nd-btn--sm"
  defp trigger_class("nd", _), do: "nd-btn nd-btn--secondary nd-btn--sm"
  defp trigger_class(_, "primary"), do: "btn btn-black btn-sm"
  defp trigger_class(_, _), do: "btn btn-outline btn-sm"
end
