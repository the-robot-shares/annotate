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
  Atomically claims one slot for `plan`. Returns `:ok` or `{:error, :plan_full}`.
  """
  def claim!(plan) when is_binary(plan) do
    seed()

    plan_trimmed = plan

    result =
      Repo.query!(
        """
        UPDATE plan_signup_caps
        SET taken = taken + 1, updated_at = now()
        WHERE plan = $1
          AND taken < cap
          AND (
            SELECT count(*) FROM billing_subscriptions
            WHERE plan = $1 AND status = ANY($2)
          ) < cap
        RETURNING taken
        """,
        [plan_trimmed, @active]
      )

    case result.rows do
      [[_taken]] -> :ok
      [] -> {:error, :plan_full}
    end
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
