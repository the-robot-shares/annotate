defmodule AnnotateWeb.Hologram.Pages.ForgotPasswordPage do
  @moduledoc """
  Password reset: request code → verify code + set new password.
  Mirrors start-app frontend `/forgot-password`.
  """
  use Hologram.Page

  alias Hologram.UI.Link
  alias AnnotateWeb.Hologram.Layouts.AuthLayout
  alias AnnotateWeb.Hologram.Pages.LoginPage

  route "/forgot-password"
  layout AuthLayout, page_title: "Forgot Password"
  middleware AnnotateWeb.Hologram.Middleware.GithubOnly

  # <REMOVED UUID HERE> init :: auto-generated pointer for public function init
  def init(_params, component, _server) do
    put_state(component,
      step: "request",
      email: "",
      code: "",
      new_password: "",
      confirm_password: "",
      message: nil,
      error: nil,
      loading: false,
      dev_code: nil
    )
  end

  # <REMOVED UUID HERE> template :: auto-generated pointer for public function template
  def template do
    ~HOLO"""
    <div class="nd-auth">
      <h1 class="nd-auth__title">Forgot Password</h1>

      {%if @step == "request"}
        <p class="nd-auth__intro">Enter your email and we'll send a reset code if an account exists.</p>
        <form class="nd-auth__form" $submit.prevent_default={:submit_request}>
          {%if @error}
            <p class="nd-auth__error" role="alert">{@error}</p>
          {/if}
          <div class="nd-auth__field">
            <label for="reset-email">Email</label>
            <input id="reset-email" type="email" value={@email} required autocomplete="email" $change={:set_email} />
          </div>
          <button type="submit" class="nd-btn nd-btn--primary" disabled={@loading}>
            {%if @loading}Sending...{%else}Send reset code{/if}
          </button>
          <div class="nd-auth__footer">
            <p><Link to={LoginPage}>Back to log in</Link></p>
          </div>
        </form>
      {/if}

      {%if @step == "verify"}
        <p class="nd-auth__intro">
          Enter the code sent to <strong>{@email}</strong> and choose a new password.
        </p>
        {%if @dev_code}
          <p class="nd-auth__intro">Dev code: <code>{@dev_code}</code></p>
        {/if}
        <form class="nd-auth__form" $submit.prevent_default={:submit_verify}>
          {%if @error}
            <p class="nd-auth__error" role="alert">{@error}</p>
          {/if}
          <div class="nd-auth__field">
            <label for="reset-code">Reset code</label>
            <input id="reset-code" type="text" value={@code} required autocomplete="one-time-code" $change={:set_code} />
          </div>
          <div class="nd-auth__field">
            <label for="reset-new-password">New password</label>
            <input
              id="reset-new-password"
              type="password"
              value={@new_password}
              required
              minlength="8"
              autocomplete="new-password"
              $change={:set_new_password}
            />
          </div>
          <div class="nd-auth__field">
            <label for="reset-confirm-password">Confirm password</label>
            <input
              id="reset-confirm-password"
              type="password"
              value={@confirm_password}
              required
              minlength="8"
              autocomplete="new-password"
              $change={:set_confirm_password}
            />
          </div>
          <button type="submit" class="nd-btn nd-btn--primary" disabled={@loading}>
            {%if @loading}Updating...{%else}Update password{/if}
          </button>
          <div class="nd-auth__footer">
            <p>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={:back_to_request}>Use a different email</button>
            </p>
          </div>
        </form>
      {/if}

      {%if @step == "done"}
        <p role="status">{@message}</p>
        <p><Link to={LoginPage}>Back to log in</Link></p>
      {/if}
    </div>
    """
  end

  # <REMOVED UUID HERE> action :: auto-generated pointer for public function action
  def action(:set_email, params, c), do: put_state(c, :email, params.event.value)
  def action(:set_code, params, c), do: put_state(c, :code, params.event.value)
  def action(:set_new_password, params, c), do: put_state(c, :new_password, params.event.value)

  def action(:set_confirm_password, params, c),
    do: put_state(c, :confirm_password, params.event.value)

  def action(:back_to_request, _params, component) do
    put_state(component,
      step: "request",
      code: "",
      new_password: "",
      confirm_password: "",
      error: nil,
      message: nil,
      dev_code: nil
    )
  end

  def action(:submit_request, _params, component) do
    component
    |> put_state(loading: true, error: nil)
    |> put_command(:request_reset, email: component.state.email)
  end

  def action(:reset_sent, params, component) do
    put_state(component,
      loading: false,
      step: "verify",
      message: params.message,
      dev_code: Map.get(params, :dev_code),
      error: nil
    )
  end

  def action(:reset_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Request failed")
  end

  def action(:submit_verify, _params, component) do
    cond do
      String.length(component.state.new_password || "") < 8 ->
        put_state(component, error: "Password must be at least 8 characters")

      component.state.new_password != component.state.confirm_password ->
        put_state(component, error: "Passwords do not match")

      true ->
        component
        |> put_state(loading: true, error: nil)
        |> put_command(:verify_reset,
          email: component.state.email,
          code: component.state.code,
          new_password: component.state.new_password
        )
    end
  end

  def action(:reset_ok, params, component) do
    put_state(component,
      loading: false,
      step: "done",
      message: params.message || "Password updated. You can log in with your new password.",
      error: nil
    )
  end

  def action(:verify_failed, params, component) do
    put_state(component, loading: false, error: params.error || "Invalid or expired code")
  end

  # <REMOVED UUID HERE> command :: auto-generated pointer for public function command
  def command(:request_reset, params, server) do
    case Annotate.Auth.SmartTokenAuth.request_password_reset(params.email) do
      {:ok, %{otp_code: code}} ->
        Annotate.Auth.SmartTokenEmail.send_password_reset(params.email, code)

        response = %{message: "If an account exists with that email, a reset code has been sent."}

        response =
          if Application.get_env(:annotate, :dev_routes) do
            Map.put(response, :dev_code, code)
          else
            response
          end

        put_action(server, :reset_sent, response)

      {:error, :not_found} ->
        put_action(server, :reset_sent,
          message: "If an account exists with that email, a reset code has been sent."
        )
    end
  end

  def command(:verify_reset, params, server) do
    case Annotate.Auth.SmartTokenAuth.verify_password_reset(
           params.email,
           params.code,
           params.new_password,
           %{}
         ) do
      {:ok, _} ->
        put_action(server, :reset_ok,
          message: "Password updated. You can log in with your new password."
        )

      {:error, :invalid_code} ->
        put_action(server, :verify_failed, error: "Invalid or expired code")

      {:error, reason} ->
        put_action(server, :verify_failed, error: "Could not reset password (#{inspect(reason)})")
    end
  end
end
