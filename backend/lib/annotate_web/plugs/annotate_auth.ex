defmodule AnnotateWeb.Plugs.AnnotateAuth do
  @moduledoc """
  Bearer-token auth for the annotate API.

  Verifies the `Annotate.Auth.ApiToken` JWT and enforces its bindings:
  - `site` claim must equal the site addressed by the path/query → else 403.
  - `origin` claim must equal the request Origin header (when present) → else 401.

  Modes:
  - `:required` — a valid token is mandatory.
  - `:optional` — anonymous requests continue WITHOUT a commenter when the
    site's `settings.public_read` is true and the method is GET/HEAD, or for
    POST (guest thread creation). Other writes and public_read=false reads
    require a token.

  On success assigns `:annotate_site`, `:annotate_commenter`, `:annotate_claims`.
  """

  import Plug.Conn

  alias Annotate.Auth.ApiToken
  alias Annotate.Sites

  def init(opts), do: %{mode: Keyword.get(opts, :mode, :required)}

  def call(conn, %{mode: mode}) do
    case authenticate(conn, mode) do
      {:ok, site, conn} ->
        conn
        |> assign(:annotate_site, site)
        |> assign(:annotate_commenter, conn.assigns[:annotate_commenter])
        |> assign(:annotate_claims, conn.assigns[:annotate_claims])

      {:error, conn} ->
        conn
    end
  end

  defp authenticate(conn, mode) do
    case fetch_site(conn) do
      {:ok, site} ->
        case extract_and_verify(conn) do
          {:ok, claims} ->
            check_bindings(conn, site, claims)

          # A *presented* token that fails must 401 even in :optional mode —
          # only the absence of a token may fall through to guest access.
          {:error, :missing} ->
            anonymous_fallback(conn, site, mode)

          {:error, _reason} ->
            {:error, respond(conn, "invalid_token", :unauthorized)}
        end

      {:error, conn} ->
        {:error, conn}
    end
  end

  defp fetch_site(conn) do
    slug = conn.params["site"]

    case slug && Sites.get_site_by_slug(slug) do
      %Annotate.Schema.Annotate.Site{} = site -> {:ok, site}
      _ -> {:error, respond(conn, "site_not_found", :not_found)}
    end
  end

  defp check_bindings(conn, site, claims) do
    cond do
      claims["site"] != site.id ->
        {:error, respond(conn, "site_mismatch", :forbidden)}

      origin_mismatch?(conn, claims) ->
        {:error, respond(conn, "origin_mismatch", :unauthorized)}

      true ->
        commenter = Sites.get_commenter(claims["sub"])

        if commenter do
          {:ok, site,
           conn
           |> assign(:annotate_commenter, commenter)
           |> assign(:annotate_claims, claims)}
        else
          {:error, respond(conn, "invalid_token", :unauthorized)}
        end
    end
  end

  defp extract_and_verify(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> ApiToken.verify(String.trim(token))
      _ -> {:error, :missing}
    end
  end

  defp origin_mismatch?(conn, claims) do
    case get_req_header(conn, "origin") do
      [origin | _] -> claims["origin"] != origin
      [] -> false
    end
  end

  defp anonymous_fallback(conn, site, :optional) do
    read? = conn.method in ["GET", "HEAD"] and Sites.public_read?(site)
    # POST on this pipeline is thread creation — guests may comment.
    guest_post? = conn.method == "POST"

    if read? or guest_post? do
      {:ok, site, assign(conn, :annotate_commenter, nil)}
    else
      {:error, respond(conn, "invalid_token", :unauthorized)}
    end
  end

  defp anonymous_fallback(conn, _site, _mode) do
    {:error, respond(conn, "invalid_token", :unauthorized)}
  end

  defp respond(conn, code, status) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"error" => code}))
    |> halt()
  end
end
