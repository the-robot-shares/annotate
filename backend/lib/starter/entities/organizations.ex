defmodule Starter.Organizations do
  @moduledoc """
  Context for Starter.Organizations
  """
  alias Starter.Organizations.Organization, as: Entity
  alias Starter.Schema.Organizations.Organization, as: Schema
  alias Starter.Schema.Organizations.InviteToken, as: InviteTokenSchema
  alias Starter.Schema.Organizations.InviteTokenRedemption, as: InviteTokenRedemptionSchema
  alias Starter.Schema.Authz.ScopedMembership, as: ScopedMembershipSchema
  use Noizu.Repo
  def_repo(entity: Entity)
  import Ecto.Query

  # <REMOVED UUID HERE> list :: auto-generated pointer for public function list
  def list(context, options \\ []) do
    settings = Noizu.Entity.Meta.persistence(Entity) |> hd

    Starter.Repo.all(Schema)
    |> Enum.map(fn record ->
      {:ok, entity} = Entity.from_record(record, settings, context, options)
      {:ok, entity} = __after_get__(entity, context, options)
      entity
    end)
  end

  # <REMOVED UUID HERE> get_organization :: auto-generated pointer for public function get_organization
  def get_organization(id, context, options \\ []), do: get(id, context, options)

  # <REMOVED UUID HERE> create_organization_with_owner :: auto-generated pointer for public function create_organization_with_owner
  def create_organization_with_owner(attrs, user_id) do
    Starter.Repo.transaction(fn ->
      with {:ok, org} <- %Schema{} |> Schema.changeset(attrs) |> Starter.Repo.insert(),
           {:ok, _membership} <-
             Starter.Authz.ScopedMemberships.add_member("organization", org.id, user_id, "owner") do
        org
      else
        {:error, reason} -> Starter.Repo.rollback(reason)
      end
    end)
  end

  # <REMOVED UUID HERE> list_user_organizations :: auto-generated pointer for public function list_user_organizations
  def list_user_organizations(user_id) do
    from(sm in ScopedMembershipSchema,
      join: o in Schema,
      on: o.id == sm.resource_id,
      join: g in Starter.Schema.Authz.Group,
      on: g.id == sm.group_id,
      where:
        sm.member_type == "user" and sm.member_id == ^user_id and
          sm.resource_type == "organization",
      where: is_nil(sm.expires_at) or sm.expires_at > ^DateTime.utc_now(),
      select: %{id: o.id, slug: o.slug, name: o.name, role: g.name}
    )
    |> Starter.Repo.all()
  end

  # <REMOVED UUID HERE> authorize :: auto-generated pointer for public function authorize
  def authorize(user_id, organization_id, required_role) do
    Starter.Authz.authorize(user_id, "organization", organization_id, required_role)
  end

  # <REMOVED UUID HERE> list_members :: auto-generated pointer for public function list_members
  def list_members(organization_id) do
    Starter.Authz.ScopedMemberships.list_for_resource("organization", organization_id)
  end

  # <REMOVED UUID HERE> create_invite_token :: auto-generated pointer for public function create_invite_token
  def create_invite_token(attrs) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    key_prefix = String.slice(raw_token, 0, 8)
    token_hash = Bcrypt.hash_pwd_salt(raw_token)

    result =
      %InviteTokenSchema{}
      |> InviteTokenSchema.changeset(
        Map.merge(attrs, %{
          token_hash: token_hash,
          key_prefix: key_prefix
        })
      )
      |> Starter.Repo.insert()

    case result do
      {:ok, invite} -> {:ok, invite, raw_token}
      error -> error
    end
  end

  # <REMOVED UUID HERE> find_active_invite_by_raw_token :: auto-generated pointer for public function find_active_invite_by_raw_token
  def find_active_invite_by_raw_token(raw_token, email \\ nil) when is_binary(raw_token) do
    key_prefix = String.slice(raw_token, 0, 8)
    now = DateTime.utc_now()

    from(t in InviteTokenSchema,
      where: t.key_prefix == ^key_prefix and t.revoked == false,
      where: is_nil(t.starts_at) or t.starts_at <= ^now,
      where: is_nil(t.expires_at) or t.expires_at > ^now,
      where: is_nil(t.max_uses) or t.uses < t.max_uses
    )
    |> match_invite(raw_token, email)
  end

  @doc """
  Like `find_active_invite_by_raw_token/2`, but a live (unrevoked, started,
  unexpired) invite whose uses are spent is still returned. Lets the redeem
  flow tell "already used" from "unknown" off the one bcrypt-verified row —
  no second hash pass over the candidates.
  """
  def find_live_invite_by_raw_token(raw_token, email \\ nil) when is_binary(raw_token) do
    key_prefix = String.slice(raw_token, 0, 8)
    now = DateTime.utc_now()

    from(t in InviteTokenSchema,
      where: t.key_prefix == ^key_prefix and t.revoked == false,
      where: is_nil(t.starts_at) or t.starts_at <= ^now,
      where: is_nil(t.expires_at) or t.expires_at > ^now
    )
    |> match_invite(raw_token, email)
  end

  defp match_invite(query, raw_token, email) do
    email = email && Starter.Users.Credentials.standardize_email(email)

    query
    |> Starter.Repo.all()
    |> Enum.find(fn token ->
      email_matches? =
        is_nil(token.email) ||
          is_nil(email) ||
          Starter.Users.Credentials.standardize_email(token.email) == email

      email_matches? && Bcrypt.verify_pass(raw_token, token.token_hash)
    end)
    |> case do
      nil -> {:error, :invalid_token}
      token -> {:ok, token}
    end
  end

  @doc """
  True when `raw_token` names a live (unrevoked, started, unexpired) invite
  bound to `email` (or to no email) whose uses are spent. Lets the
  authenticated, rate-limited redeem answer 409 "already used" instead of the
  generic 404 — never used by the public lookup. Resolves via
  `find_live_invite_by_raw_token/2` (one bcrypt pass) and reads spent-ness
  straight off the found row.
  """
  def exhausted_invite?(raw_token, email \\ nil) when is_binary(raw_token) do
    case find_live_invite_by_raw_token(raw_token, email) do
      {:ok, token} -> not is_nil(token.max_uses) and token.uses >= token.max_uses
      _ -> false
    end
  end

  # <REMOVED UUID HERE> increment_invite_uses :: auto-generated pointer for public function increment_invite_uses
  def increment_invite_uses(invite_token) do
    from(t in InviteTokenSchema, where: t.id == ^invite_token.id)
    |> Starter.Repo.update_all(inc: [uses: 1, redemption_count: 1])
  end

  # <REMOVED UUID HERE> redeem_invite_for_user :: auto-generated pointer for public function redeem_invite_for_user
  @doc """
  Records a redemption and consumes one invite use.

  Idempotent per user: a (invite_token_id, user_id) pair is unique in the DB,
  and the insert itself — not a read-then-insert — is the arbiter, so a
  repeat by the same user returns `{:ok, :already_redeemed}` consuming
  nothing, even under a race. A fresh redemption still atomically enforces
  `uses < max_uses` via the guarded increment; the loser of an exhaustion
  race rolls back entirely (redemption row included).
  """
  def redeem_invite_for_user(invite_token, user, conn \\ nil) do
    user_id = Map.get(user, :id)
    now = DateTime.utc_now()

    Starter.Repo.transaction(fn ->
      {rows, _} =
        Starter.Repo.insert_all(
          InviteTokenRedemptionSchema,
          [
            %{
              id: UUID.uuid4(),
              invite_token_id: invite_token.id,
              user_id: user_id,
              redeemed_at: now,
              remote_ip: remote_ip(conn),
              user_agent: user_agent(conn),
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: :nothing,
          conflict_target: [:invite_token_id, :user_id]
        )

      if rows == 0 do
        :already_redeemed
      else
        {count, _} =
          from(t in InviteTokenSchema,
            where: t.id == ^invite_token.id,
            where: is_nil(t.max_uses) or t.uses < t.max_uses
          )
          |> Starter.Repo.update_all(
            inc: [uses: 1, redemption_count: 1],
            set: [
              accepted_by: user_id,
              accepted_at: invite_token.accepted_at || now,
              status: "accepted",
              updated_at: now
            ]
          )

        if count == 0, do: Starter.Repo.rollback(:invite_exhausted), else: :ok
      end
    end)
  end

  defp remote_ip(nil), do: nil
  defp remote_ip(%{remote_ip: nil}), do: nil
  defp remote_ip(%{remote_ip: remote_ip}), do: remote_ip |> :inet.ntoa() |> to_string()

  defp user_agent(nil), do: nil
  defp user_agent(conn), do: Plug.Conn.get_req_header(conn, "user-agent") |> List.first()

  # ── Invite admin surface ──────────────────────────────────────

  # Roles an inviter may grant. `owner` is deliberately absent — an invite
  # must never mint a second org owner. Mirrors the roles add_member/4 accepts.
  @invite_roles ~w(admin member viewer)

  @doc "Roles that may be attached to an invite token (never `owner`)."
  def invite_roles, do: @invite_roles

  @doc "Normalizes + validates a caller-supplied invite role."
  def validate_invite_role(nil), do: {:ok, "viewer"}

  def validate_invite_role(role) when is_binary(role) do
    normalized = role |> String.trim() |> String.downcase()

    if normalized in @invite_roles, do: {:ok, normalized}, else: {:error, :invalid_role}
  end

  def validate_invite_role(_), do: {:error, :invalid_role}

  @doc """
  Lists an org's invites. `token_hash` is never selected — it is bcrypt at
  rest and useless to the admin UI; the raw token only ever leaves
  `create_invite_token/1`.
  """
  def list_invites(organization_id) do
    from(t in InviteTokenSchema,
      where: t.organization_id == ^organization_id,
      order_by: [desc: t.inserted_at],
      select:
        map(t, [
          :id,
          :email,
          :role,
          :key_prefix,
          :status,
          :revoked,
          :uses,
          :max_uses,
          :expires_at,
          :starts_at,
          :inserted_at
        ])
    )
    |> Starter.Repo.all()
  end

  @doc """
  Revokes an invite by id, scoped to its organization so one org can never
  revoke another org's invite. Idempotent on already-revoked rows.
  """
  def revoke_invite(organization_id, invite_id) do
    now = DateTime.utc_now()

    from(t in InviteTokenSchema,
      where: t.id == ^invite_id and t.organization_id == ^organization_id
    )
    |> Starter.Repo.update_all(set: [revoked: true, status: "revoked", updated_at: now])
    |> case do
      {0, _} -> {:error, :not_found}
      _ -> :ok
    end
  end

  @doc "Redemptions recorded against an invite, newest first."
  def list_invite_redemptions(invite_id) do
    from(r in InviteTokenRedemptionSchema,
      where: r.invite_token_id == ^invite_id,
      order_by: [desc: r.redeemed_at],
      limit: 100,
      select: map(r, [:id, :user_id, :redeemed_at, :remote_ip])
    )
    |> Starter.Repo.all()
  end

  @doc """
  Exact redemption counts for every invite in an org, as a single grouped
  query (`%{invite_token_id => count}`). Use this in listings instead of
  `list_invite_redemptions |> length/1` — that both caps at 100 and N+1s per
  invite.
  """
  def invite_redemption_counts(organization_id) do
    from(r in InviteTokenRedemptionSchema,
      join: t in InviteTokenSchema,
      on: t.id == r.invite_token_id,
      where: t.organization_id == ^organization_id,
      group_by: r.invite_token_id,
      select: {r.invite_token_id, count()}
    )
    |> Starter.Repo.all()
    |> Map.new()
  end

  @doc "Organization name for invite surfaces (lookup/emails), nil-safe."
  def organization_name(organization_id) do
    case Starter.Repo.get(Schema, organization_id) do
      nil -> nil
      org -> Map.get(org, :name) || Map.get(org, :title)
    end
  end
end
