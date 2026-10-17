defmodule AnnotateWeb.GithubLoginFlowTest do
  @moduledoc """
  Dashboard GitHub sign-in end to end through the router + Ueberauth, using
  the dev/test `Annotate.Auth.GithubStub` strategy (no network), and the
  GitHub-only login-method gate.
  """
  use AnnotateWeb.ConnCase, async: false

  alias Annotate.Repo
  alias Annotate.Schema.Users.User

  defp start_flow(query) do
    conn = get(build_conn(), "/auth/github?" <> URI.encode_query(query))
    assert conn.status == 302
    {conn, redirected_to(conn)}
  end

  defp finish(conn, location), do: conn |> recycle() |> get(location)

  test "verified GitHub email → account created, redirected to the code exchange" do
    {conn, location} =
      start_flow(%{stub_id: "77", stub_login: "octo", stub_email: "octo@example.com"})

    assert location =~ "/auth/github/callback"
    assert location =~ "state="

    conn = finish(conn, location)
    assert redirected_to(conn) =~ ~r{^/auth/sso-callback\?code=.+&provider=github$}
    assert %User{verified: true} = Repo.get_by(User, email: "octo@example.com")
  end

  test "unverified GitHub email is refused (no account)" do
    {conn, location} =
      start_flow(%{stub_id: "78", stub_email: "victim@example.com", stub_verified: "false"})

    conn = finish(conn, location)
    assert redirected_to(conn) == "/auth/sso-callback?error=github_email_unverified"
    refute Repo.get_by(User, email: "victim@example.com")
  end

  test "callback without the state cookie fails (CSRF)" do
    {_conn, location} = start_flow(%{stub_id: "79", stub_email: "c@example.com"})
    conn = get(build_conn(), location)
    assert redirected_to(conn) == "/auth/sso-callback?error=github_failed"
    refute Repo.get_by(User, email: "c@example.com")
  end

  test "stub refuses to run when not allowed" do
    Application.put_env(:annotate, :github_stub_allowed, false)
    on_exit(fn -> Application.put_env(:annotate, :github_stub_allowed, true) end)

    conn = get(build_conn(), "/auth/github?stub_id=80&stub_email=s@example.com")
    refute conn.status == 302 and redirected_to(conn) =~ "/auth/github/callback"
  end

  test "GitHub not configured → friendly error, not a blank 404" do
    prev = Application.get_env(:ueberauth, Ueberauth)
    Application.put_env(:ueberauth, Ueberauth, providers: [])
    on_exit(fn -> Application.put_env(:ueberauth, Ueberauth, prev) end)

    conn = get(build_conn(), "/auth/github")
    assert redirected_to(conn) == "/auth/sso-callback?error=github_not_configured"
  end

  describe "GitHub-only login methods" do
    setup do
      Application.put_env(:annotate, :login_methods, ["github"])
      on_exit(fn -> Application.put_env(:annotate, :login_methods, :all) end)
    end

    test "password / magic-link / OIDC / other social routes 404" do
      for {method, path} <- [
            {:post, "/api/v1/auth/login"},
            {:post, "/api/v1/auth/register"},
            {:post, "/api/v1/auth/magic-link"},
            {:post, "/api/v1/auth/otp-login"},
            {:post, "/api/v1/auth/password-reset"},
            {:get, "/auth/oidc"},
            {:get, "/auth/google"}
          ] do
        conn = dispatch(build_conn(), @endpoint, method, path, %{})
        assert conn.status == 404, "#{method} #{path} returned #{conn.status}"
      end
    end

    test "GitHub still works; providers list is GitHub-only" do
      {_conn, location} = start_flow(%{stub_id: "81", stub_email: "g@example.com"})
      assert location =~ "/auth/github/callback"

      Application.put_env(:annotate, :oidc_enabled, true)
      on_exit(fn -> Application.delete_env(:annotate, :oidc_enabled) end)

      assert %{"providers" => ["github"]} =
               build_conn() |> get("/api/v1/auth/sso/providers") |> json_response(200)
    end

    test "context-level gates refuse email sign-in families" do
      assert {:error, :login_method_disabled} =
               Annotate.Auth.SmartTokenAuth.request_magic_link("a@example.com")

      assert {:error, :login_method_disabled} =
               Annotate.Auth.SmartTokenAuth.request_password_reset("a@example.com")

      assert {:error, msg} =
               Annotate.Hologram.Auth.login(%Hologram.Server{}, "a@example.com", "pw123456")

      assert msg =~ "GitHub"
    end

    test "/login, /signup, /forgot-password bounce to /sign-in; /sign-in renders" do
      for path <- ["/login", "/signup", "/forgot-password"] do
        conn = get(build_conn(), path)
        assert redirected_to(conn) == "/sign-in", path
      end

      html = build_conn() |> get("/sign-in") |> html_response(200)
      assert html =~ "Continue with GitHub"
      assert html =~ ~s(href="/auth/github")
    end
  end

  test "full round trip: callback page hands off to /dashboard" do
    {conn, location} =
      start_flow(%{stub_id: "90", stub_login: "rt", stub_email: "rt@example.com"})

    conn = finish(conn, location)
    html = conn |> recycle() |> get(redirected_to(conn)) |> html_response(200)
    assert html =~ ~s(content="0;url=/dashboard")
  end

  test "/sign-in shows 'not configured' when GitHub creds are absent" do
    Application.put_env(:annotate, :github_enabled, false)
    on_exit(fn -> Application.put_env(:annotate, :github_enabled, true) end)

    html = build_conn() |> get("/sign-in") |> html_response(200)
    assert html =~ "GitHub sign-in is not configured yet."
  end
end
