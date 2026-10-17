defmodule Annotate.MCP.Resources.Common do
  @moduledoc """
  Resources are read-only views over the read tools: same authorization
  (per read, `Annotate.MCP.Authz`), same untrusted labelling. Any denial is
  the spec's `resource_not_found` (-32002) — no tenant oracle.
  """

  def tool_json(uri, ctx, tool, args) do
    case tool.call(args, ctx) do
      {:ok, data} -> {:ok, Jason.encode!(data)}
      {:error, _message} -> {:error, Noizu.MCP.Error.resource_not_found(uri)}
    end
  end
end
