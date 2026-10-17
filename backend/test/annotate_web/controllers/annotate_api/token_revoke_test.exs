defmodule AnnotateWeb.AnnotateAPI.TokenRevokeTest do
  @moduledoc """
  Refresh families (T-02 reuse detection), `POST /api/v1/token/revoke`
  (widget sign-out) and the refresh response's `expires_at` (widget 1.0.3
  persisted sign-in, T-33).
  """
  use AnnotateWeb.AnnotateAPICase, async: true

  import Ecto.Query
  alias Annotate.Auth.RefreshTokens
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.RefreshToken

  setup do
    {site, _key} = create_site()
    commenter = create_commenter()

    {:ok, %{refresh_token: rt1}} =
      Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, nil, :none)

    {:ok, site: site, commenter: commenter, rt1: rt1}
  end

  defp api(origin \\ @good_origin) do
    conn = build_conn() |> Map.put(:host, @site_host)
    if origin, do: put_req_header(conn, "origin", origin), else: conn
  end

  defp refresh(rt, slug, origin \\ @good_origin),
    do: post(api(origin), "/api/v1/token/refresh?site=#{slug}", %{"refresh_token" => rt})

  defp revoke(rt, slug, origin \\ @good_origin),
    do: post(api(origin), "/api/v1/token/revoke?site=#{slug}", %{"refresh_token" => rt})

  defp row(raw),
    do: Repo.one!(from(t in RefreshToken, where: t.token_hash == ^RefreshTokens.hash(raw)))

  defp backdate_revocation(raw, seconds) do
    at = DateTime.add(DateTime.utc_now(), -seconds, :second)

    Repo.update_all(from(t in RefreshToken, where: t.token_hash == ^RefreshTokens.hash(raw)),
      set: [revoked_at: at]
    )
  end

  describe "refresh response" do
    test "carries expires_at (ms) for the access token", %{site: site, rt1: rt1} do
      body = json_response(refresh(rt1, site.slug), 200)
      now_ms = System.system_time(:millisecond)
      assert is_integer(body["expires_at"])
      assert body["expires_at"] > now_ms
      assert body["expires_at"] <= now_ms + Annotate.Auth.ApiToken.access_ttl() * 1000 + 2_000
    end

    test "rotation keeps the family", %{site: site, rt1: rt1} do
      %{"refresh_token" => rt2} = json_response(refresh(rt1, site.slug), 200)
      fam = RefreshTokens.family(row(rt1))
      assert is_binary(fam)
      assert RefreshTokens.family(row(rt2)) == fam
    end

    test "separate sign-ins get separate families", %{site: site, commenter: commenter, rt1: rt1} do
      {:ok, %{refresh_token: other}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, nil, :none)

      refute RefreshTokens.family(row(other)) == RefreshTokens.family(row(rt1))
    end
  end

  describe "reuse detection" do
    test "replay inside the leeway (tab race) fails without killing the family", %{
      site: site,
      rt1: rt1
    } do
      %{"refresh_token" => rt2} = json_response(refresh(rt1, site.slug), 200)
      assert %{"error" => "invalid_refresh_token"} = json_response(refresh(rt1, site.slug), 401)
      assert %{"refresh_token" => _} = json_response(refresh(rt2, site.slug), 200)
    end

    test "replay past the leeway revokes the whole family", %{
      site: site,
      commenter: commenter,
      rt1: rt1
    } do
      {:ok, %{refresh_token: unrelated}} =
        Annotate.Auth.ApiToken.issue_pair(commenter, site, @good_origin, nil, :none)

      %{"refresh_token" => rt2} = json_response(refresh(rt1, site.slug), 200)
      backdate_revocation(rt1, RefreshTokens.reuse_leeway_seconds() + 5)

      assert %{"error" => "invalid_refresh_token"} = json_response(refresh(rt1, site.slug), 401)
      # the descendant held by the "victim" (or the thief) is dead too
      assert %{"error" => "invalid_refresh_token"} = json_response(refresh(rt2, site.slug), 401)
      # a different sign-in (other family) is untouched
      assert %{"refresh_token" => _} = json_response(refresh(unrelated, site.slug), 200)
    end

    test "concurrent presentations of one token: exactly one rotation wins", %{
      site: site,
      rt1: rt1
    } do
      results =
        1..4
        |> Enum.map(fn _ ->
          # $callers propagation shares the sandbox connection with the task.
          Task.async(fn -> RefreshTokens.rotate(rt1, @good_origin) end)
        end)
        |> Enum.map(&Task.await/1)

      _ = site
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :invalid}))
    end
  end

  describe "POST /api/v1/token/revoke" do
    test "revokes the presented token's family; refresh then fails", %{site: site, rt1: rt1} do
      %{"refresh_token" => rt2} = json_response(refresh(rt1, site.slug), 200)
      assert %{"revoked" => true} = json_response(revoke(rt2, site.slug), 200)
      assert %{"error" => "invalid_refresh_token"} = json_response(refresh(rt2, site.slug), 401)
    end

    test "presenting an older (rotated) token of the family also signs the chain out", %{
      site: site,
      rt1: rt1
    } do
      %{"refresh_token" => rt2} = json_response(refresh(rt1, site.slug), 200)
      assert %{"revoked" => true} = json_response(revoke(rt1, site.slug), 200)
      assert %{"error" => "invalid_refresh_token"} = json_response(refresh(rt2, site.slug), 401)
    end

    test "unknown token is a 200 no-op (not an oracle)", %{site: site} do
      assert %{"revoked" => true} = json_response(revoke("not-a-token", site.slug), 200)
    end

    test "missing refresh_token → 400", %{site: site} do
      conn = post(api(), "/api/v1/token/revoke?site=#{site.slug}", %{})
      assert %{"error" => "refresh_token_required"} = json_response(conn, 400)
    end

    test "foreign browser origin is refused by per-site CORS and burns nothing", %{
      site: site,
      rt1: rt1
    } do
      assert json_response(revoke(rt1, site.slug, @evil_origin), 403)
      assert %{"refresh_token" => _} = json_response(refresh(rt1, site.slug), 200)
    end

    test "CORS preflight for the widget's origin is allowed", %{site: site} do
      conn =
        api()
        |> put_req_header("access-control-request-method", "POST")
        |> options("/api/v1/token/revoke?site=#{site.slug}")

      assert conn.status == 204
      assert get_resp_header(conn, "access-control-allow-origin") == [@good_origin]
    end
  end
end
