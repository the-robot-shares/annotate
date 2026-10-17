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

  @default_days 14
  @max_days 90

  def default_days, do: @default_days

  @doc """
  Creates an invite. `opts`: `:email` (bind), `:days` (1..90), `:max_uses`
  (1..100). Returns `{:ok, invite, raw_token}` or `{:error, reason}`.
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
        Annotate.Organizations.create_invite_token(%{
          organization_id: nil,
          created_by_user_id: issuer_id(issuer),
          email: email,
          role: "viewer",
          max_uses: max_uses,
          starts_at: DateTime.add(DateTime.utc_now(), -60, :second),
          expires_at: DateTime.add(DateTime.utc_now(), days * 86_400, :second)
        })
    end
  end

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

  @doc "Revokes a dashboard invite by id."
  def revoke(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        from(t in InviteToken, where: t.id == ^id and is_nil(t.organization_id))
        |> Repo.update_all(
          set: [revoked: true, status: "revoked", updated_at: DateTime.utc_now()]
        )
        |> case do
          {1, _} -> :ok
          _ -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

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
