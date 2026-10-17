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

  test "MCP return_to survives the GitHub round trip (same-origin only)" do
    {conn, location} =
      start_flow(%{
        stub_id: "93",
        stub_email: "mcp-return@example.com",
        return_to: "/oauth/authorize?login_state=abc123"
      })

    conn = finish(conn, location)
    target = redirected_to(conn)
    assert target =~ ~r{^/auth/sso-callback\?code=.+&provider=github}

    assert URI.decode_query(URI.parse(target).query)["return_to"] ==
             "/oauth/authorize?login_state=abc123"
  end

  test "a foreign return_to is dropped before the round trip" do
    {conn, location} =
      start_flow(%{
        stub_id: "94",
        stub_email: "mcp-evil@example.com",
        return_to: "https://evil.example/steal"
      })

    conn = finish(conn, location)
    refute redirected_to(conn) =~ "return_to"
  end

  test "prod 2026-10-17: a crash inside the token exchange is a friendly page, not a 500" do
    {conn, location} =
      start_flow(%{stub_id: "91", stub_email: "tls@example.com", stub_crash: "tls"})

    conn = finish(conn, location)
    assert redirected_to(conn) == "/auth/sso-callback?error=github_failed"
    refute Repo.get_by(User, email: "tls@example.com")
  end

  test "GitHub's callback with iss + a primary verified email (prod shape) signs in" do
    {conn, location} =
      start_flow(%{
        stub_id: "92",
        stub_login: "keith",
        stub_emails: "noreply@users.noreply.github.com:true,owner@example.com:true:primary"
      })

    conn =
      finish(conn, location <> "&iss=" <> URI.encode_www_form("https://github.com/login/oauth"))

    assert redirected_to(conn) =~ ~r{^/auth/sso-callback\?code=}
    assert %User{verified: true} = Repo.get_by(User, email: "owner@example.com")
  end

  test "production image installs a CA bundle (outbound TLS for the GitHub token exchange)" do
    dockerfile = File.read!(Path.expand("../../../Dockerfile", __DIR__))
    [_, production] = String.split(dockerfile, "AS production", parts: 2)
    assert production =~ "ca-certificates"
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

  test "full round trip, exempt @noizu.com: callback page hands off to /dashboard" do
    {conn, location} =
      start_flow(%{stub_id: "90", stub_login: "rt", stub_email: "rt@noizu.com"})

    conn = finish(conn, location)
    html = conn |> recycle() |> get(redirected_to(conn)) |> html_response(200)
    assert html =~ ~s(content="0;url=/dashboard")
  end

  test "full round trip, uninvited: lands on the invite interstitial" do
    {conn, location} =
      start_flow(%{stub_id: "93", stub_login: "rt2", stub_email: "rt2@example.com"})

    conn = finish(conn, location)
    html = conn |> recycle() |> get(redirected_to(conn)) |> html_response(200)
    assert html =~ ~s(content="0;url=/auth/invite-required")
  end

  test "prod shape: providers observed as \"\" → not-configured redirect, not a 500" do
    prev = Application.get_env(:ueberauth, Ueberauth)
    Application.put_env(:ueberauth, Ueberauth, providers: "")
    on_exit(fn -> Application.put_env(:ueberauth, Ueberauth, prev) end)

    assert redirected_to(get(build_conn(), "/auth/github")) ==
             "/auth/sso-callback?error=github_not_configured"

    assert redirected_to(get(build_conn(), "/auth/github/callback?code=x&state=y")) ==
             "/auth/sso-callback?error=github_not_configured"
  end

  test "/sign-in shows 'not configured' when GitHub creds are absent" do
    Application.put_env(:annotate, :github_enabled, false)
    on_exit(fn -> Application.put_env(:annotate, :github_enabled, true) end)

    html = build_conn() |> get("/sign-in") |> html_response(200)
    assert html =~ "GitHub sign-in is not configured yet."
  end
end
