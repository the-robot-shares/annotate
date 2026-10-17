defmodule AnnotateWeb.Analytics do
  @moduledoc """
  Google Analytics 4 (gtag.js) for the MARKETING host pages only (landing,
  legal, sign-in). Never rendered on the annotate-srv API/embed host and never
  inside the embeddable widget (which runs on third-party sites).

  The measurement id (`G-…`, public, not a secret) comes from
  `GA_MEASUREMENT_ID` (chart `analytics.ga.measurementId`), is read in
  `config/runtime.exs` for `:prod` only, and is validated against the GA4 id
  shape so nothing but `G-[A-Z0-9]+` can ever reach a `<script>` attribute.

  Consent Mode v2 defaults are applied by `/js/ga-init.js` (external file, so no
  inline script and no CSP nonce is needed): `analytics_storage` granted,
  `ad_storage` / `ad_user_data` / `ad_personalization` denied.
  """

  @id_re ~r/^G-[A-Z0-9]{4,20}$/

  @doc "The configured id, or nil (non-prod / unset / malformed)."
  @spec measurement_id() :: String.t() | nil
  def measurement_id do
    case Application.get_env(:annotate, :ga_measurement_id) do
      id when is_binary(id) -> if Regex.match?(@id_re, id), do: id, else: nil
      _ -> nil
    end
  end

  @doc """
  The id to render for a request whose `Host` header is `host`: only the
  marketing host qualifies. Pass nil when the host is unknown (no id).
  """
  @spec measurement_id_for_host(String.t() | nil) :: String.t() | nil
  def measurement_id_for_host(host) when is_binary(host) do
    marketing = Application.get_env(:annotate, :marketing, [])
    marketing_host = Keyword.get(marketing, :host)
    api_host = Keyword.get(marketing, :api_host)
    bare = host |> String.split(":") |> hd() |> String.downcase()

    cond do
      bare == "" -> nil
      is_binary(api_host) and bare == String.downcase(api_host) -> nil
      is_binary(marketing_host) and bare == String.downcase(marketing_host) -> measurement_id()
      true -> nil
    end
  end

  def measurement_id_for_host(_), do: nil

  @doc "Convenience for layout `init/3`: id for the request's host (`server.host`)."
  def for_server(%{host: host}), do: measurement_id_for_host(host)
  def for_server(_), do: nil

  @doc "`https://www.googletagmanager.com/gtag/js?id=G-…`"
  def script_src(id), do: "https://www.googletagmanager.com/gtag/js?id=" <> id

  @script_hosts ["https://www.googletagmanager.com"]
  @connect_hosts [
    "https://www.googletagmanager.com",
    "https://*.google-analytics.com",
    "https://*.analytics.google.com"
  ]
  @img_hosts @connect_hosts

  def csp_script_hosts, do: @script_hosts
  def csp_connect_hosts, do: @connect_hosts
  def csp_img_hosts, do: @img_hosts
end
