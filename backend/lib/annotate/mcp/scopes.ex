defmodule Annotate.MCP.Scopes do
  @moduledoc """
  Which OAuth scope each MCP tool needs, and the HTTP-level step-up.

  `comments:read` is the base scope of every token (required by the
  verifier). Write tools need more; when a `tools/call` names one and the
  token lacks its scope, `/mcp` answers **403** with
  `WWW-Authenticate: Bearer error="insufficient_scope", scope="…"` so the
  client can send the user back through consent to grant it (step-up).

  The JSON body is decoded once by `AnnotateWeb.MCP.Plug`, which then sets
  the private request header `x-annotate-mcp-required-scope` (any
  client-sent copy is stripped first) for `Annotate.MCP.Verifier` to enforce.
  Tools re-check the scope themselves too (`Annotate.MCP.Authz`).
  """

  @base "comments:read"
  @header "x-annotate-mcp-required-scope"

  @tool_scopes %{
    "reply_to_thread" => "comments:write",
    "resolve_thread" => "comments:write",
    "reopen_thread" => "comments:write",
    "delete_comment" => "comments:moderate"
  }

  def base, do: @base
  def header, do: @header

  @doc "Scope a tool needs (base read scope for anything not listed)."
  def for_tool(name) when is_binary(name), do: Map.get(@tool_scopes, name, @base)
  def for_tool(_), do: @base

  @doc "Scopes required by a decoded JSON-RPC message (or batch)."
  def required(messages) when is_list(messages),
    do: messages |> Enum.flat_map(&required/1) |> Enum.uniq()

  def required(%{"method" => "tools/call", "params" => %{"name" => name}}) do
    case for_tool(name) do
      @base -> []
      scope -> [scope]
    end
  end

  def required(_), do: []
end
