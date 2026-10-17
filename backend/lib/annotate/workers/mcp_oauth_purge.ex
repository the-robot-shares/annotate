defmodule Annotate.Workers.MCPOAuthPurge do
  @moduledoc """
  Every 15 minutes: delete expired MCP OAuth rows (login states,
  authorization codes, refresh tokens past expiry, tracked access tokens) via
  the library's `Store.Ecto.purge_expired/2`. Nothing in noizu_mcp sweeps on
  its own. Audit rows (`mcp_audit_events`) are kept.
  """
  use Oban.Worker, queue: :cleanup, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    {store, opts} = Annotate.MCP.Config.store()

    case store.purge_expired(DateTime.utc_now(), Keyword.put(opts, :track_access_tokens, true)) do
      {:ok, _counts} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
