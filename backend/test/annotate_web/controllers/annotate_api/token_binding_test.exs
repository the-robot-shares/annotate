defmodule AnnotateWeb.AnnotateAPI.TokenBindingTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  setup %{conn: conn} do
    {site, _key} = create_site()
    commenter = create_commenter()
    {:ok, conn: conn, site: site, commenter: commenter}
  end

  test "token origin claim ≠ request Origin → 401 origin_mismatch", %{
    conn: conn,
    site: site,
    commenter: commenter
  } do
    # Both origins registered (CORS passes); token is bound to the other one.
    Annotate.Repo.update!(
      Ecto.Changeset.change(site,
        allowed_origins: ["https://good.example", "https://other.example"]
      )
    )

    token = issue_access(commenter, site, "https://other.example")

    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert %{"error" => "origin_mismatch"} = json_response(conn, 401)
  end

  test "expired access token → 401", %{conn: conn, site: site, commenter: commenter} do
    expired =
      Annotate.Auth.ApiToken.sign(
        %{
          "sub" => commenter.id,
          "site" => site.id,
          "origin" => @good_origin,
          "typ" => "annotate_access"
        },
        -1
      )

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{expired}")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert %{"error" => "invalid_token"} = json_response(conn, 401)
  end

  test "forged token (wrong secret) → 401", %{conn: conn, site: site, commenter: commenter} do
    forged =
      %{
        "kty" => "oct",
        "k" => Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      }
      |> JOSE.JWT.sign(%{"alg" => "HS256"}, %{
        "sub" => commenter.id,
        "site" => site.id,
        "origin" => @good_origin,
        "typ" => "annotate_access"
      })
      |> JOSE.JWS.compact()
      |> elem(1)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{forged}")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert %{"error" => "invalid_token"} = json_response(conn, 401)
  end

  test "HS512 downgrade attempt rejected", %{conn: conn, site: site, commenter: commenter} do
    token =
      %{
        "kty" => "oct",
        "k" =>
          Base.url_encode64(:crypto.hash(:sha256, Annotate.Auth.ApiToken.secret()),
            padding: false
          )
      }
      |> JOSE.JWT.sign(%{"alg" => "HS512"}, %{
        "sub" => commenter.id,
        "site" => site.id,
        "origin" => @good_origin,
        "typ" => "annotate_access"
      })
      |> JOSE.JWS.compact()
      |> elem(1)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert %{"error" => "invalid_token"} = json_response(conn, 401)
  end

  test "refresh rotation: new pair works, reuse of rotated token fails", %{
    conn: conn,
    site: site,
    commenter: commenter
  } do
    {:ok, %{access_token: _access, refresh_token: refresh1}} =
      Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin)

    conn1 =
      conn
      |> put_req_header("origin", @good_origin)
      |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh1})

    assert %{"access_token" => access2, "refresh_token" => refresh2, "commenter" => _} =
             json_response(conn1, 200)

    assert refresh2 != refresh1

    # new access token is bound and usable
    check =
      build_conn()
      |> Map.put(:host, @site_host)
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{access2}")
      |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

    assert check.status == 200, "status=#{check.status} body=#{check.resp_body}"

    # old refresh token is revoked — reuse fails
    reuse =
      build_conn()
      |> Map.put(:host, @site_host)
      |> put_req_header("origin", @good_origin)
      |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh1})

    assert %{"error" => "invalid_refresh_token"} = json_response(reuse, 401)
  end

  describe "POST /api/v1/token/refresh (comment_policy re-check)" do
    test "policy tightened after issuance → 403 policy_violation, token revoked", %{
      conn: conn,
      site: site,
      commenter: commenter
    } do
      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, %{
          "email" => commenter.email,
          "groups" => ["annotate-users"]
        })

      # site tightens policy to a group the identity does not have
      Annotate.Repo.update!(
        Ecto.Changeset.change(site, comment_policy: %{"required_groups" => ["board-members"]})
      )

      denied =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh})

      assert %{"error" => "policy_violation"} = json_response(denied, 403)

      # the presented token was revoked on the failed rotate — reuse is dead too
      reuse =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh})

      assert %{"error" => "invalid_refresh_token"} = json_response(reuse, 401)
    end

    test "policy satisfied → rotation succeeds and carries identity claims forward", %{
      conn: conn,
      site: site,
      commenter: commenter
    } do
      Annotate.Repo.update!(
        Ecto.Changeset.change(site, comment_policy: %{"required_groups" => ["annotate-users"]})
      )

      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, %{
          "email" => commenter.email,
          "groups" => ["annotate-users"]
        })

      ok =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh})

      assert %{"access_token" => _, "refresh_token" => refresh2} = json_response(ok, 200)

      # the fresh token still passes the (unchanged) policy on the next rotate
      ok2 =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh2})

      assert %{"refresh_token" => _} = json_response(ok2, 200)
    end

    test "legacy token without stored claims: email-domain policy still enforced, required_groups fails closed",
         %{conn: conn, site: site, commenter: commenter} do
      raw = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      # insert a pre-claims (legacy) refresh token row directly
      %Annotate.Schema.Annotate.RefreshToken{}
      |> Ecto.Changeset.change(%{
        commenter_id: commenter.id,
        site_id: site.id,
        token_hash: Annotate.Auth.RefreshTokens.hash(raw),
        identity_claims: nil,
        expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
      })
      |> Annotate.Repo.insert!()

      # email domain allowlist that MATCHES the commenter's stored email → ok
      Annotate.Repo.update!(
        Ecto.Changeset.change(site,
          comment_policy: %{"allowed_email_domains" => ["ok.example"]}
        )
      )

      commenter = Annotate.Repo.reload!(commenter)
      # ensure the email matches the policy for this leg
      Annotate.Repo.update!(Ecto.Changeset.change(commenter, email: "legacy@ok.example"))

      legacy =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => raw})

      assert %{"access_token" => _, "refresh_token" => fresh} = json_response(legacy, 200)

      # tighten to required_groups — legacy claims cannot prove membership → fail closed
      Annotate.Repo.update!(
        Ecto.Changeset.change(site, comment_policy: %{"required_groups" => ["staff"]})
      )

      denied =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => fresh})

      assert %{"error" => "policy_violation"} = json_response(denied, 403)
    end

    test "email-domain policy tightened against the stored identity → 403", %{
      conn: conn,
      site: site,
      commenter: commenter
    } do
      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, %{
          "email" => "someone@freemail.example",
          "groups" => []
        })

      Annotate.Repo.update!(
        Ecto.Changeset.change(site,
          comment_policy: %{"allowed_email_domains" => ["corp.example"]}
        )
      )

      denied =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/token/refresh?site=#{site.slug}", %{"refresh_token" => refresh})

      assert %{"error" => "policy_violation"} = json_response(denied, 403)
    end
  end

  describe "POST /api/v1/token/refresh (origin binding)" do
    defp refresh_from(origin, refresh, slug) do
      conn = build_conn() |> Map.put(:host, @site_host)
      conn = if origin, do: put_req_header(conn, "origin", origin), else: conn
      post(conn, "/api/v1/token/refresh?site=#{slug}", %{"refresh_token" => refresh})
    end

    test "forged Origin (not on the allowlist) → 401, token NOT burned", %{
      site: site,
      commenter: commenter
    } do
      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin)

      # CORS layer: evil origin addressing the victim site is refused outright.
      assert json_response(refresh_from(@evil_origin, refresh, site.slug), 403)

      # Realistic attack: the attacker registers their OWN site allowlisting
      # their origin and addresses it, presenting the victim site's token.
      {attacker, _} = create_site(origins: [@evil_origin])

      assert %{"error" => "origin_mismatch"} =
               json_response(refresh_from(@evil_origin, refresh, attacker.slug), 401)

      # the legitimate holder can still rotate
      assert %{"access_token" => access} =
               json_response(refresh_from(@good_origin, refresh, site.slug), 200)

      assert Annotate.Auth.ApiToken.verify(access) |> elem(1) |> Map.get("origin") == @good_origin
    end

    test "allowed but different origin than the token was issued for → 401", %{
      site: site,
      commenter: commenter
    } do
      Annotate.Repo.update!(
        Ecto.Changeset.change(site,
          allowed_origins: ["https://good.example", "https://other.example"]
        )
      )

      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin)

      assert %{"error" => "origin_mismatch"} =
               json_response(refresh_from("https://other.example", refresh, site.slug), 401)
    end

    test "missing Origin → 401", %{site: site, commenter: commenter} do
      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin)

      assert %{"error" => "origin_mismatch"} =
               json_response(refresh_from(nil, refresh, site.slug), 401)
    end

    test "origin binding survives rotation", %{site: site, commenter: commenter} do
      Annotate.Repo.update!(
        Ecto.Changeset.change(site,
          allowed_origins: ["https://good.example", "https://other.example"]
        )
      )

      {:ok, %{refresh_token: refresh}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin)

      assert %{"refresh_token" => refresh2} =
               json_response(refresh_from(@good_origin, refresh, site.slug), 200)

      assert json_response(refresh_from("https://other.example", refresh2, site.slug), 401)
    end

    test "legacy token without recorded origin: allowlisted Origin ok, then re-bound", %{
      site: site,
      commenter: commenter
    } do
      Annotate.Repo.update!(
        Ecto.Changeset.change(site,
          allowed_origins: ["https://good.example", "https://other.example"]
        )
      )

      raw = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

      %Annotate.Schema.Annotate.RefreshToken{}
      |> Ecto.Changeset.change(%{
        commenter_id: commenter.id,
        site_id: site.id,
        token_hash: Annotate.Auth.RefreshTokens.hash(raw),
        identity_claims: %{"email" => nil, "groups" => nil},
        expires_at: DateTime.add(DateTime.utc_now(), 1, :day)
      })
      |> Annotate.Repo.insert!()

      {attacker, _} = create_site(origins: [@evil_origin])

      assert %{"error" => "origin_mismatch"} =
               json_response(refresh_from(@evil_origin, raw, attacker.slug), 401)

      assert %{"refresh_token" => raw2} =
               json_response(refresh_from(@good_origin, raw, site.slug), 200)

      assert json_response(refresh_from("https://other.example", raw2, site.slug), 401)
    end
  end
end
