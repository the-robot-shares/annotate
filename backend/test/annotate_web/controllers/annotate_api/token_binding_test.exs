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
      |> post("/api/v1/token/refresh", %{"refresh_token" => refresh1})

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
      |> post("/api/v1/token/refresh", %{"refresh_token" => refresh1})

    assert %{"error" => "invalid_refresh_token"} = json_response(reuse, 401)
  end
end
