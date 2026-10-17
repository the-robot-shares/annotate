defmodule Annotate.Billing.BetaJoin do
  @moduledoc """
  The $19.95 "skip the queue" beta join (feedback 2026-10-18).

  A gated user on `/auth/invite-required` can pay a one-time, non-refundable
  $19.95 (Stripe Checkout, `payment` mode) to join the beta without waiting
  for an invite token. The payment webhook (`checkout.session.completed` with
  metadata `kind: "beta_join"`) then:

    1. clears the invite gate — status `:active`, `approved_at` stamped,
       `beta_joined_at` stamped (the beta tag);
    2. grants a 90-day Team trial on the billing row (plan "team", status
       "trialing", trial_ends_at now+90d) — free for those 3 months, locking
       after unless a real subscription takes over. An existing paid
       subscription is never touched.

  Everything here is idempotent (Stripe retries, repeat checkouts) and fails
  soft: an unknown user id or a racing activation logs and returns `:ok` so
  the webhook answers 200 and Stripe stops retrying.
  """

  import Ecto.Query, only: [from: 2]

  alias Annotate.Billing.Subscriptions
  alias Annotate.Repo
  alias Annotate.Schema.Billing.Subscription
  alias Annotate.Schema.Users.User, as: UserSchema

  require Logger

  @price_cents 1_995
  @lookup_key "annotate_beta_join_once"
  @trial_days 90

  @gated_statuses [:pending, :waitlist, :unverified]

  def price_cents, do: @price_cents
  def lookup_key, do: @lookup_key
  def trial_days, do: @trial_days

  @doc """
  Applies a paid beta join for `user_id` (webhook path). Idempotent; returns
  `:ok` whether or not the user needed activating.
  """
  def activate(user_id) when is_binary(user_id) do
    with {:ok, id} <- Ecto.UUID.cast(user_id),
         %UserSchema{} = user <- Repo.get(UserSchema, id) do
      clear_gate(user)
      grant_team_trial(id)
    else
      _ ->
        Logger.warning("beta_join webhook for unknown user")
        :ok
    end

    :ok
  end

  def activate(_), do: :ok

  # A gated account flips :active (stamping approved_at); anyone already
  # active just gets the beta tag. Guarded updates — safe to replay.
  defp clear_gate(%UserSchema{id: id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(u in UserSchema,
      where: u.id == ^id and u.status in ^@gated_statuses and is_nil(u.beta_joined_at)
    )
    |> Repo.update_all(set: [status: :active, approved_at: now, beta_joined_at: now])

    from(u in UserSchema, where: u.id == ^id and is_nil(u.beta_joined_at))
    |> Repo.update_all(set: [beta_joined_at: now])

    :ok
  end

  # 90 days of Team, free. Only lands on a row with no real Stripe
  # subscription behind it — never clobbers a paying customer's plan.
  defp grant_team_trial(user_id) do
    case Subscriptions.get(user_id) do
      %Subscription{stripe_subscription_id: nil} = row ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        row
        |> Subscription.changeset(%{
          plan: "team",
          status: "trialing",
          trial_ends_at: DateTime.add(now, @trial_days * 86_400, :second)
        })
        |> Repo.update()

        :ok

      %Subscription{} ->
        :ok

      nil ->
        {:ok, _} = Subscriptions.ensure(user_id)
        grant_team_trial(user_id)
    end
  end
end
