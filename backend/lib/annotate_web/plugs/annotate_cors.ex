defmodule AnnotateWeb.Plugs.AnnotateCORS do
  @moduledoc """
  Per-site CORS for `/api/v1`.

  Echoes `Access-Control-Allow-Origin` ONLY when the request's Origin header
  is a member of the addressed site's `allowed_origins` — exact match, no
  wildcard, no credentials. The site is resolved from the path
  (`/api/v1/sites/:slug/...`) or the `site` query param (token-bound routes
  like `POST /api/v1/threads/:id/comments?site=<slug>` carry it explicitly so
  preflights — which have no body — can be authorized).

  Runs at the endpoint, BEFORE body parsers, so OPTIONS preflights are
  answered without parsing. Requests with no Origin header (non-browser
  clients) pass through untouched. Foreign origins get a bare 403 with no
  ACAO headers. The scaffold's broad `AnnotateWeb.Plugs.CORS` still runs
  after this plug for everything outside `/api/v1`.
  """

  import Plug.Conn

  @allowed_headers "authorization, content-type, x-annotate-site"
  @allowed_methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"

  def init(opts), do: opts

  # Annotate-owned subtrees. On these the scaffold's broad CORS plug must not
  # stamp its permissive `*` — claiming the conn makes it a passthrough.
  @annotate_prefixes [["sites"], ["threads"], ["comments"], ["attachments"], ["token"]]

  defp maybe_claim(conn, rest) do
    if Enum.any?(@annotate_prefixes, fn p -> List.starts_with?(rest, p) end) do
      put_private(conn, :annotate_cors_claimed, true)
    else
      conn
    end
  end

  def call(%{path_info: ["api", "v1" | rest]} = conn, _opts) do
    conn = maybe_claim(conn, rest)

    case get_req_header(conn, "origin") do
      [] ->
        conn

      [origin | _] ->
        case resolve_site(conn) do
          {:ok, site} ->
            if Annotate.Sites.allowed_origin?(site, origin) do
              allow(conn, origin)
            else
              deny(conn, origin)
            end

          :error ->
            deny(conn, origin)
        end
    end
  end

  def call(conn, _opts), do: conn

  defp allow(conn, origin) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", @allowed_methods)
      |> put_resp_header("access-control-allow-headers", @allowed_headers)
      |> put_resp_header("access-control-max-age", "3600")
      |> put_resp_header("vary", "origin")

    case conn.method do
      "OPTIONS" -> conn |> send_resp(:no_content, "") |> halt()
      _ -> conn
    end
  end

  defp deny(conn, _origin) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, ~s({"error":"origin_not_allowed"}))
    |> halt()
  end

  defp resolve_site(conn) do
    conn = fetch_query_params(conn)

    slug =
      case conn.path_info do
        ["api", "v1", "sites", slug | _] -> slug
        _ -> conn.query_params["site"]
      end

    case slug && Annotate.Sites.get_site_by_slug(slug) do
      %Annotate.Schema.Annotate.Site{} = site -> {:ok, site}
      _ -> :error
    end
  end
end
