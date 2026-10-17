defmodule AnnotateWeb.AnnotateAPI.EmbedAuthTest do
  use AnnotateWeb.AnnotateAPICase, async: false

  import ExUnit.CaptureLog

  @provider_cfg [
    discovery_document_uri: "https://fake.example/.well-known/openid-configuration",
    client_id: "cid",
    client_secret: "sec",
    response_type: "code",
    scope: "openid email profile"
  ]

  # Mirrors the real OpenIDConnect surface: authorization_uri → %URI{},
  # fetch_tokens/2 → {:ok, token_map}, verify/2 → {:ok, claims map}.
  #
  # fetch_tokens/2 pattern-matches a MAP of atom-keyed params — the real
  # OpenIDConnect.fetch_tokens/2 merges its second argument into the token
  # POST form with Map.merge/2, so a keyword list raises BadMapError. That
  # mismatch was the prod 500 on /embed/callback (2026-10-16); the match here
  # is the regression pin.
  defmodule FakeOIDC do
    def authorization_uri(_config, _redirect_uri, params) do
      send(self(), {:fake_authorize, params})

      %URI{
        scheme: "https",
        host: "fake-idp.example",
        path: "/authorize",
        query: "state=#{params.state}"
      }
    end

    def fetch_tokens(_config, %{code: code, redirect_uri: redirect_uri} = params) do
      send(self(), {:fake_fetch_tokens, params})
      {:ok, %{"id_token" => "fake.id.token", "code" => code, "redirect_uri" => redirect_uri}}
    end

    def verify(_config, _id_token) do
      {:ok,
       %{
         "sub" => "auth-sub-1",
         "email" => "ella@example.com",
         "name" => "Ella",
         "groups" => ["annotate-users"],
         # echo the nonce the test stashed (fail-closed nonce check: the id
         # token must carry the nonce from the authorization request)
         "nonce" => Process.get(:fake_oidc_nonce)
       }}
    end
  end

  # Crashes mid-exchange the way the real library did in prod (a code-shaped
  # token embedded in the message, so the log-redaction path is exercised too).
  defmodule RaisingOIDC do
    def fetch_tokens(_config, _params) do
      raise "token endpoint exploded for code=SuperSecretCodeToken0987654321abcdefgh"
    end
  end

  setup do
    {site, _key} = create_site()
    {:ok, site: site}
  end

  defp with_fake_oidc(_ctx) do
    Application.put_env(:annotate, :oidc_impl, FakeOIDC)
    Application.put_env(:openid_connect, :providers, default: @provider_cfg)

    on_exit(fn ->
      Application.delete_env(:annotate, :oidc_impl)
      Application.delete_env(:openid_connect, :providers)
    end)

    :ok
  end

  describe "Embed.Policy.check/2" do
    test "passes with no constraints" do
      assert :ok == Annotate.Embed.Policy.check(%{"groups" => [], "email" => "a@x.com"}, %{})
    end

    test "any-of group match" do
      policy = %{"required_groups" => ["a", "b"]}

      assert :ok == Annotate.Embed.Policy.check(%{"groups" => ["b"]}, policy)

      assert {:error, :group_not_allowed} =
               Annotate.Embed.Policy.check(%{"groups" => ["c"]}, policy)
    end

    test "email domain allowlist" do
      policy = %{"allowed_email_domains" => ["corp.example"]}

      assert :ok == Annotate.Embed.Policy.check(%{"email" => "u@corp.example"}, policy)

      assert {:error, :email_domain_not_allowed} =
               Annotate.Embed.Policy.check(%{"email" => "u@gmail.com"}, policy)
    end
  end

  describe "GET /embed/login" do
    test "403 on disallowed origin", %{conn: conn, site: site} do
      conn =
        conn
        |> get("/embed/login?site=#{site.slug}&origin=https://evil.example")

      assert %{"error" => "origin_not_allowed"} = json_response(conn, 403)
    end

    test "503 when OIDC unconfigured", %{conn: conn, site: site} do
      Application.delete_env(:openid_connect, :providers)
      on_exit(fn -> Application.delete_env(:openid_connect, :providers) end)

      conn =
        conn
        |> get("/embed/login?site=#{site.slug}&origin=#{URI.encode_www_form(@good_origin)}")

      assert conn.status == 503
    end

    test "stashes state in session and redirects to the IdP", %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)

      conn =
        conn
        |> get("/embed/login?site=#{site.slug}&origin=#{URI.encode_www_form(@good_origin)}")

      assert conn.status == 302
      assert redirected_to(conn) =~ "https://fake-idp.example/authorize"

      assert %{
               "site_id" => stashed_site_id,
               "origin" => @good_origin,
               "state" => state,
               "nonce" => nonce
             } =
               conn.private.plug_session["embed_state"]

      assert stashed_site_id == site.id
      assert is_binary(state) and is_binary(nonce)
      assert_received {:fake_authorize, %{state: ^state, nonce: ^nonce}}
    end

    test "session cookie carries flow state: SameSite=Lax, HttpOnly, Max-Age=900",
         %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)

      conn =
        conn
        |> get("/embed/login?site=#{site.slug}&origin=#{URI.encode_www_form(@good_origin)}")

      assert conn.status == 302

      set_cookie =
        conn
        |> get_resp_header("set-cookie")
        |> Enum.join("; ")

      # Lax is load-bearing: the IdP redirect back to /embed/callback is a
      # top-level cross-site navigation, and SameSite=Strict would drop the
      # state/nonce cookie exactly there (the cookie never carries
      # credentials, so Lax is the correct posture).
      assert set_cookie =~ "_annotate_sso="
      assert set_cookie =~ ~r/samesite=lax/i
      assert set_cookie =~ ~r/httponly/i
      assert set_cookie =~ ~r/max-age=900/i
    end
  end

  describe "GET /embed/callback" do
    test "success: commenter upserted, postMessage HTML with tokens",
         %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)
      Process.put(:fake_oidc_nonce, "nonce-abc")

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-123",
          "nonce" => "nonce-abc"
        })
        |> get("/embed/callback?code=c&state=st-123")

      html = response(conn, 200)
      assert html =~ "annotate-auth"
      refute html =~ "annotate-auth-error"
      assert html =~ @good_origin

      # Regression pin for the prod 500 (2026-10-16): the code exchange must
      # hand OpenIDConnect a MAP of atom-keyed params, never a keyword list.
      assert_received {:fake_fetch_tokens, %{code: "c", redirect_uri: redirect_uri}}
      assert redirect_uri == "http://localhost:4002/embed/callback"

      assert commenter =
               Annotate.Repo.get_by(Annotate.Schema.Annotate.Commenter,
                 authentik_sub: "auth-sub-1"
               )

      assert commenter.display_name == "Ella"

      # session state consumed — replay fails the state check
      replay =
        build_conn()
        |> Map.put(:host, @site_host)
        |> get("/embed/callback?code=c&state=st-123")

      assert response(replay, 200) =~ "state_mismatch"
    end

    test "nonce mismatch (id token nonce ≠ session nonce) → nonce_mismatch postMessage",
         %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)
      Process.put(:fake_oidc_nonce, "attacker-nonce")

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-7",
          "nonce" => "session-nonce"
        })
        |> get("/embed/callback?code=c&state=st-7")

      html = response(conn, 200)
      assert html =~ "nonce_mismatch"
      refute html =~ "annotate-auth\""

      refute Annotate.Repo.get_by(Annotate.Schema.Annotate.Commenter, authentik_sub: "auth-sub-1")
    end

    test "missing nonce on either side fails closed → nonce_mismatch",
         %{conn: conn, site: site} =
           ctx do
      :ok = with_fake_oidc(ctx)
      # fake id token carries NO nonce (Process dict unset) while the session
      # stashed one — the nil-vs-nil and nil-vs-value cases must both reject.
      Process.put(:fake_oidc_nonce, nil)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-8",
          "nonce" => "session-nonce"
        })
        |> get("/embed/callback?code=c&state=st-8")

      assert response(conn, 200) =~ "nonce_mismatch"
    end

    test "policy rejection → group_not_allowed postMessage", %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)
      Process.put(:fake_oidc_nonce, "nonce-9")

      Annotate.Repo.update!(
        Ecto.Changeset.change(site, comment_policy: %{"required_groups" => ["other-group"]})
      )

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-9",
          "nonce" => "nonce-9"
        })
        |> get("/embed/callback?code=c&state=st-9")

      html = response(conn, 200)
      assert html =~ "group_not_allowed"

      refute Annotate.Repo.get_by(Annotate.Schema.Annotate.Commenter, authentik_sub: "auth-sub-1")
    end

    test "state tampering → state_mismatch", %{conn: conn, site: site} = ctx do
      :ok = with_fake_oidc(ctx)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "real-state",
          "nonce" => nil
        })
        |> get("/embed/callback?code=c&state=tampered")

      assert response(conn, 200) =~ "state_mismatch"
    end

    test "missing session state → state_mismatch", %{conn: conn} do
      conn = get(conn, "/embed/callback?code=c&state=s")
      assert response(conn, 200) =~ "state_mismatch"
    end

    test "callback with neither code nor error → auth_failed postMessage", %{conn: conn} do
      conn = get(conn, "/embed/callback")
      html = response(conn, 200)

      assert html =~ "annotate-auth-error"
      assert html =~ "auth_failed"
    end

    test "IdP error redirect (consent denied) → access_denied postMessage, no code exchange",
         %{conn: conn, site: site} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-err",
          "nonce" => "n"
        })
        |> get("/embed/callback?error=access_denied&error_description=user+denied&state=st-err")

      html = response(conn, 200)
      assert html =~ "annotate-auth-error"
      assert html =~ "access_denied"
      refute html =~ "annotate-auth\""
    end

    test "IdP error with unmapped code collapses to auth_failed", %{conn: conn, site: site} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-err2",
          "nonce" => "n"
        })
        |> get("/embed/callback?error=server_error&state=st-err2")

      assert response(conn, 200) =~ "auth_failed"
    end

    test "IdP error leg still fails closed on state mismatch", %{conn: conn} do
      conn = get(conn, "/embed/callback?error=access_denied&state=forged")
      assert response(conn, 200) =~ "state_mismatch"
    end

    test "exchange crash → 200 auth_failed postMessage (never a 500), token-shaped strings redacted in logs",
         %{conn: conn, site: site} do
      Application.put_env(:annotate, :oidc_impl, RaisingOIDC)
      Application.put_env(:openid_connect, :providers, default: @provider_cfg)

      on_exit(fn ->
        Application.delete_env(:annotate, :oidc_impl)
        Application.delete_env(:openid_connect, :providers)
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("embed_state", %{
          "site_id" => site.id,
          "origin" => @good_origin,
          "state" => "st-crash",
          "nonce" => "n"
        })

      log =
        capture_log(fn ->
          send(self(), {:crash_resp, get(conn, "/embed/callback?code=c&state=st-crash")})
        end)

      assert_received {:crash_resp, conn}

      # The crash must render the widget error page, not an opaque 500.
      html = response(conn, 200)
      assert html =~ "annotate-auth-error"
      assert html =~ "auth_failed"
      refute html =~ "SuperSecretCodeToken"

      # …and the warning log must carry the failure without the embedded code.
      assert log =~ "[embed] callback exchange failed"
      assert log =~ "[redacted]"
      refute log =~ "SuperSecretCodeToken"
    end

    test "nonce check: verify_nonce unit (fail closed on nil either side)", %{conn: _conn} do
      assert :ok == AnnotateWeb.AnnotateAPI.EmbedController.verify_nonce("a", "a")

      assert {:error, :nonce_mismatch} =
               AnnotateWeb.AnnotateAPI.EmbedController.verify_nonce("a", "b")

      assert {:error, :nonce_mismatch} =
               AnnotateWeb.AnnotateAPI.EmbedController.verify_nonce("a", nil)

      assert {:error, :nonce_mismatch} =
               AnnotateWeb.AnnotateAPI.EmbedController.verify_nonce(nil, "a")

      assert {:error, :nonce_mismatch} =
               AnnotateWeb.AnnotateAPI.EmbedController.verify_nonce(nil, nil)
    end
  end
end
