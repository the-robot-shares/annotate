defmodule Annotate.MCP.RateLimit do
  @moduledoc """
  Rate limits for the MCP surface (Hammer, ETS backend, single replica).

  * `oauth/3` — the library's `rate_limit:` hook for the authorization
    server endpoints, per client IP (`AnnotateWeb.Plugs.RateLimit.client_ip/1`,
    Cloudflare-aware). Registration is the tight one: an unauthenticated
    caller can create rows there.
  * `tool/3` — per `(user, client_id)` tool budgets: 120 reads and 30
    writes per minute (`Annotate.MCP.Authz`).
  """

  @oauth_limits %{
    register: {3_600_000, 20},
    authorize: {60_000, 30},
    consent: {60_000, 30},
    token: {60_000, 60},
    revoke: {60_000, 60},
    api_token: {60_000, 30}
  }

  @tool_limits %{read: {60_000, 120}, write: {60_000, 30}}

  @doc "Library hook: `(endpoint, conn, config) -> :ok | {:error, retry_after_s}`."
  def oauth(endpoint, conn, _config) do
    {period, limit} = Map.get(@oauth_limits, endpoint, {60_000, 60})
    ip = AnnotateWeb.Plugs.RateLimit.client_ip(conn)
    check("mcp_oauth:#{endpoint}:#{ip}", period, limit)
  end

  @doc "Per (user, client) tool budget. `kind` is `:read | :write`."
  def tool(kind, user_id, client_id) when kind in [:read, :write] do
    {period, limit} = Map.fetch!(@tool_limits, kind)
    check("mcp_tool:#{kind}:#{user_id}:#{client_id}", period, limit)
  end

  def tool_limits, do: @tool_limits

  defp check(key, period, limit) do
    case Hammer.check_rate(key, period, limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, div(period, 1000)}
      _ -> :ok
    end
  end
end
