defmodule Annotate.MCP.Grants do
  @moduledoc """
  A user's connected MCP clients (`/dashboard/agents`): list and revoke.

  A "connection" is a recorded consent `(subject, client_id)` in
  `mcp_oauth_consents`. Revoking one, in this order:

    1. deletes the consent — `Annotate.MCP.Verifier` requires it on every
       `/mcp` request, so a live access token dies on its NEXT request;
    2. marks every tracked access token of the pair revoked;
    3. revokes every refresh token of the pair (no silent re-mint).

  The client row itself stays (another user may use the same registered
  client; CIMD clients are shared by design).
  """

  alias Annotate.MCP.Config
  alias Annotate.Repo

  @doc "Connected clients for `user_id`, newest grant first."
  def list(user_id) when is_binary(user_id) do
    sql = """
    SELECT c.client_id, cl.client_name, cl.client_id_kind, c.scope, c.granted_at,
           (SELECT max(t.inserted_at) FROM mcp_oauth_access_tokens t
             WHERE t.subject = c.subject AND t.client_id = c.client_id) AS last_token_at
      FROM mcp_oauth_consents c
      JOIN mcp_oauth_clients cl ON cl.client_id = c.client_id
     WHERE c.subject = $1 AND (c.expires_at IS NULL OR c.expires_at > now())
     ORDER BY c.granted_at DESC
    """

    case Repo.query(sql, [user_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [client_id, name, kind, scope, granted_at, last_token_at] ->
          %{
            client_id: client_id,
            # Self-registered: the client chose this name. Render escaped, label as such.
            untrusted_client_name: name,
            kind: kind,
            scopes: String.split(scope || "", " ", trim: true),
            granted_at: granted_at,
            last_token_at: last_token_at
          }
        end)

      _ ->
        []
    end
  end

  @doc "Revoke `client_id` for `user_id` (consent, access tokens, refresh tokens)."
  def revoke(user_id, client_id) when is_binary(user_id) and is_binary(client_id) do
    {store, opts} = Config.store()
    opts = Keyword.put(opts, :track_access_tokens, true)

    _ = store.revoke_consent(user_id, client_id, opts)

    {:ok, _} =
      Repo.query(
        "UPDATE mcp_oauth_access_tokens SET revoked_at = now() WHERE subject = $1 AND client_id = $2 AND revoked_at IS NULL",
        [user_id, client_id]
      )

    _ = store.revoke_subject_tokens(user_id, client_id, opts)
    :ok
  end
end
