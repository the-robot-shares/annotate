defmodule AnnotateWeb.AnnotateAPI.HostAssertTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  @now System.system_time(:second)

  defp host_jwt(service_key, claims) do
    jwk = %{
      "kty" => "oct",
      "k" => Base.url_encode64(:crypto.hash(:sha256, service_key), padding: false)
    }

    jwk
    |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  describe "POST /api/v1/sites/:site/token/assert" do
    test "valid assertion upserts commenter by (site, external_id) and issues a usable pair", %{
      conn: conn
    } do
      {site, key} = create_site()

      token = host_jwt(key, %{"sub" => "user-42", "name" => "External Ella", "exp" => @now + 60})

      conn =
        conn
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{"token" => token})

      assert %{"access_token" => access, "refresh_token" => refresh, "commenter" => commenter} =
               json_response(conn, 201)

      assert commenter["display_name"] == "External Ella"

      stored = Annotate.Repo.get_by!(Annotate.Schema.Annotate.Commenter, external_id: "user-42")
      assert stored.site_id == site.id

      # access token works on the API
      check =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> put_req_header("authorization", "Bearer #{access}")
        |> get("/api/v1/sites/#{site.slug}/threads?page_key=/p")

      assert check.status == 200

      # second assert with the same sub upserts, not duplicates
      conn2 =
        build_conn()
        |> Map.put(:host, @site_host)
        |> put_req_header("origin", @good_origin)
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(key, %{"sub" => "user-42", "name" => "Renamed", "exp" => @now + 60})
        })

      assert %{"commenter" => %{"id" => same_id}} = json_response(conn2, 201)
      assert same_id == commenter["id"]

      # refresh token rotates normally
      rot =
        build_conn()
        |> Map.put(:host, @site_host)
        |> post("/api/v1/token/refresh", %{"refresh_token" => refresh})

      assert json_response(rot, 200)["refresh_token"]
    end

    test "forged signature (wrong key) → 401", %{conn: conn} do
      {site, _} = create_site()
      bogus = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(bogus, %{"sub" => "u", "exp" => @now + 60})
        })

      assert %{"error" => "invalid_assertion"} = json_response(conn, 401)
    end

    test "expired exp → 401", %{conn: conn} do
      {site, key} = create_site()

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(key, %{"sub" => "u", "exp" => @now - 5})
        })

      assert %{"error" => "expired_assertion"} = json_response(conn, 401)
    end

    test "exp window > 5 minutes rejected", %{conn: conn} do
      {site, key} = create_site()

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(key, %{"sub" => "u", "exp" => @now + 3600})
        })

      assert %{"error" => "exp_window_exceeded"} = json_response(conn, 401)
    end

    test "missing sub → 422", %{conn: conn} do
      {site, key} = create_site()

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{
          "token" => host_jwt(key, %{"name" => "no sub", "exp" => @now + 60})
        })

      assert %{"error" => "sub_required"} = json_response(conn, 422)
    end

    test "site without service key configured → 422", %{conn: conn} do
      {site, _} = create_site()

      # wipe the sealed key to simulate a legacy/manual site row
      Annotate.Repo.update!(Ecto.Changeset.change(site, service_key_encrypted: nil))

      conn =
        conn
        |> post("/api/v1/sites/#{site.slug}/token/assert", %{"token" => "anything"})

      assert %{"error" => "service_key_not_configured"} = json_response(conn, 422)
    end

    test "unknown site → 404", %{conn: conn} do
      conn =
        conn
        |> post("/api/v1/sites/who-dis/token/assert", %{"token" => "x"})

      assert %{"error" => "site_not_found"} = json_response(conn, 404)
    end
  end

  describe "service key crypto" do
    test "encrypt/decrypt roundtrip; hash matches; wrong secret fails" do
      key = Annotate.Auth.ServiceKey.generate()
      sealed = Annotate.Auth.ServiceKey.encrypt(key)

      assert {:ok, ^key} = Annotate.Auth.ServiceKey.decrypt(sealed)
      assert Annotate.Auth.ServiceKey.hash(key) == Annotate.Auth.ServiceKey.hash(key)
      assert Annotate.Auth.ServiceKey.decrypt("garbage") == :error
      assert Annotate.Auth.ServiceKey.decrypt(nil) == :error
    end
  end
end
