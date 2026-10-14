defmodule AnnotateWeb.Hologram.Pages.ProfilePage do
  @moduledoc "User profile + password change (`/app/profile`)."
  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Schema.Users.User, as: UserSchema
  alias AnnotateWeb.Hologram.Components.AppShell
  alias AnnotateWeb.Hologram.Layouts.MainLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/app/profile"
  layout MainLayout, page_title: "Profile"
  # Profile/settings stay reachable for invite-gated users (decision 3).
  middleware RequireAuth, invite: :exempt

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, server) do
    {user, organizations} = Auth.current_user_and_orgs(server)

    put_state(component,
      user: user,
      organizations: normalize_orgs(organizations || []),
      user_name: user[:user_name] || user["user_name"] || "",
      mobile_phone: user[:mobile_phone] || user["mobile_phone"] || "",
      message: nil,
      error: nil,
      loading: false,
      current_password: "",
      new_password: "",
      confirm_password: "",
      password_message: nil,
      password_error: nil,
      password_loading: false
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <AppShell user={@user} organizations={@organizations} active="profile" title="Profile">
      <p class="sg-page-intro">{@user.email}</p>

      {%if @message}
        <p class="app-flash" role="status">{@message}</p>
      {/if}
      {%if @error}
        <p class="sg-error" role="alert">{@error}</p>
      {/if}

      <section class="app-dash-panel" style="margin-bottom: var(--space-4)">
        <h2 class="app-dash-panel__title">Profile</h2>
        <div class="app-dash-panel__body">
          <form class="sg-form" $submit.prevent_default={:save}>
            <div class="sg-field">
              <label for="profile-username">Username</label>
              <input id="profile-username" type="text" value={@user_name} $change={:set_user_name} />
            </div>
            <div class="sg-field">
              <label for="profile-phone">Mobile phone</label>
              <input id="profile-phone" type="tel" value={@mobile_phone} $change={:set_mobile_phone} />
            </div>
            <button type="submit" class="btn btn-black" disabled={@loading}>
              {%if @loading}Saving...{%else}Save{/if}
            </button>
          </form>
        </div>
      </section>

      <section class="app-dash-panel" id="settings">
        <h2 class="app-dash-panel__title">Change password</h2>
        <div class="app-dash-panel__body">
          {%if @password_message}
            <p class="app-flash" role="status">{@password_message}</p>
          {/if}
          {%if @password_error}
            <p class="sg-error" role="alert">{@password_error}</p>
          {/if}
          <form class="sg-form" $submit.prevent_default={:change_password}>
            <div class="sg-field">
              <label for="profile-current-password">Current password</label>
              <input
                id="profile-current-password"
                type="password"
                value={@current_password}
                required
                autocomplete="current-password"
                $change={:set_current_password}
              />
            </div>
            <div class="sg-field">
              <label for="profile-new-password">New password</label>
              <input
                id="profile-new-password"
                type="password"
                value={@new_password}
                required
                minlength="8"
                autocomplete="new-password"
                $change={:set_new_password}
              />
            </div>
            <div class="sg-field">
              <label for="profile-confirm-password">Confirm new password</label>
              <input
                id="profile-confirm-password"
                type="password"
                value={@confirm_password}
                required
                minlength="8"
                autocomplete="new-password"
                $change={:set_confirm_password}
              />
            </div>
            <button type="submit" class="btn btn-black" disabled={@password_loading}>
              {%if @password_loading}Updating...{%else}Update password{/if}
            </button>
          </form>
        </div>
      </section>
    </AppShell>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_user_name, params, c), do: put_state(c, :user_name, params.event.value)
  def action(:set_mobile_phone, params, c), do: put_state(c, :mobile_phone, params.event.value)

  def action(:set_current_password, params, c),
    do: put_state(c, :current_password, params.event.value)

  def action(:set_new_password, params, c), do: put_state(c, :new_password, params.event.value)

  def action(:set_confirm_password, params, c),
    do: put_state(c, :confirm_password, params.event.value)

  def action(:save, _params, component) do
    component
    |> put_state(loading: true, error: nil, message: nil)
    |> put_command(:update_profile,
      user_name: component.state.user_name,
      mobile_phone: component.state.mobile_phone
    )
  end

  def action(:saved, params, component) do
    put_state(component, loading: false, message: "Profile saved.", user: params.user)
  end

  def action(:save_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Save failed")
  end

  def action(:change_password, _params, component) do
    cond do
      String.length(component.state.new_password || "") < 8 ->
        put_state(component, password_error: "Password must be at least 8 characters")

      component.state.new_password != component.state.confirm_password ->
        put_state(component, password_error: "Passwords do not match")

      true ->
        component
        |> put_state(password_loading: true, password_error: nil, password_message: nil)
        |> put_command(:update_password,
          current_password: component.state.current_password,
          new_password: component.state.new_password
        )
    end
  end

  def action(:password_updated, _params, component) do
    put_state(component,
      password_loading: false,
      password_message: "Password updated.",
      current_password: "",
      new_password: "",
      confirm_password: ""
    )
  end

  def action(:password_failed, params, component) do
    put_state(component,
      password_loading: false,
      password_error: params.error || "Could not update password"
    )
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:update_profile, params, server) do
    case Auth.current_user(server) do
      nil ->
        put_action(server, :save_failed, error: "Not signed in")

      user ->
        schema = Annotate.Repo.get!(UserSchema, user.id)

        attrs = %{
          user_name: params.user_name,
          handle: params.user_name,
          mobile_phone: params.mobile_phone
        }

        case schema |> UserSchema.changeset(attrs) |> Annotate.Repo.update() do
          {:ok, updated} ->
            put_action(server, :saved, user: Auth.serialize_user(updated))

          {:error, changeset} ->
            put_action(server, :save_failed, error: inspect(changeset.errors))
        end
    end
  end

  def command(:update_password, params, server) do
    case Auth.current_user(server) do
      nil ->
        put_action(server, :password_failed, error: "Not signed in")

      user ->
        case verify_and_update_password(user, params.current_password, params.new_password) do
          :ok ->
            put_action(server, :password_updated)

          {:error, :invalid_current_password} ->
            put_action(server, :password_failed, error: "Current password is incorrect")

          {:error, :credential_not_found} ->
            put_action(server, :password_failed, error: "No password credential on this account")

          {:error, reason} ->
            put_action(server, :password_failed, error: "Update failed (#{inspect(reason)})")
        end
    end
  end

  defp verify_and_update_password(user, current_password, new_password) do
    import Ecto.Query
    alias Annotate.Schema.Users.Credentials.UserCredential, as: CredSchema

    context = Noizu.Context.system()

    with {:ok, auth_provider} <- Annotate.Auth.Providers.login(),
         {:ok, auth_provider_id} <- Annotate.Auth.Providers.Provider.id(auth_provider) do
      credential =
        from(c in CredSchema,
          where: c.user_id == ^user.id,
          where: c.auth_provider_id == ^auth_provider_id,
          where: c.status == :active,
          limit: 1
        )
        |> Annotate.Repo.one()

      cond do
        is_nil(credential) ->
          {:error, :credential_not_found}

        not Bcrypt.verify_pass(current_password, credential.settings["password"]) ->
          {:error, :invalid_current_password}

        true ->
          case Annotate.Users.Credentials.update_password(user, new_password, context) do
            {:ok, _} -> :ok
            other -> other
          end
      end
    else
      _ -> {:error, :credential_not_found}
    end
  end

  defp normalize_orgs(list) when is_list(list) do
    Enum.map(list, fn
      %{id: id, name: name} = o ->
        %{id: to_string(id), name: name || "Organization", slug: Map.get(o, :slug)}

      %{"id" => id, "name" => name} = o ->
        %{id: to_string(id), name: name || "Organization", slug: Map.get(o, "slug")}

      other when is_map(other) ->
        id = Map.get(other, :id) || Map.get(other, "id")
        name = Map.get(other, :name) || Map.get(other, "name") || "Organization"
        %{id: to_string(id), name: name, slug: Map.get(other, :slug) || Map.get(other, "slug")}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_orgs(_), do: []
end
