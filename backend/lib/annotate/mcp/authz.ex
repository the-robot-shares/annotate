defmodule Annotate.MCP.Authz do
  @moduledoc """
  Per-call authorization for every MCP tool, resource and prompt.

  Nothing from the MCP session is trusted across calls. On each call:

    1. **Token claims** of *this* request (`ctx.auth`, verified by
       `Annotate.MCP.Verifier` on the HTTP request that carried it).
    2. **Scope** — the tool's required scope must be granted
       (`comments:read` / `comments:write` / `comments:moderate`).
    3. **Rate limit** per `(user, client_id)` — reads 120/min, writes 30/min.
    4. **User** re-read from the DB: not deleted, not suspended/disabled,
       through the invite gate (`Annotate.Dashboard.Access.allowed?/1`).
    5. **Site** by slug (never a raw site id) and the user's membership role
       re-read from `site_members` (`Annotate.SiteMembers.member_role/2`).
       A site the user is not a member of — or that does not exist — is
       `:not_found` either way (no tenant existence oracle).

  Every denial, and every write (success or failure), lands in
  `mcp_audit_events` (`audit/5`); comment bodies never do (only a SHA-256 of
  the canonical arguments).
  """

  import Ecto.Query

  alias Annotate.Dashboard.Access
  alias Annotate.Repo
  alias Annotate.Schema.Users.User
  alias Annotate.SiteMembers
  alias Annotate.Sites

  defmodule Caller do
    @moduledoc false
    defstruct [:user, :user_id, :client_id, :scopes, :ip, :site, :role, :tool]
  end

  @type reason ::
          :unauthenticated
          | :insufficient_scope
          | :rate_limited
          | :access_denied
          | :not_found
          | :forbidden

  @doc "True when the users row may act through MCP right now."
  def user_allowed?(%User{deleted_at: nil, status: status} = user)
      when status not in [:suspended, :deleted, :other],
      do: Access.allowed?(user)

  def user_allowed?(_), do: false

  @doc """
  Authorize a tool call. Options:

    * `:tool` (required) — name, for the audit log
    * `:scope` — required OAuth scope (default `"comments:read"`)
    * `:kind` — `:read | :write` rate-limit bucket (default `:read`)
    * `:site` — site slug to resolve (optional)
    * `:min_role` — `:member | :admin | :owner` on that site (default `:member`)
    * `:args` — call arguments (hashed into the audit row on denial)

  `{:ok, %Caller{}}` or `{:error, reason}` (already audited).
  """
  def authorize(ctx, opts) do
    tool = Keyword.fetch!(opts, :tool)
    scope = Keyword.get(opts, :scope, "comments:read")
    kind = Keyword.get(opts, :kind, :read)
    args = Keyword.get(opts, :args, %{})

    with {:ok, caller} <- caller(ctx, tool),
         :ok <- check_scope(caller, scope),
         :ok <- check_rate(caller, kind),
         {:ok, caller} <- load_user(caller),
         {:ok, caller} <-
           load_site(caller, Keyword.get(opts, :site), Keyword.get(opts, :min_role, :member)) do
      {:ok, caller}
    else
      {:error, reason, caller} ->
        audit(caller, tool, args, "denied", reason)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Re-check the caller's role on its resolved site (moderation decisions)."
  def role_at_least?(%Caller{role: role}, min), do: SiteMembers.role_at_least?(role, min)

  @doc "Granted scopes on this request."
  def scope?(%Caller{scopes: scopes}, scope), do: scope in scopes

  @doc "Sites the caller is a member of (with role), freshest first."
  def member_sites(%Caller{user_id: user_id}), do: SiteMembers.list_sites_for_user(user_id)

  # ── steps ─────────────────────────────────────────────────────

  defp caller(ctx, tool) do
    claims =
      case ctx do
        %{auth: %Noizu.MCP.Auth.Principal{claims: claims}} when is_map(claims) -> claims
        %{assigns: %{auth_claims: claims}} when is_map(claims) -> claims
        _ -> nil
      end

    case claims do
      %{"sub" => sub, "client_id" => client_id} = claims when is_binary(sub) ->
        {:ok,
         %Caller{
           user_id: sub,
           client_id: client_id,
           scopes: Noizu.MCP.Auth.JWTVerifier.scopes(claims),
           ip: get_in(ctx_assigns(ctx), [:client_ip]),
           tool: tool
         }}

      _ ->
        {:error, :unauthenticated}
    end
  end

  defp ctx_assigns(%{assigns: assigns}) when is_map(assigns), do: assigns
  defp ctx_assigns(_), do: %{}

  defp check_scope(caller, scope) do
    if scope in caller.scopes, do: :ok, else: {:error, :insufficient_scope, caller}
  end

  defp check_rate(caller, kind) do
    case Annotate.MCP.RateLimit.tool(kind, caller.user_id, caller.client_id) do
      :ok -> :ok
      {:error, _retry} -> {:error, :rate_limited, caller}
    end
  end

  defp load_user(caller) do
    user =
      with {:ok, id} <- Ecto.UUID.cast(caller.user_id),
           do: Repo.get(User, id)

    if user_allowed?(user),
      do: {:ok, %{caller | user: user}},
      else: {:error, :access_denied, caller}
  end

  defp load_site(caller, nil, _min_role), do: {:ok, caller}

  defp load_site(caller, slug, min_role) when is_binary(slug) do
    with %{} = site <- Sites.get_site_by_slug(slug),
         role when role != nil <- SiteMembers.member_role(site, caller.user_id) do
      caller = %{caller | site: site, role: role}

      if SiteMembers.role_at_least?(role, min_role),
        do: {:ok, caller},
        else: {:error, :forbidden, caller}
    else
      _ -> {:error, :not_found, %{caller | site: %{slug: slug}}}
    end
  end

  defp load_site(caller, _bad, _min_role), do: {:error, :not_found, caller}

  # ── audit ─────────────────────────────────────────────────────

  @doc """
  Append an audit row. `outcome` is `"ok" | "error" | "denied"`. Never raises:
  an audit failure is logged, and the caller's result stands.
  """
  def audit(%Caller{} = caller, tool, args, outcome, reason \\ nil) do
    {site_id, site_slug} =
      case caller.site do
        %Annotate.Schema.Annotate.Site{id: id, slug: slug} -> {id, slug}
        %{slug: slug} -> {nil, slug}
        _ -> {nil, nil}
      end

    row = %{
      id: Ecto.UUID.bingenerate(),
      user_id: dump_uuid(caller.user_id),
      client_id: caller.client_id,
      site_id: dump_uuid(site_id),
      site_slug: truncate(site_slug, 255),
      tool: tool,
      args_hash: args_hash(args),
      outcome: outcome,
      reason: reason && truncate(to_string(reason), 255),
      ip: caller.ip,
      inserted_at: DateTime.utc_now()
    }

    Repo.insert_all("mcp_audit_events", [row])
    :ok
  rescue
    e ->
      require Logger
      Logger.error("[mcp] audit insert failed: #{inspect(e.__struct__)} tool=#{tool}")
      :ok
  end

  @doc "Most recent audit rows for a user (dashboard Agents page)."
  def recent_audit(user_id, limit \\ 50) do
    from(a in "mcp_audit_events",
      where: a.user_id == type(^user_id, :binary_id),
      order_by: [desc: a.inserted_at],
      limit: ^limit,
      select: %{
        client_id: a.client_id,
        site_slug: a.site_slug,
        tool: a.tool,
        outcome: a.outcome,
        reason: a.reason,
        at: a.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "SHA-256 hex of the canonical JSON of `args` (keys sorted)."
  def args_hash(args) do
    :crypto.hash(:sha256, canonical(args)) |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    inner =
      map
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.sort()
      |> Enum.map_join(",", fn {k, v} -> Jason.encode!(k) <> ":" <> canonical(v) end)

    "{" <> inner <> "}"
  end

  defp canonical(list) when is_list(list),
    do: "[" <> Enum.map_join(list, ",", &canonical/1) <> "]"

  defp canonical(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: Jason.encode!(to_string(atom))

  defp canonical(other), do: Jason.encode!(other)

  defp dump_uuid(nil), do: nil

  defp dump_uuid(id) do
    case Ecto.UUID.dump(id) do
      {:ok, bin} -> bin
      :error -> nil
    end
  end

  defp truncate(nil, _), do: nil
  defp truncate(s, n) when is_binary(s), do: String.slice(s, 0, n)

  @doc "Tool-facing message for a denial (no tenant oracle)."
  def message(:unauthenticated), do: "unauthenticated: sign in again (reconnect the MCP client)"

  def message(:insufficient_scope),
    do:
      "insufficient_scope: this connection was not granted the permission this tool needs; reconnect and approve it"

  def message(:rate_limited), do: "rate_limited: too many calls this minute; slow down and retry"

  def message(:access_denied),
    do:
      "access_denied: this annotate account cannot use the dashboard (disabled or invite pending)"

  def message(:not_found),
    do: "not_found: no such site/thread/comment, or you are not a member of its site"

  def message(:forbidden), do: "forbidden: your role on this site does not allow that"
  def message(other), do: "error: #{other}"
end
