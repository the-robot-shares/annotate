defmodule Annotate.Billing do
  @moduledoc """
  Billing facade and CRITICAL SAFETY valve: every limit/expiry enforcement
  point in the app calls through here and is a no-op unless
  `enabled?/0` — Stripe keys configured (`Annotate.Billing.Stripe`).
  Without keys nothing ever locks: a warning is logged once at boot and
  users keep full access, because a locked account with no way to pay is
  the one unrecoverable state (user decision 2026-10-17).

  Model: the dashboard USER is the billing owner. A site is locked when its
  `site_members` OWNER is locked (trial expired, no active subscription, not
  `comp`). Locked sites answer writes with `{:error, :billing_read_only}` —
  visitors still see every comment; the owner's dashboard stays reachable.
  """

  import Ecto.Query

  alias Annotate.Billing.Plans
  alias Annotate.Billing.Stripe
  alias Annotate.Billing.Subscriptions
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Attachment
  alias Annotate.Schema.Annotate.SiteMember
  alias Annotate.Schema.Billing.Subscription
  alias Annotate.Schema.Users.User

  require Logger

  @locked_message "This site is read-only: the owner's annotate trial has ended. " <>
                    "The site owner can restore commenting from their dashboard Billing page."

  def locked_message, do: @locked_message

  @doc "True when billing is live (Stripe keys configured)."
  def enabled?, do: Stripe.enabled?()

  @doc "Warn-once at boot when enforcement is off (ops visibility, not an error)."
  def boot_check do
    unless enabled?() do
      Logger.warning(
        "billing disabled (no ANNOTATE_STRIPE_SECRET_KEY): trials, plan limits and " <>
          "invite-expiry enforcement are OFF — nothing is locked"
      )
    end

    :ok
  end

  # ── Subscription state ────────────────────────────────────────

  def subscription(user_id), do: Subscriptions.get(user_id)
  def ensure_subscription(user_id), do: Subscriptions.ensure(user_id)

  @doc """
  True when `user_id` may not write: billing on, not comp, trial over, no
  active/trialing Stripe subscription. Billing off → always false.
  """
  def locked?(user_id) when is_binary(user_id) do
    if enabled?() do
      {:ok, row} = Subscriptions.ensure(user_id)
      locked?(row)
    else
      false
    end
  end

  def locked?(%Subscription{comp: true}), do: false

  def locked?(%Subscription{} = row) do
    if enabled?() do
      stripe_active? =
        row.status in ["active", "trialing"] and
          after_now?(row.current_period_end, DateTime.utc_now())

      stripe_active? or after_now?(row.trial_ends_at, DateTime.utc_now())
    else
      false
    end
  end

  def locked?(_), do: false

  defp after_now?(nil, _now), do: false
  defp after_now?(%DateTime{} = dt, now), do: DateTime.compare(dt, now) == :gt

  @doc "State summary for dashboard/pricing UI."
  def state(user_id) when is_binary(user_id) do
    {:ok, row} = Subscriptions.ensure(user_id)

    %{
      enabled: enabled?(),
      plan: row.plan,
      status: row.status,
      comp: row.comp,
      current_period_end: row.current_period_end,
      trial_ends_at: row.trial_ends_at,
      trial_days_left: trial_days_left(row),
      extra_users: row.extra_users,
      extra_gb: row.extra_gb,
      locked: locked?(row),
      stripe_configured: enabled?()
    }
    |> Map.merge(usage(user_id))
  end

  defp trial_days_left(%Subscription{status: "trialing", current_period_end: nil} = row) do
    case row.trial_ends_at do
      %DateTime{} = t -> max(DateTime.diff(t, DateTime.utc_now(), :day) + 1, 0)
      nil -> nil
    end
  end

  defp trial_days_left(_), do: nil

  # ── Usage ─────────────────────────────────────────────────────

  @doc "Usage meters: owned sites, distinct users across them, storage bytes."
  def usage(user_id) when is_binary(user_id) do
    %{
      sites: owned_site_count(user_id),
      users: distinct_member_count(user_id),
      storage_bytes: owned_storage_bytes(user_id)
    }
  end

  def usage(_), do: %{sites: 0, users: 0, storage_bytes: 0}

  defp owned_site_count(user_id) do
    from(m in SiteMember, where: m.user_id == ^user_id and m.role == :owner, select: count(m.id))
    |> Repo.one() || 0
  end

  defp distinct_member_count(user_id) do
    site_ids = owned_site_ids(user_id)

    case site_ids do
      [] ->
        1

      ids ->
        from(sm in SiteMember, where: sm.site_id in ^ids, select: count(sm.user_id, :distinct))
        |> Repo.one() || 1
    end
  end

  defp owned_storage_bytes(user_id) do
    case owned_site_ids(user_id) do
      [] ->
        0

      ids ->
        from(a in Attachment,
          where: a.site_id in ^ids and a.status == :ready,
          select: coalesce(sum(a.bytes), 0)
        )
        |> Repo.one() || 0
    end
  end

  defp owned_site_ids(user_id) do
    from(m in SiteMember, where: m.user_id == ^user_id and m.role == :owner, select: m.site_id)
    |> Repo.all()
  end

  @doc """
  Effective limits for a user's plan row: %{apps, users, storage_bytes}.
  `:unlimited` (team/enterprise/comp semantics) or nil (unknown plan) mean
  no cap on that axis.
  """
  def limits(%Subscription{} = row) do
    plan = row.plan

    %{
      apps: Plans.apps_limit(plan),
      users: Plans.users_limit(plan, row.extra_users),
      storage_bytes: Plans.storage_limit(plan, row.extra_gb)
    }
  end

  def limits(user_id) when is_binary(user_id) do
    {:ok, row} = Subscriptions.ensure(user_id)
    limits(row)
  end

  # ── Enforcement helpers (all gated on enabled?) ───────────────

  @doc "Apps-limit check for `create_site_with_owner`. `:ok` | `{:error, reason}`."
  def check_site_creation(user_id) when is_binary(user_id) do
    if enabled?() do
      {:ok, row} = Subscriptions.ensure(user_id)

      cond do
        row.comp ->
          :ok

        locked?(row) ->
          {:error, :billing_required}

        true ->
          case limits(row).apps do
            :unlimited ->
              :ok

            nil ->
              :ok

            limit when is_integer(limit) ->
              if usage(user_id).sites < limit, do: :ok, else: {:error, :plan_site_limit}
          end
      end
    else
      :ok
    end
  end

  def check_site_creation(_), do: :ok

  @doc """
  True when `user_id`'s account has NO per-account site cap: a `comp`
  subscription, or a plan whose apps limit is `:unlimited` (team,
  enterprise). Read-only on purpose — `Annotate.Sites` consults this before
  its self-serve abuse bound, and that check must never create a trial row
  as a side effect. Billing off → only the row's own plan/comp decides.
  """
  def site_limit_exempt?(user_id) when is_binary(user_id) do
    case Subscriptions.get(user_id) do
      %Subscription{comp: true} -> true
      %Subscription{} = row -> limits(row).apps == :unlimited
      nil -> false
    end
  end

  def site_limit_exempt?(_), do: false

  @doc """
  Users-limit check for `SiteMembers.add_member` against the SITE OWNER's
  plan (distinct members across all of the owner's sites).
  """
  def check_member_addition(site_id) when is_binary(site_id) do
    if enabled?() do
      owner_id = owner_user_id(site_id)

      if owner_id do
        {:ok, row} = Subscriptions.ensure(owner_id)

        if row.comp do
          :ok
        else
          case limits(row).users do
            unlimited when unlimited in [nil, :unlimited] ->
              :ok

            limit when is_integer(limit) ->
              if distinct_member_count(owner_id) < limit,
                do: :ok,
                else: {:error, :plan_user_limit}
          end
        end
      else
        :ok
      end
    else
      :ok
    end
  end

  def check_member_addition(_), do: :ok

  @doc "Storage check for uploads: does `additional_bytes` fit the owner's plan?"
  def check_storage(site_id, additional_bytes)
      when is_binary(site_id) and is_integer(additional_bytes) do
    if enabled?() do
      owner_id = owner_user_id(site_id)

      if owner_id do
        {:ok, row} = Subscriptions.ensure(owner_id)

        if row.comp do
          :ok
        else
          case limits(row).storage_bytes do
            unlimited when unlimited in [nil, :unlimited] ->
              :ok

            limit when is_integer(limit) ->
              if owned_storage_bytes(owner_id) + additional_bytes <= limit,
                do: :ok,
                else: {:error, :plan_storage_limit}
          end
        end
      else
        :ok
      end
    else
      :ok
    end
  end

  def check_storage(_, _), do: :ok

  @doc "Read-only gate for comment/reply/upload writes on `site_id`."
  def site_locked?(site_id) when is_binary(site_id) do
    if enabled?() do
      case owner_user_id(site_id) do
        nil -> false
        owner_id -> locked?(owner_id)
      end
    else
      false
    end
  end

  def site_locked?(_), do: false

  @doc "The billing owner (site_members owner) of `site_id`, or nil."
  def owner_user_id(site_id) when is_binary(site_id) do
    from(m in SiteMember,
      where: m.site_id == ^site_id and m.role == :owner,
      select: m.user_id,
      limit: 1
    )
    |> Repo.one()
  end

  def owner_user_id(_), do: nil

  @doc "Admin/ops: set `users.invite_quota`. Returns `{:ok, user}`."
  def set_invite_quota(user_id, quota)
      when is_binary(user_id) and is_integer(quota) and quota >= 0 do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        user
        |> Ecto.Changeset.change(invite_quota: quota)
        |> Repo.update()
    end
  end

  def set_invite_quota(_, _), do: {:error, :invalid}

  @doc "Admin/ops: grant quota by email (lowercased citext match)."
  def set_invite_quota_by_email(email, quota)
      when is_binary(email) and is_integer(quota) and quota >= 0 do
    email = email |> String.trim() |> String.downcase()

    case Repo.one(from(u in User, where: u.email == ^email, limit: 1)) do
      nil -> {:error, :not_found}
      user -> set_invite_quota(user.id, quota)
    end
  end

  def set_invite_quota_by_email(_, _), do: {:error, :invalid}
end
