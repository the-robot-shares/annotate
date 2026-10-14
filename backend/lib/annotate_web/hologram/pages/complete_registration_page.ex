defmodule AnnotateWeb.Hologram.Pages.CompleteRegistrationPage do
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Schema.Users.User, as: UserSchema
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth
  alias AnnotateWeb.Hologram.Pages.AppHomePage
  alias AnnotateWeb.Hologram.Pages.InviteRequiredPage

  route "/complete-registration"
  layout MainLayout, page_title: "Complete registration"
  # Profile completion stays reachable for invite-gated users (decision 3).
  middleware RequireAuth, invite: :exempt

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    user = Auth.current_user(server)

    put_state(component,
      user: user,
      user_name: user[:user_name] || "",
      first_name: "",
      last_name: "",
      mobile_phone: user[:mobile_phone] || "",
      invite_token: "",
      error: nil,
      loading: false
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="content">
      <h1 class="sg-page-title">Complete registration</h1>
      <p class="sg-page-intro">Finish your profile to continue.</p>

      <form class="sg-form" $submit.prevent_default={:submit}>
        {%if @error}
          <p class="sg-error" role="alert">{@error}</p>
        {/if}
        <div class="sg-field">
          <label for="cr-username">Username</label>
          <input id="cr-username" type="text" value={@user_name} required $change={:set_user_name} />
        </div>
        <div class="sg-field">
          <label for="cr-first">First name</label>
          <input id="cr-first" type="text" value={@first_name} required $change={:set_first_name} />
        </div>
        <div class="sg-field">
          <label for="cr-last">Last name</label>
          <input id="cr-last" type="text" value={@last_name} required $change={:set_last_name} />
        </div>
        <div class="sg-field">
          <label for="cr-phone">Mobile phone</label>
          <input id="cr-phone" type="tel" value={@mobile_phone} required $change={:set_mobile_phone} />
        </div>
        <div class="sg-field">
          <label for="cr-invite">Invite code (optional)</label>
          <input id="cr-invite" type="text" value={@invite_token} $change={:set_invite_token} />
        </div>
        <button type="submit" class="btn btn-black" disabled={@loading}>
          {%if @loading}Saving...{%else}Continue{/if}
        </button>
      </form>
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_user_name, p, c), do: put_state(c, :user_name, p.event.value)
  def action(:set_first_name, p, c), do: put_state(c, :first_name, p.event.value)
  def action(:set_last_name, p, c), do: put_state(c, :last_name, p.event.value)
  def action(:set_mobile_phone, p, c), do: put_state(c, :mobile_phone, p.event.value)
  def action(:set_invite_token, p, c), do: put_state(c, :invite_token, p.event.value)

  def action(:submit, _params, component) do
    component
    |> put_state(loading: true, error: nil)
    |> put_command(:complete,
      user_name: component.state.user_name,
      first_name: component.state.first_name,
      last_name: component.state.last_name,
      mobile_phone: component.state.mobile_phone,
      invite_token: component.state.invite_token
    )
  end

  def action(:completed, params, component) do
    page =
      case Auth.post_auth_path(params.user) do
        "/auth/invite-required" -> InviteRequiredPage
        _ -> AppHomePage
      end

    component
    |> put_state(loading: false)
    # Dashboard, or the invite interstitial while still gated
    |> put_page(page)
  end

  def action(:complete_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Could not complete registration")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:complete, params, server) do
    case Auth.current_user(server) do
      nil ->
        put_action(server, :complete_failed, error: "Not signed in")

      user ->
        schema = Annotate.Repo.get!(UserSchema, user.id)

        attrs = %{
          user_name: params.user_name,
          handle: params.user_name,
          mobile_phone: params.mobile_phone,
          profile_completed_at: DateTime.utc_now()
        }

        # Redeem and profile save share one transaction: a failed redeem must
        # not leave a half-completed profile behind (and vice versa).
        result =
          Annotate.Repo.transaction(fn ->
            with {:ok, activated} <- maybe_redeem(server, params, schema),
                 {:ok, updated} <-
                   activated |> UserSchema.changeset(attrs) |> Annotate.Repo.update() do
              updated
            else
              {:error, reason} -> Annotate.Repo.rollback(reason)
            end
          end)

        case result do
          {:ok, updated} ->
            put_action(server, :completed, user: Auth.serialize_user(updated))

          {:error, %Ecto.Changeset{} = changeset} ->
            put_action(server, :complete_failed, error: inspect(changeset.errors))

          {:error, code} ->
            put_action(server, :complete_failed, error: Auth.invite_error_message(code))
        end
    end
  end

  # The optional invite field redeems in place (a valid code activates a gated
  # account); blank keeps the profile save only. Returns the refreshed schema
  # row so the caller's profile update continues from the activated state.
  defp maybe_redeem(server, params, schema) do
    case Map.get(params, :invite_token) do
      token when is_binary(token) and token != "" ->
        case Auth.redeem_invite(server, token) do
          {:ok, _serialized} -> {:ok, Annotate.Repo.get!(UserSchema, schema.id)}
          error -> error
        end

      _ ->
        {:ok, schema}
    end
  end
end
