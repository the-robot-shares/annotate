defmodule Annotate.Auth.GoogleStub do
  @moduledoc """
  **Dev/test only** Ueberauth strategy standing in for Google OAuth. Mirrors
  `Annotate.Auth.GithubStub`: request → callback with Ueberauth's CSRF
  `state` and `stub_*` params; the callback fabricates the OpenID userinfo
  shape `Ueberauth.Strategy.Google` returns (`sub`, `email`,
  `email_verified`, `hd`, `name`, `picture`).

      /auth/google?stub_sub=1234&stub_email=a@example.com&stub_verified=true&stub_hd=example.com

  Refuses unless `:github_stub_allowed` is set (test config / dev
  `ANNOTATE_GITHUB_STUB=1`), so it can never run in prod.
  """

  use Ueberauth.Strategy, uid_field: :sub

  alias Ueberauth.Auth.{Credentials, Extra, Info}

  @stub_params ~w(stub_sub stub_email stub_verified stub_hd stub_name stub_crash)

  def handle_request!(conn) do
    if allowed?() do
      params = conn.params |> Map.take(@stub_params) |> Map.to_list() |> with_state_param(conn)
      redirect!(conn, callback_url(conn, params))
    else
      set_errors!(conn, [error("stub_disabled", "Google stub strategy is disabled")])
    end
  end

  def handle_callback!(%Plug.Conn{params: %{"stub_crash" => "tls"}}),
    do:
      raise(FunctionClauseError,
        module: :pubkey_os_cacerts,
        function: :conv_error_reason,
        arity: 1
      )

  def handle_callback!(%Plug.Conn{params: %{"stub_sub" => sub} = p} = conn) do
    if allowed?() do
      user =
        %{
          "sub" => sub,
          "email" => p["stub_email"],
          # Google sends a JSON boolean; absent param = verified.
          "email_verified" => p["stub_verified"] != "false",
          "name" => p["stub_name"],
          "picture" => "https://avatars.example.test/g/#{sub}"
        }
        |> then(fn u -> if p["stub_hd"], do: Map.put(u, "hd", p["stub_hd"]), else: u end)

      put_private(conn, :google_user, user)
    else
      set_errors!(conn, [error("stub_disabled", "Google stub strategy is disabled")])
    end
  end

  def handle_callback!(conn),
    do: set_errors!(conn, [error("missing_stub_sub", "stub_sub is required")])

  def handle_cleanup!(conn), do: put_private(conn, :google_user, nil)
  def uid(conn), do: conn.private.google_user["sub"]

  def info(conn) do
    u = conn.private.google_user
    %Info{email: u["email"], name: u["name"], image: u["picture"]}
  end

  def credentials(_conn), do: %Credentials{token: "stub-token", token_type: "Bearer"}
  def extra(conn), do: %Extra{raw_info: %{token: nil, user: conn.private.google_user}}

  defp allowed?, do: Application.get_env(:annotate, :github_stub_allowed, false) == true
end
