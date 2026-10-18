defmodule Annotate.Billing.SignupCapsTest do
  use Annotate.DataCase, async: false

  alias Annotate.Billing
  alias Annotate.Billing.SignupCaps
  alias Annotate.Billing.Subscriptions
  alias Annotate.Repo
  alias Annotate.Schema.Billing.SignupCap
  alias Annotate.Schema.Billing.Subscription
  alias Annotate.Schema.Users.User

  setup do
    # Deterministic caps per test; the sandbox rolls every write back.
    set_cap("trial", 25)
    set_cap("agent_addon", 0)
    set_cap("start", 25)
    :ok
  end

  # Corrected model (user decision 2026-10-18): signups are never blocked.
  # The trial is minted by `Subscriptions.ensure/1` (first billing touch),
  # which claims an intake slot — at capacity the account gets NO trial
  # (already-expired row) and is usage-gated until it subscribes.
  test "ensure mints 14-day trials up to the cap, then mints trial-less rows" do
    set_cap("trial", 2)

    with_billing_on(fn ->
      {:ok, row1} = ensure_user()
      assert row1.status == "trialing"
      assert DateTime.compare(row1.trial_ends_at, DateTime.utc_now()) == :gt
      assert taken("trial") == 1

      {:ok, _row2} = ensure_user()
      assert taken("trial") == 2

      # At capacity: the account still gets a row (admin visibility), but the
      # trial is already over — and no extra slot is taken.
      {:ok, row3} = ensure_user()
      assert row3.status == "trialing"
      refute DateTime.compare(row3.trial_ends_at, DateTime.utc_now()) == :gt
      assert taken("trial") == 2

      # Trial-less rows are the usage gate: locked until subscribed (assert
      # with a definitively-past trial end — the mint stamps `now`, and the
      # lock only flips once the clock passes it).
      assert Billing.locked?(%{row3 | trial_ends_at: DateTime.add(DateTime.utc_now(), -1, :second)})
      refute Billing.locked?(row1.user_id)
    end)
  end

  test "ensure with billing disabled mints the trial without claiming" do
    refute billing_on?()

    {:ok, row} = ensure_user()

    assert DateTime.compare(row.trial_ends_at, DateTime.utc_now()) == :gt
    assert taken("trial") == 0
  end

  test "a cap-0 plan is :plan_unavailable, not :plan_full" do
    assert SignupCaps.claim!("agent_addon") == {:error, :plan_unavailable}
    assert taken("agent_addon") == 0
  end

  test "a full paid plan is :plan_full" do
    set_cap("start", 1)

    assert SignupCaps.claim!("start") == :ok
    assert SignupCaps.claim!("start") == {:error, :plan_full}
  end

  test "expired local trials are reconciled away before a claim" do
    set_cap("trial", 1)
    user = insert_user()

    Repo.insert!(%Subscription{
      user_id: user.id,
      status: "trialing",
      trial_ends_at: DateTime.add(DateTime.utc_now(), -86_400, :second)
    })

    # `taken` still counts the stale row until reconcile runs…
    bump_taken("trial", 1)
    # …then the claim reconciles taken to the live count (0) and takes the slot.
    assert SignupCaps.claim_trial() == :ok
    assert taken("trial") == 1
  end

  test "release hands a claimed trial slot back" do
    set_cap("trial", 1)
    assert SignupCaps.claim_trial() == :ok
    insert_trial_row()
    assert taken("trial") == 1

    # A release always rides the row leaving the planless-trial state (the
    # webhook path calls release right before/after rewriting the row), so
    # the counter decrement and the live count drop together.
    assert SignupCaps.release(SignupCaps.trial_plan())
    convert_trial_rows()
    assert taken("trial") == 0
    assert SignupCaps.claim_trial() == :ok
  end

  test "a webhook that converts the local trial releases its intake slot" do
    set_cap("trial", 1)
    assert SignupCaps.claim_trial() == :ok

    user = insert_user()

    Repo.insert!(%Subscription{
      user_id: user.id,
      status: "trialing",
      trial_ends_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
    })

    sub = %{
      "id" => "sub_test_#{System.unique_integer([:positive])}",
      "customer" => "cus_test_#{System.unique_integer([:positive])}",
      "status" => "active",
      "items" => [%{"price" => %{"lookup_key" => "annotate_standard_monthly"}}]
    }

    assert Subscriptions.write_subscription_row(user.id, sub) == :ok
    assert taken("trial") == 0
  end

  # ── helpers ───────────────────────────────────────────────────

  defp set_cap(plan, cap) do
    Repo.insert!(
      %SignupCap{plan: plan, cap: cap, taken: 0},
      on_conflict: [set: [cap: cap, taken: 0]],
      conflict_target: :plan
    )
  end

  defp bump_taken(plan, n),
    do: cap_row(plan) |> Ecto.Changeset.change(taken: n) |> Repo.update!()

  defp cap_row(plan), do: Repo.get!(SignupCap, plan)
  defp taken(plan), do: cap_row(plan).taken

  defp billing_on? do
    conf = Application.get_env(:annotate, Annotate.Billing.Stripe, [])
    conf[:enabled] == true and is_binary(conf[:api_key])
  end

  # `ensure` only claims when billing is live; flip the app env for the
  # duration of the test (this file is async: false — the exclusive ExUnit
  # wave means no other test reads the flipped env concurrently).
  defp with_billing_on(fun) do
    prev = Application.get_env(:annotate, Annotate.Billing.Stripe)

    Application.put_env(
      :annotate,
      Annotate.Billing.Stripe,
      Keyword.merge(prev || [], enabled: true, api_key: "sk_test_signup_caps")
    )

    try do
      fun.()
    after
      if prev do
        Application.put_env(:annotate, Annotate.Billing.Stripe, prev)
      else
        Application.delete_env(:annotate, Annotate.Billing.Stripe)
      end
    end
  end

  defp ensure_user do
    user = insert_user()
    Subscriptions.ensure(user.id)
  end

  # Simulates the webhook transition out of the planless trial (paid plan
  # takes over): the row keeps its history but no longer holds an intake slot.
  defp convert_trial_rows do
    from(s in Subscription,
      where: is_nil(s.plan) and s.status == "trialing" and is_nil(s.stripe_subscription_id)
    )
    |> Repo.update_all(
      set: [
        plan: "start",
        status: "active",
        stripe_subscription_id: "sub_released_#{System.unique_integer([:positive])}",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )

    :ok
  end

  defp insert_trial_row do
    user = insert_user()

    Repo.insert!(%Subscription{
      user_id: user.id,
      status: "trialing",
      trial_ends_at: DateTime.add(DateTime.utc_now(), 86_400, :second)
    })
  end

  defp insert_user do
    uniq = System.unique_integer([:positive])

    Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      email: "caps-#{uniq}@example.com",
      user_name: "caps#{uniq}",
      handle: "caps#{uniq}",
      status: :active
    })
  end
end
