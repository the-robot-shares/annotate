defmodule Annotate.Schema.Billing.Subscription do
  @moduledoc """
  The billing state of one dashboard user (the billing owner). One row per
  user (`UNIQUE user_id`).

  Local trial rows: `status: "trialing"`, `current_period_end: NULL`,
  `trial_ends_at` set (backfilled for existing users by changelog
  annotate-0051; created lazily for new accounts by `Annotate.Billing`).
  Stripe webhooks overwrite plan/status/period and stamp the Stripe ids.
  `comp: true` accounts are never locked.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(trialing active past_due canceled incomplete incomplete_expired)

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  schema "billing_subscriptions" do
    belongs_to :user, Annotate.Schema.Users.User, type: Ecto.UUID
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :plan, :string
    field :status, :string, default: "trialing"
    field :current_period_end, :utc_datetime_usec
    field :extra_users, :integer, default: 0
    field :extra_gb, :integer, default: 0
    field :trial_ends_at, :utc_datetime_usec
    field :comp, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :stripe_customer_id,
      :stripe_subscription_id,
      :plan,
      :status,
      :current_period_end,
      :extra_users,
      :extra_gb,
      :trial_ends_at,
      :comp
    ])
    |> validate_required([:user_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:user_id)
    |> unique_constraint(:stripe_subscription_id)
  end

  def statuses, do: @statuses
end
