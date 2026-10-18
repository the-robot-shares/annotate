defmodule Annotate.Billing.SignupCaps do
  @moduledoc """
  Per-plan signup caps (anti-flood, user decision 2026-10-17).

  `claim!/1` is the atomic arbiter: a single `UPDATE … WHERE taken < cap AND
  (live active/trialing count) < cap RETURNING taken` — Postgres serializes
  concurrent claims on the row lock, so a plan can never be over-claimed, no
  matter how many checkouts race. `taken` counts claims; the live
  subscription count guards drift (cancellations free the slot back via the
  live count even before `release/1` runs).
  """

  import Ecto.Query

  alias Annotate.Billing.Plans
  alias Annotate.Repo
  alias Annotate.Schema.Billing.SignupCap
  alias Annotate.Schema.Billing.Subscription

  @active ~w(active trialing)
  @trial_plan "trial"

  @claim_sql """
  UPDATE plan_signup_caps
  SET taken = taken + 1, updated_at = now()
  WHERE plan = $1
    AND taken < cap
    AND (
      SELECT count(*) FROM billing_subscriptions
      WHERE plan = $1 AND status = ANY($2)
    ) < cap
  RETURNING taken
  """

  # Trial rows carry plan IS NULL (the local 14-day trial precedes any plan),
  # so the live count keys on the planless trialing rows that are not yet
  # expired; expired trials free their slot without a webhook. Stripe-backed
  # rows never hold an intake slot, even when their plan is unresolvable.
  @trial_claim_sql """
  UPDATE plan_signup_caps
  SET taken = taken + 1, updated_at = now()
  WHERE plan = $1
    AND taken < cap
    AND (
      SELECT count(*) FROM billing_subscriptions
      WHERE plan IS NULL AND status = 'trialing'
        AND stripe_subscription_id IS NULL
        AND (trial_ends_at IS NULL OR trial_ends_at > now())
    ) < cap
  RETURNING taken
  """

  @intake_capacity_message "Free trials are at capacity right now — subscribe to start using annotate."

  @doc "The `plan_signup_caps` row key that caps concurrent trials."
  def trial_plan, do: @trial_plan

  @doc "Copy shown when a new account cannot get a trial (intake cap full)."
  def intake_capacity_message, do: @intake_capacity_message

  @doc """
  Claims one intake (trial) slot. Called from the trial-mint path
  (`Subscriptions.ensure/1`) — signups themselves are never blocked
  (user decision 2026-10-18, corrected model): at capacity the account is
  minted with NO trial and is usage-gated until it subscribes. `{:error,
  :plan_full}` when the trial cap is reached.
  """
  def claim_trial, do: claim!(@trial_plan)

  @doc "Cap rows for every known plan, seeded on first read."
  def list do
    seed()

    from(c in SignupCap, order_by: [asc: c.plan]) |> Repo.all()
  end

  def status(plan) when is_binary(plan) do
    seed()

    case Repo.get(SignupCap, plan) do
      nil -> nil
      cap -> %{plan: cap.plan, cap: cap.cap, taken: cap.taken, full: full?(plan)}
    end
  end

  @doc "True when the plan has hit its cap (live active/trialing count >= cap)."
  def full?(plan) when is_binary(plan) do
    cap = Repo.get(SignupCap, plan)
    (cap && live_count(plan) >= cap.cap) || false
  end

  @doc """
  Atomically claims one slot for `plan`. Returns `:ok`,
  `{:error, :plan_unavailable}` (cap is 0) or `{:error, :plan_full}`.
  """
  def claim!(plan) when is_binary(plan) do
    seed()

    trial? = plan == @trial_plan
    if trial?, do: reconcile_trial()

    # The trial claim counts planless rows in-SQL; the paid-plan claim binds
    # the active statuses as $2 — the two statements take different arities.
    params = if(trial?, do: [plan], else: [plan, @active])
    result = Repo.query!(if(trial?, do: @trial_claim_sql, else: @claim_sql), params)

    case result.rows do
      [[_taken]] -> :ok
      [] -> {:error, failure_reason(plan)}
    end
  end

  # A 0-cap row is a plan switched off for demand, not a full one.
  defp failure_reason(plan) do
    case Repo.get(SignupCap, plan) do
      %{cap: 0} -> :plan_unavailable
      _ -> :plan_full
    end
  end

  # Expired trials never see a webhook, so `taken` drifts upward against the
  # real live count. Re-sync the trial row's counter from the live count
  # before every trial claim (single global row — one statement, self-healing).
  defp reconcile_trial do
    Repo.query!(
      """
      UPDATE plan_signup_caps
      SET taken = GREATEST((
        SELECT count(*) FROM billing_subscriptions
        WHERE plan IS NULL AND status = 'trialing'
          AND stripe_subscription_id IS NULL
          AND (trial_ends_at IS NULL OR trial_ends_at > now())
      ), 0), updated_at = now()
      WHERE plan = $1
      """,
      [@trial_plan]
    )

    :ok
  end

  @doc "Releases a claimed slot (checkout expired/failed). Floors at 0."
  def release(plan) when is_binary(plan) do
    from(c in SignupCap, where: c.plan == ^plan and c.taken > 0)
    |> Repo.update_all(set: [updated_at: DateTime.utc_now()], inc: [taken: -1])

    :ok
  end

  @doc "Admin: raise/lower a plan's cap. Returns `{:ok, cap}`."
  def set_cap(plan, cap) when is_binary(plan) and is_integer(cap) and cap >= 0 do
    seed()

    Repo.get(SignupCap, plan)
    |> case do
      nil -> {:error, :unknown_plan}
      row -> row |> SignupCap.changeset(%{cap: cap}) |> Repo.update()
    end
  end

  def set_cap(_, _), do: {:error, :invalid}

  defp live_count("trial") do
    from(s in Subscription,
      where:
        is_nil(s.plan) and s.status == "trialing" and is_nil(s.stripe_subscription_id) and
          (is_nil(s.trial_ends_at) or s.trial_ends_at > ^DateTime.utc_now()),
      select: count(s.id)
    )
    |> Repo.one() || 0
  end

  defp live_count(plan) do
    from(s in Subscription,
      where: s.plan == ^plan and s.status in @active,
      select: count(s.id)
    )
    |> Repo.one() ||
      0
  end

  defp seed do
    now = DateTime.utc_now()

    rows =
      Enum.map(Plans.cap_seeds(), fn {plan, cap} ->
        %{plan: plan, cap: cap, taken: 0, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(SignupCap, rows, on_conflict: :nothing, conflict_target: [:plan])
    :ok
  end
end
