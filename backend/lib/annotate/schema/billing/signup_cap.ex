defmodule Annotate.Schema.Billing.SignupCap do
  @moduledoc """
  Per-plan signup cap (anti-flood): how many active/trialing subscriptions a
  plan may take. `taken` is claimed atomically at Checkout start
  (`Annotate.Billing.SignupCaps`). Caps are admin-adjustable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:plan, :string, autogenerate: false}
  schema "plan_signup_caps" do
    field :cap, :integer
    field :taken, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(cap, attrs) do
    cap
    |> cast(attrs, [:plan, :cap, :taken])
    |> validate_required([:plan, :cap])
    |> validate_number(:cap, greater_than_or_equal_to: 0)
  end
end
