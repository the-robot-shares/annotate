defmodule AnnotateWeb.AnnotateAPI.AnchorFidelityTest do
  use AnnotateWeb.AnnotateAPICase, async: true

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Thread

  setup %{conn: conn} do
    {site, _key} = create_site()
    author = create_commenter()
    token = issue_access(author, site)

    conn =
      conn
      |> put_req_header("origin", @good_origin)
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn, site: site, author: author}
  end

  defp post_thread(conn, site, url, extra \\ %{}) do
    body =
      Map.merge(
        %{
          "page_key" => "https://good.example/shop",
          "url" => url,
          "title" => "Shop",
          "anchor" => %{"v" => 2, "css" => "#buy", "ids" => %{"id" => "buy"}},
          "body_md" => "look"
        },
        extra
      )

    conn |> post("/api/v1/sites/#{site.slug}/threads", body) |> json_response(201)
  end

  defp list(conn, site, qs) do
    conn
    |> get("/api/v1/sites/#{site.slug}/threads?page_key=#{URI.encode_www_form("https://good.example/shop")}#{qs}")
    |> json_response(200)
    |> Map.fetch!("threads")
  end

  test "create stores and returns full page context + deep link", %{conn: conn, site: site} do
    %{"thread" => t} =
      post_thread(conn, site, "https://good.example/shop/?b=2&a=1&utm_source=nl#reviews")

    assert t["url"] == "https://good.example/shop/?b=2&a=1&utm_source=nl#reviews"
    assert t["origin"] == "https://good.example"
    assert t["page_path"] == "/shop"
    assert t["query_string"] == "b=2&a=1&utm_source=nl"
    assert t["query_params"] == %{"a" => "1", "b" => "2", "utm_source" => "nl"}
    assert t["hash"] == "reviews"
    assert t["page_title"] == "Shop"
    assert t["anchor_version"] == 2
    assert t["deep_link"] == "https://good.example/shop/?b=2&a=1&utm_source=nl#annotate=#{t["id"]}"
    assert t["anchor"]["ids"]["id"] == "buy"
  end

  test "list filters by query params, order-insensitive; no query = whole page",
       %{conn: conn, site: site} do
    %{"thread" => a} = post_thread(conn, site, "https://good.example/shop?a=1&b=2")
    %{"thread" => b} = post_thread(conn, site, "https://good.example/shop?a=9")

    ids = fn ts -> ts |> Enum.map(& &1["id"]) |> Enum.sort() end

    assert ids.(list(conn, site, "&query=b%3D2%26a%3D1")) == [a["id"]]
    assert ids.(list(conn, site, "&url=#{URI.encode_www_form("https://good.example/shop?a=9")}")) == [b["id"]]
    assert ids.(list(conn, site, "")) == Enum.sort([a["id"], b["id"]])
    assert list(conn, site, "&query=zzz%3D1") == []
  end

  test "site ignore list (utm_*, fbclid) merges campaign variants", %{conn: conn} do
    {site, _} =
      create_site(
        settings: %{
          "public_read" => true,
          "anchor" => %{"ignore_query_params" => ["utm_*", "fbclid"]}
        }
      )

    author = create_commenter()
    conn = conn |> put_req_header("authorization", "Bearer #{issue_access(author, site)}")
    %{"thread" => t} = post_thread(conn, site, "https://good.example/shop?id=7&utm_campaign=x")

    assert [%{"id" => id}] = list(conn, site, "&query=fbclid%3Dq%26id%3D7")
    assert id == t["id"]
    assert list(conn, site, "&query=id%3D8") == []
    # request-level ignore_params unions with the site config
    assert [_] = list(conn, site, "&query=id%3D7%26ref%3Dz&ignore_params=ref")
  end

  test "legacy rows (NULL query_params) stay readable and match any query", %{conn: conn, site: site, author: author} do
    t = create_thread!(site, author, %{"page_key" => "https://good.example/shop"})
    Repo.update_all(Thread, set: [query_params: nil, url: nil, page_path: nil])

    [row] = list(conn, site, "&query=anything%3D1")
    assert row["id"] == t.id
    assert row["deep_link"] == nil
    assert row["query_params"] == nil
  end

  test "url-less writer: client page_path / query_params are used", %{conn: conn, site: site} do
    %{"thread" => t} =
      post_thread(conn, site, nil, %{"url" => nil, "page_path" => "/shop/", "query_params" => %{"a" => "1"}})

    assert t["page_path"] == "/shop"
    assert t["query_params"] == %{"a" => "1"}
  end
end
