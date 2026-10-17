defmodule Annotate.Auth.GithubStub do
  @moduledoc """
  **Dev/test only** Ueberauth strategy standing in for GitHub OAuth.

  Request phase redirects straight to the callback, carrying Ueberauth's CSRF
  `state` plus the `stub_*` params; the callback fabricates the same
  `raw_info.user` shape `Ueberauth.Strategy.Github` produces (including the
  `/user/emails` list with `verified` flags), so `Annotate.Dashboard.
  GithubLogin` runs its real verification logic against it.

      /auth/github?stub_id=42&stub_login=octo&stub_email=octo@example.com&stub_verified=true

  Refuses to run unless `config :annotate, :github_stub_allowed, true` (set
  only by config/test.exs and the dev-only `ANNOTATE_GITHUB_STUB=1` path in
  runtime.exs): wiring it into prod by mistake fails every sign-in closed.
  """

  use Ueberauth.Strategy, uid_field: :id

  alias Ueberauth.Auth.{Credentials, Extra, Info}

  @stub_params ~w(stub_id stub_login stub_name stub_email stub_verified stub_emails)

  def handle_request!(conn) do
    if allowed?() do
      params =
        conn.params
        |> Map.take(@stub_params)
        |> Map.to_list()
        |> with_state_param(conn)

      redirect!(conn, callback_url(conn, params))
    else
      set_errors!(conn, [error("stub_disabled", "GitHub stub strategy is disabled")])
    end
  end

  def handle_callback!(%Plug.Conn{params: %{"stub_id" => id} = p} = conn) do
    if allowed?() do
      email = p["stub_email"]
      verified = p["stub_verified"] != "false"

      emails =
        case p["stub_emails"] do
          # "a@x:true:primary,b@y:false"
          list when is_binary(list) and list != "" ->
            list
            |> String.split(",", trim: true)
            |> Enum.map(fn entry ->
              [addr | flags] = String.split(entry, ":")

              %{
                "email" => addr,
                "verified" => "true" in flags,
                "primary" => "primary" in flags
              }
            end)

          _ ->
            if email,
              do: [%{"email" => email, "verified" => verified, "primary" => true}],
              else: []
        end

      user = %{
        "id" => String.to_integer(id),
        "login" => p["stub_login"] || "stub-#{id}",
        "name" => p["stub_name"],
        "email" => nil,
        "avatar_url" => "https://avatars.example.test/#{id}",
        "emails" => emails
      }

      put_private(conn, :github_user, user)
    else
      set_errors!(conn, [error("stub_disabled", "GitHub stub strategy is disabled")])
    end
  end

  def handle_callback!(conn),
    do: set_errors!(conn, [error("missing_stub_id", "stub_id is required")])

  def handle_cleanup!(conn), do: put_private(conn, :github_user, nil)

  def uid(conn), do: conn.private.github_user["id"]

  def info(conn) do
    user = conn.private.github_user

    %Info{
      nickname: user["login"],
      name: user["name"],
      email: nil,
      image: user["avatar_url"]
    }
  end

  def credentials(_conn), do: %Credentials{token: "stub-token", token_type: "Bearer"}

  def extra(conn),
    do: %Extra{raw_info: %{token: nil, user: conn.private.github_user}}

  defp allowed?, do: Application.get_env(:annotate, :github_stub_allowed, false) == true
end
