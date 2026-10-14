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
    site = conn.params["site"]

    key =
      if is_binary(site) and site != "" do
        "#{action}:#{ip}:#{site}"
      else
        "#{action}:#{ip}"
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

  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
