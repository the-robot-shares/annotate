defmodule Annotate.Dashboard.Invites do
  @moduledoc """
  Dashboard invites: org-less rows in the scaffold's `invite_tokens` table
  (`organization_id` NULL), redeemed by `Annotate.Auth.InviteGate.redeem/3`.

  Token: 32 random bytes (256 bits) url64; only a bcrypt hash + an 8-char
  lookup prefix are stored — the raw token exists once, in the return value
  of `create/2` (shown once in the dashboard / printed once by the release
  task). Single-use by default (`max_uses: 1`), expiring (default 14 days),
  optionally bound to an email (the signing-in provider-verified email must
  match), revocable. Redemption is rate-limited at the interstitial and
  atomic (guarded increment + per-user redemption row).

  Link: `https://<host>/sign-up?invite=<token>`.
  """

  import Ecto.Query

  alias Annotate.Repo
  alias Annotate.Schema.Organizations.InviteToken
  alias Annotate.Schema.Users.User, as: UserSchema

  @default_days 14
  @max_days 90

  def default_days, do: @default_days

  @doc """
  Creates an invite. `opts`: `:email` (bind), `:days` (1..90), `:max_uses`
  (1..100). Returns `{:ok, invite, raw_token}` or `{:error, reason}`.

  Quota (user decision 2026-10-17): minting consumes one of the issuer's
  `users.invite_quota` — except platform admins and ops (`issuer` nil), who
  are unlimited. `{:error, :no_quota}` when the balance is 0. The decrement
  and the insert are one transaction, so a failed insert refunds implicitly;
  revoking an UNUSED invite refunds its issuer (unless they are unlimited).
  """
  def create(issuer, opts \\ []) do
    email =
      case Keyword.get(opts, :email) do
        e when is_binary(e) -> e |> String.trim() |> String.downcase() |> blank_to_nil()
        _ -> nil
      end

    days = Keyword.get(opts, :days, @default_days)
    max_uses = Keyword.get(opts, :max_uses, 1)

    cond do
      email && not Annotate.Waitlist.valid_email?(email) ->
        {:error, :invalid_email}

      not (is_integer(days) and days >= 1 and days <= @max_days) ->
        {:error, :invalid_days}

      not (is_integer(max_uses) and max_uses >= 1 and max_uses <= 100) ->
        {:error, :invalid_max_uses}

      true ->
        with_quota(issuer, fn ->
          Annotate.Organizations.create_invite_token(%{
            organization_id: nil,
            created_by_user_id: issuer_id(issuer),
            email: email,
            role: "viewer",
            max_uses: max_uses,
            starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
            expires_at: DateTime.add(DateTime.utc_now(), days * 86_400, :second)
          })
        end)
    end
  end

  @doc "The issuer's remaining mintable invites; nil when unlimited (admins/ops)."
  def remaining_quota(issuer)

  def remaining_quota(nil), do: nil

  def remaining_quota(%{id: user_id} = issuer) do
    if unlimited?(issuer) do
      nil
    else
      case Repo.get(UserSchema, user_id) do
        %{invite_quota: q} when is_integer(q) -> q
        _ -> 0
      end
    end
  end

  def remaining_quota(_), do: nil

  defp unlimited?(%{admin: true}), do: true
  defp unlimited?(_), do: false

  # Admins and ops bypass the quota; everyone else spends one inside a
  # transaction that locks their user row (two concurrent mints cannot both
  # spend the last invite).
  defp with_quota(issuer, fun)

  defp with_quota(%{admin: true}, fun), do: fun.()
  defp with_quota(nil, fun), do: fun.()

  defp with_quota(%{id: user_id}, fun) when is_binary(user_id) do
    Repo.transaction(fn ->
      user = Repo.get!(UserSchema, user_id)

      case user.invite_quota do
        q when is_integer(q) and q > 0 ->
          from(u in UserSchema, where: u.id == ^user_id)
          |> Repo.update_all(set: [invite_quota: q - 1, updated_at: DateTime.utc_now()])

          case fun.() do
            {:ok, _} = ok -> ok
            {:error, reason} -> Repo.rollback(reason)
          end

        q when is_integer(q) ->
          Repo.rollback(:no_quota)

        _ ->
          Repo.rollback(:no_quota)
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_quota(_, _fun), do: {:error, :forbidden}

  @doc "Dashboard invites, newest first (no hashes, no raw tokens)."
  def list(limit \\ 100) do
    now = DateTime.utc_now()

    from(t in InviteToken,
      where: is_nil(t.organization_id),
      order_by: [desc: t.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        prefix: t.key_prefix,
        email: t.email,
        uses: t.uses,
        max_uses: t.max_uses,
        expires_at: t.expires_at,
        state: state(t, now)
      }
    end)
  end

  defp state(%{revoked: true}, _), do: "revoked"
  defp state(%{max_uses: m, uses: u}, _) when is_integer(m) and u >= m, do: "used"

  defp state(%{expires_at: %DateTime{} = e}, now),
    do: if(DateTime.compare(e, now) == :gt, do: "active", else: "expired")

  defp state(_, _), do: "active"

  @doc """
  Revokes a dashboard invite by id. Revoking an UNUSED invite refunds its
  issuer's quota (admins are unlimited; refunds only land on finite-quota
  users), so a mis-minted invite never burns budget.
  """
  def revoke(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn ->
          from(t in InviteToken,
            where: t.id == ^id and is_nil(t.organization_id) and t.revoked == false,
            lock: "FOR UPDATE"
          )
          |> Repo.one()
          |> case do
            nil ->
              Repo.rollback(:not_found)

            invite ->
              from(t in InviteToken, where: t.id == ^id)
              |> Repo.update_all(
                set: [revoked: true, status: "revoked", updated_at: DateTime.utc_now()]
              )

              refund_unused(invite)
              :ok
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, :not_found} -> {:error, :not_found}
          _ -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  # `uses` is read under the row lock, so two concurrent revokes cannot both
  # refund. Org-bound invites (organization_id set) never enter here.
  defp refund_unused(%InviteToken{uses: uses, created_by_user_id: creator_id})
       when uses in [0, nil] and is_binary(creator_id) do
    case Repo.get(UserSchema, creator_id) do
      %{admin: true} ->
        :ok

      %UserSchema{} = issuer ->
        from(u in UserSchema, where: u.id == ^issuer.id)
        |> Repo.update_all(inc: [invite_quota: 1])

        :ok

      _ ->
        :ok
    end
  end

  defp refund_unused(_), do: :ok

  @doc "The sign-up link for a raw token."
  def link(raw_token) do
    base = Application.get_env(:annotate, :frontend_url) || "https://annotate.therobotlives.com"
    String.trim_trailing(base, "/") <> "/sign-up?invite=" <> URI.encode_www_form(raw_token)
  end

  defp issuer_id(%{id: id}), do: id
  defp issuer_id(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end
