defmodule Annotate.Billing.Subscriptions do
  @moduledoc """
  The `billing_subscriptions` context: trial lifecycle, Stripe Checkout /
  Portal starts, and webhook-driven state. Webhooks are the source of truth
  for anything Stripe-side; the local trial (14 days, every account) lives in
  the same row until a subscription takes over.
  """

  alias Annotate.Billing.Plans
  alias Annotate.Billing.SignupCaps
  alias Annotate.Billing.Stripe
  alias Annotate.Repo
  alias Annotate.Schema.Billing.Subscription

  require Logger

  @trial_days 14
  @active ~w(active trialing)

  def trial_days, do: @trial_days

  # ── Row lifecycle ─────────────────────────────────────────────

  @doc """
  The user's subscription row, creating it if absent. The 14-day trial is
  minted here (the trial-mint path): signups are never blocked — when the
  trial intake cap is full the row is minted with NO trial (already-expired
  trial), so the account exists but is usage-gated (`Billing.locked?/1`)
  until it subscribes (user decision 2026-10-18, corrected model). With
  billing disabled the trial is minted without claiming (nothing enforced).
  """
  def ensure(user_id) when is_binary(user_id) do
    case Repo.get_by(Subscription, user_id: user_id) do
      %Subscription{} = row ->
        {:ok, row}

      nil ->
        {:ok, mint_trial_row(user_id)}
    end
  end

  # Claim and row commit atomically: `SignupCaps` reconciles the intake
  # counter against live unexpired planless-trial rows, so a claim whose row
  # doesn't exist yet would be reconciled away. At capacity the row still
  # exists (admin visibility, one row per account) with `trial_ends_at: now`
  # — an expired trial never holds an intake slot.
  defp mint_trial_row(user_id) do
    {:ok, row} =
      Annotate.Repo.transaction(fn ->
        trial? =
          if Annotate.Billing.enabled?(),
            do: match?(:ok, SignupCaps.claim_trial()),
            else: true

        now = DateTime.utc_now() |> DateTime.truncate(:second)
        ends_at = if trial?, do: DateTime.add(now, @trial_days * 86_400, :second), else: now

        %Subscription{}
        |> Subscription.changeset(%{
          user_id: user_id,
          status: "trialing",
          trial_ends_at: ends_at
        })
        |> Repo.insert(conflict_target: :user_id, on_conflict: :nothing)

        Repo.get_by!(Subscription, user_id: user_id)
      end)

    row
  end

  def get(user_id) when is_binary(user_id), do: Repo.get_by(Subscription, user_id: user_id)
  def get(_), do: nil

  # ── Checkout / Portal ─────────────────────────────────────────

  @doc """
  Starts a Stripe Checkout session (subscription mode) for `user` on
  `plan_key`. Claims a signup-cap slot first; a full plan answers
  `{:error, :plan_full}` (the UI offers the waitlist). The claim is released
  if the session create fails.
  """
  def start_checkout(%{id: user_id, email: email}, plan_key) do
    with :ok <- ensure_billing(),
         true <- Plans.purchasable?(plan_key) || {:error, :unknown_plan},
         :ok <- SignupCaps.claim!(plan_key),
         {:ok, row} <- ensure(user_id),
         {:ok, customer_id} <- ensure_customer(row, user_id, email),
         {:ok, price_id} <- Stripe.price_id(Plans.get(plan_key).lookup_key),
         {:ok, session} <-
           Stripe.create_checkout_session(customer_id, price_id,
             user_id: user_id,
             plan: plan_key
           ) do
      {:ok, session.url}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def start_checkout(_, _), do: {:error, :unauthenticated}

  @doc """
  Starts the one-time $19.95 beta-join Checkout for a gated user (see
  `Annotate.Billing.BetaJoin`). No signup cap is claimed — the webhook grants
  a 90-day Team trial instead of a paid plan slot.
  """
  def start_beta_checkout(%{id: user_id, email: email}) do
    with :ok <- ensure_billing(),
         {:ok, row} <- ensure(user_id),
         {:ok, customer_id} <- ensure_customer(row, user_id, email),
         {:ok, session} <- Stripe.create_beta_checkout_session(customer_id, user_id: user_id) do
      {:ok, session.url}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def start_beta_checkout(_), do: {:error, :unauthenticated}

  @doc "Billing Portal session for the user's Stripe customer."
  def start_portal(%{id: user_id}) do
    with :ok <- ensure_billing(),
         %Subscription{stripe_customer_id: cid} <- get(user_id),
         true <- is_binary(cid) || {:error, :no_customer},
         {:ok, url} <- Stripe.create_portal_session(cid) do
      {:ok, url}
    else
      %Subscription{} -> {:error, :no_customer}
      {:error, reason} -> {:error, reason}
      nil -> {:error, :no_customer}
    end
  end

  def start_portal(_), do: {:error, :unauthenticated}

  @doc """
  Sets the Team extras (extra users / extra GB quantities) on the user's
  Stripe subscription. Webhooks persist the change back to the row.
  """
  def set_extras(%{id: user_id}, extra_users, extra_gb)
      when is_integer(extra_users) and is_integer(extra_gb) and extra_users >= 0 and extra_gb >= 0 do
    with :ok <- ensure_billing(),
         %Subscription{stripe_subscription_id: sub_id, stripe_customer_id: cid}
         when is_binary(sub_id) and is_binary(cid) <- get(user_id),
         true <- row_plan_is_team(user_id) || {:error, :not_team},
         {:ok, _} <-
           Stripe.update_subscription_items(sub_id, %{
             "annotate_extra_user_monthly" => extra_users,
             "annotate_extra_gb_monthly" => extra_gb
           }) do
      :ok
    else
      %Subscription{} -> {:error, :no_subscription}
      true -> :ok
      {:error, reason} -> {:error, reason}
      nil -> {:error, :no_subscription}
    end
  end

  def set_extras(_, _, _), do: {:error, :invalid}

  defp row_plan_is_team(user_id) do
    case get(user_id) do
      %Subscription{plan: "team"} -> true
      _ -> false
    end
  end

  defp ensure_customer(%Subscription{stripe_customer_id: cid}, _user_id, _email)
       when is_binary(cid),
       do: {:ok, cid}

  defp ensure_customer(%Subscription{} = row, user_id, email) do
    with {:ok, customer} <- Stripe.create_customer(user_id, email: email) do
      row
      |> Subscription.changeset(%{stripe_customer_id: customer.id})
      |> Repo.update()

      {:ok, customer.id}
    end
  end

  # ── Webhooks ──────────────────────────────────────────────────

  @doc """
  Applies a verified Stripe event idempotently (processed event ids are
  stored and skipped). Returns `:ok | {:ok, :duplicate} | {:error, reason}`.
  """
  def apply_event(%{"id" => event_id} = event) when is_binary(event_id) do
    case claim_event(event_id) do
      :ok ->
        try do
          handle_event(event)
        rescue
          e ->
            Logger.error("billing webhook apply failed: #{Exception.message(e)}")
            {:error, :apply_failed}
        end

      {:error, :duplicate} ->
        {:ok, :duplicate}
    end
  end

  def apply_event(_), do: {:error, :invalid_event}

  defp claim_event(event_id) do
    Repo.insert_all(
      "billing_processed_events",
      [%{event_id: event_id, processed_at: DateTime.utc_now()}],
      on_conflict: :nothing,
      conflict_target: :event_id
    )
    |> case do
      {1, _} -> :ok
      _ -> {:error, :duplicate}
    end
  end

  defp handle_event(%{"type" => type, "data" => %{"object" => object}}) do
    case type do
      "checkout.session.completed" ->
        user_id = get_in(object, ["metadata", "user_id"]) || object["client_reference_id"]

        cond do
          get_in(object, ["metadata", "kind"]) == "beta_join" and is_binary(user_id) ->
            Annotate.Billing.BetaJoin.activate(user_id)

          is_binary(object["subscription"]) and is_binary(user_id) ->
            sync_from_stripe(user_id, object["subscription"], then_claim_cap: true)

          true ->
            :ok
        end

      "customer.subscription.updated" ->
        sync_subscription_object(object, then_claim_cap: false)

      "customer.subscription.deleted" ->
        sync_subscription_object(object, then_claim_cap: false)

      "checkout.session.expired" ->
        plan = get_in(object, ["metadata", "plan"])
        if is_binary(plan), do: SignupCaps.release(plan)
        :ok

      _ ->
        :ok
    end
  end

  defp handle_event(_), do: :ok

  # Pulls the subscription from Stripe (items expanded) and writes the row.
  defp sync_from_stripe(user_id, sub_id, opts) do
    with {:ok, sub} <- Stripe.retrieve_subscription(sub_id) do
      write_subscription_row(user_id, sub)

      if opts[:then_claim_cap], do: claim_cap_for_sub(sub)

      :ok
    end
  end

  # subscription.updated/deleted carry the object inline (items may not be
  # expanded) — fall back to a retrieve when prices are missing.
  defp sync_subscription_object(%{"id" => sub_id, "status" => status} = object, opts)
       when is_binary(sub_id) do
    user_id = get_in(object, ["metadata", "user_id"])

    with {:ok, sub} <-
           if(has_prices?(object),
             do: {:ok, object},
             else: Stripe.retrieve_subscription(sub_id)
           ) do
      # Deleted subscriptions keep the user's history but stop billing.
      sub = if status == "canceled", do: Map.put(sub, "status", "canceled"), else: sub

      cond do
        is_binary(user_id) ->
          write_subscription_row(user_id, sub)

        true ->
          # No metadata: locate the row by subscription id.
          case Repo.get_by(Subscription, stripe_subscription_id: sub_id) do
            %Subscription{user_id: uid} when is_binary(uid) -> write_subscription_row(uid, sub)
            nil -> :ok
          end
      end

      if opts[:then_claim_cap], do: claim_cap_for_sub(sub)

      :ok
    end
  end

  defp sync_subscription_object(_, _), do: :ok

  defp has_prices?(%{"items" => %{"data" => [_ | _] = items}}),
    do: Enum.all?(items, &is_binary(get_in(&1, ["price", "lookup_key"])))

  defp has_prices?(_), do: false

  # One slot per activated subscription; the webhook path (not checkout
  # start) claims it so cancelled/expired checkouts never burn capacity.
  defp claim_cap_for_sub(sub) do
    plan = plan_from_sub(sub)
    if active_status?(sub["status"]) and is_binary(plan), do: SignupCaps.claim!(plan)

    :ok
  end

  @doc "Writes Stripe subscription state onto the user's row (upsert)."
  def write_subscription_row(user_id, sub) when is_binary(user_id) and is_map(sub) do
    {:ok, row} = ensure(user_id)

    extras = extra_items(sub)

    attrs = %{
      stripe_customer_id: sub["customer"],
      stripe_subscription_id: sub["id"],
      plan: plan_from_sub(sub) || row.plan,
      status: sub["status"],
      current_period_end: to_dt(sub["current_period_end"]),
      extra_users: extras["annotate_extra_user_monthly"] || 0,
      extra_gb: extras["annotate_extra_gb_monthly"] || 0,
      trial_ends_at: to_dt(sub["trial_end"]) || row.trial_ends_at
    }

    # A webhook that moves a local trial out of the planless-trial state
    # (paid plan takes over, or the trial is canceled) frees its intake slot.
    if local_trial?(row) and not local_trial_attrs?(attrs),
      do: SignupCaps.release(SignupCaps.trial_plan())

    row
    |> Subscription.changeset(attrs)
    |> Repo.update()

    :ok
  end

  # The local trial: planless, trialing, no Stripe subscription attached.
  defp local_trial?(%Subscription{plan: nil, status: "trialing", stripe_subscription_id: nil}),
    do: true

  defp local_trial?(_), do: false

  defp local_trial_attrs?(%{plan: nil, status: "trialing"}), do: true
  defp local_trial_attrs?(_), do: false

  # The plan is the item whose price lookup key is a base plan key.
  defp plan_from_sub(sub) do
    sub
    |> items()
    |> Enum.find_value(fn item ->
      lookup = get_in(item, ["price", "lookup_key"])

      Plans.all()
      |> Enum.find_value(fn {key, plan} -> (plan.lookup_key == lookup && key) || nil end)
    end)
  end

  defp extra_items(sub) do
    items(sub)
    |> Enum.reduce(%{}, fn item, acc ->
      lookup = item_lookup(item)

      if MapSet.member?(Plans.extra_lookup_keys(), lookup),
        do: Map.put(acc, lookup, item["quantity"] || 0),
        else: acc
    end)
  end

  defp items(%{"items" => %{"data" => data}}) when is_list(data), do: data
  defp items(%{"items" => data}) when is_list(data), do: data
  defp items(_), do: []

  defp item_lookup(item), do: get_in(item, ["price", "lookup_key"])

  defp active_status?(status), do: status in @active

  # Stripe hands timestamps as unix seconds.
  defp to_dt(nil), do: nil

  defp to_dt(seconds) when is_integer(seconds),
    do: DateTime.from_unix!(seconds) |> DateTime.truncate(:second)

  defp to_dt(_), do: nil

  defp ensure_billing do
    if Stripe.enabled?(), do: :ok, else: {:error, :stripe_disabled}
  end
end
