defmodule Annotate.Billing.Plans do
  @moduledoc """
  Code-level plan catalog. Stripe Prices are referenced by **lookup key**,
  never by price id (the key survives price replacement). Comments are
  unlimited on every plan.

  | plan     | price/mo | apps | users | storage | extras                                   |
  |----------|----------|------|-------|---------|------------------------------------------|
  | start    | $0.99    | 3    | 3     | 100MB   | —                                        |
  | standard | $3.99    | 10   | 3     | 1GB     | —                                        |
  | team     | $9.99    | ∞    | 5     | 10GB    | +$0.99/user/mo, +$0.99/GB/mo (quantities)|
  | agent    | $4.95    | —    | —     | —       | NOT purchasable yet ("coming soon")      |
  """

  @mb 1_048_576
  @gb 1_073_741_824

  @plans %{
    "start" => %{
      key: "start",
      name: "Start",
      price_cents: 99,
      lookup_key: "annotate_start_monthly",
      apps: 3,
      users: 3,
      storage_bytes: 100 * @mb,
      extras: false
    },
    "standard" => %{
      key: "standard",
      name: "Standard",
      price_cents: 399,
      lookup_key: "annotate_standard_monthly",
      apps: 10,
      users: 3,
      storage_bytes: 1 * @gb,
      extras: false
    },
    "team" => %{
      key: "team",
      name: "Team",
      price_cents: 999,
      lookup_key: "annotate_team_monthly",
      apps: :unlimited,
      users: 5,
      storage_bytes: 10 * @gb,
      extras: true,
      extra_user_price_cents: 99,
      extra_user_lookup_key: "annotate_extra_user_monthly",
      extra_gb_price_cents: 99,
      extra_gb_lookup_key: "annotate_extra_gb_monthly"
    },
    "agent_addon" => %{
      key: "agent_addon",
      name: "Agent add-on",
      price_cents: 495,
      lookup_key: "annotate_agent_addon_monthly",
      apps: nil,
      users: nil,
      storage_bytes: nil,
      extras: false,
      purchasable: false
    }
  }

  @purchasable ~w(start standard team)
  @extra_lookup_keys MapSet.new([
                       "annotate_extra_user_monthly",
                       "annotate_extra_gb_monthly"
                     ])

  def all, do: @plans

  def get(plan) when is_binary(plan), do: Map.get(@plans, plan)
  def get(_), do: nil

  def purchasable?(plan), do: plan in @purchasable

  @doc "Plan keys that may start a Checkout session, in display order."
  def purchasable, do: @purchasable

  @doc "Seed values for `plan_signup_caps` (user decision 2026-10-17)."
  def cap_seeds, do: %{"start" => 25, "standard" => 25, "agent_addon" => 10, "team" => 5}

  @doc "Lookup keys that ride a Team subscription as metered quantities."
  def extra_lookup_keys, do: @extra_lookup_keys

  @doc "Effective user limit for a plan (+ purchased extra users)."
  def users_limit(plan_key, extra_users) do
    case get(plan_key) do
      %{users: users} when is_integer(users) -> users + max(extra_users || 0, 0)
      _ -> nil
    end
  end

  @doc "Effective storage bytes for a plan (+ purchased extra GB)."
  def storage_limit(plan_key, extra_gb) do
    case get(plan_key) do
      %{storage_bytes: base} when is_integer(base) -> base + max(extra_gb || 0, 0) * @gb
      _ -> nil
    end
  end

  @doc "Apps limit for a plan; `:unlimited` on Team, nil when unknown."
  def apps_limit(plan_key) do
    case get(plan_key) do
      %{apps: :unlimited} -> :unlimited
      %{apps: apps} when is_integer(apps) -> apps
      _ -> nil
    end
  end
end
