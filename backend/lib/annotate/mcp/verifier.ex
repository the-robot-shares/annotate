defmodule Annotate.MCP.Verifier do
  @moduledoc """
  Bearer verification for `/mcp` (runs on EVERY HTTP request, not once per
  MCP session).

  1. `Noizu.MCP.Auth.JWTVerifier` — HS256 with the MCP-only key, `iss` = the
     issuer, `aud` byte-matched to `https://<host>/mcp`, `exp`/`nbf`, a `sub`,
     and the base `comments:read` scope.
  2. The token's `jti` is not revoked (`track_access_tokens: true`).
  3. The `(sub, client_id)` consent still exists — revoking a client from
     `/dashboard/agents` deletes it, so an already-issued access token dies on
     its next request rather than at its 15-minute expiry.

  Every rejection is the same `{:error, :invalid_token}` (no oracle). Whether
  the human behind `sub` may still act (active, invite gate, site membership)
  is `Annotate.MCP.Authz`'s job, per tool call.
  """

  @behaviour Noizu.MCP.Auth.TokenVerifier

  alias Annotate.MCP.Config

  @impl true
  def verify(token, conn_info, _opts) do
    case Noizu.MCP.Auth.JWTVerifier.verify(token, conn_info, jwt_opts()) do
      {:ok, %{"sub" => sub, "client_id" => client_id, "jti" => jti} = claims}
      when is_binary(sub) and is_binary(client_id) and is_binary(jti) ->
        if live?(sub, client_id, jti), do: {:ok, claims}, else: {:error, :invalid_token}

      {:ok, _claims} ->
        {:error, :invalid_token}

      other ->
        other
    end
  end

  def jwt_opts do
    [
      resource: Config.resource(),
      issuer: Config.issuer(),
      secret: {Config, :secret},
      algorithms: ["HS256"],
      scopes: ["comments:read"]
    ]
  end

  defp live?(sub, client_id, jti) do
    {store, opts} = Config.store()
    opts = Keyword.put(opts, :track_access_tokens, true)

    store.access_token_revoked?(jti, opts) == false and
      match?({:ok, _}, store.get_consent(sub, client_id, opts))
  end
end
