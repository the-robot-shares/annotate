defmodule AnnotateWeb.Plugs.RateLimit do
  @behaviour Plug
  import Plug.Conn

  @default_limits %{
    auth: {10, 60_000},
    auth_sensitive: {5, 60_000},
    # Annotate embed API writes (threads/comments/attachments/token endpoints).
    # Reads pass through uncounted — only write methods consume budget.
    annotate_write: {60, 60_000}
  }

  # Actions that count POST/PATCH/PUT/DELETE only.
  @writes_only [:annotate_write]

  @impl true
  def init(opts) do
    action = Keyword.fetch!(opts, :action)
    {limit, period} = @default_limits[action] || {10, 60_000}
    %{action: action, limit: limit, period: period, writes_only: action in @writes_only}
  end

  @impl true
  def call(conn, %{writes_only: true} = state) do
    if conn.method in ["GET", "HEAD", "OPTIONS"] do
      conn
    else
      check(conn, state)
    end
  end

  def call(conn, state), do: check(conn, state)

  defp check(conn, %{action: action, limit: limit, period: period}) do
    ip = client_ip(conn)
    # Scope the bucket per site when the route addresses one, so a noisy
    # tenant cannot exhaust another tenant's budget on a shared egress IP.
    # The site key is attacker-controlled: only an EXISTING slug gets its own
    # bucket; every unknown value shares one, so spoofed values cannot mint
    # unlimited fresh buckets.
    key =
      case site_bucket(conn.params["site"]) do
        nil -> "#{action}:#{ip}"
        site -> "#{action}:#{ip}:#{site}"
      end

    case Hammer.check_rate(key, period, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        retry_after = div(period, 1000)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Too many requests. Try again later."}))
        |> halt()
    end
  end

  @unknown_site "_unknown"

  defp site_bucket(site) when is_binary(site) and site != "" do
    if Annotate.Sites.get_site_by_slug(site), do: site, else: @unknown_site
  end

  defp site_bucket(nil), do: nil
  defp site_bucket(_), do: @unknown_site

  @doc """
  Client IP for bucketing. Never trusts the left of `X-Forwarded-For` (the
  client controls it). With `N` trusted proxy hops
  (`:annotate, :rate_limit_trusted_hops`, env `RATE_LIMIT_TRUSTED_HOPS`,
  default 1 = ingress-nginx) the address is the Nth entry from the RIGHT —
  the one our own proxy appended. `0`, a missing/short header or an
  unparsable entry falls back to `conn.remote_ip`.
  """
  def client_ip(conn) do
    hops = Application.get_env(:annotate, :rate_limit_trusted_hops, 1)
    peer = conn.remote_ip |> :inet.ntoa() |> to_string()

    with true <- is_integer(hops) and hops > 0,
         [header | _] <- get_req_header(conn, "x-forwarded-for"),
         entries = header |> String.split(",") |> Enum.map(&String.trim/1),
         true <- length(entries) >= hops,
         candidate = Enum.at(entries, -hops),
         {:ok, ip} <- :inet.parse_address(String.to_charlist(candidate)) do
      ip |> :inet.ntoa() |> to_string()
    else
      _ -> peer
    end
  end
end
