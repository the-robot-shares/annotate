defmodule AnnotateWeb.Plugs.MarketingHostGate do
  @moduledoc """
  Host split for the marketing landing.

  Both ingress hosts (annotate.therobotlives.com marketing, annotate-srv.therobotlives.com
  API) terminate at this Phoenix app. On the API host, `/` 302s to the marketing
  host so the API host never serves the landing page. On any host, the landing
  path gets a strict Content-Security-Policy — scoped to `/` only so the
  style-guide pages (Google Fonts, theme machinery) are unaffected.

  Config: `config :annotate, :marketing` (see config.exs; runtime.exs overlays
  env). Missing config = no-op (dev, localhost).
  """

  import Plug.Conn

  @cdn "https://cdn.derobot.is"

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: []} = conn, _opts) do
    marketing = Application.get_env(:annotate, :marketing, [])
    host = Keyword.get(marketing, :host)
    api_host = Keyword.get(marketing, :api_host)

    cond do
      is_binary(api_host) and api_host != "" and conn.host == api_host and
        is_binary(host) and host != "" ->
        conn
        |> put_resp_header("location", "https://#{host}/")
        |> send_resp(:found, "")
        |> halt()

      true ->
        conn
        |> put_resp_header("content-security-policy", csp(marketing))
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
        |> put_resp_header("x-frame-options", "DENY")
    end
  end

  def call(conn, _opts), do: conn

  # 'unsafe-inline' in script-src is required: Hologram's hydration bootstraps
  # through inline <script> blocks (Hologram.UI.Runtime — pageMountData +
  # csrf token) with no nonce support. Accepted because this page is fully
  # static server-rendered markup: no user-generated content is interpolated
  # into the document (the widget renders UGC inside its shadow DOM from API
  # JSON, not from this HTML).
  defp csp(marketing) do
    api_base = marketing |> Keyword.get(:api_base) |> api_base_with_ws()
    s3 = s3_origin()

    img = ["'self'", "data:", "blob:", @cdn] ++ List.wrap(s3)
    connect = ["'self'"] ++ List.wrap(api_base)

    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' #{@cdn}",
      "style-src 'self' 'unsafe-inline'",
      "img-src #{Enum.join(img, " ")}",
      "font-src 'self'",
      "connect-src #{Enum.join(connect, " ")}",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'"
    ]
    |> Enum.join("; ")
  end

  # The widget opens a websocket back to the API host for live updates.
  defp api_base_with_ws("https://" <> rest), do: ["https://#{rest}", "wss://#{rest}"]
  defp api_base_with_ws("http://" <> rest), do: ["http://#{rest}", "ws://#{rest}"]
  defp api_base_with_ws(_), do: nil

  # Screenshot/image URLs may be served straight off object storage; include the
  # configured endpoint host so they render under the CSP. Internal cluster
  # endpoints (minio .svc.cluster.local) never match browser origins in
  # practice — harmless to list, and correct for dev/ingress setups.
  defp s3_origin do
    case Application.get_env(:annotate, Annotate.Storage) do
      kw when is_list(kw) ->
        case Keyword.get(kw, :host) do
          host when is_binary(host) and host != "" -> host
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
