defmodule Mix.Tasks.Annotate.Stripe.Setup do
  @moduledoc """
  Creates (or finds) the Annotate products and monthly prices in Stripe.

      mix annotate.stripe.setup

  Run ONCE per Stripe environment after the ANNOTATE_STRIPE_* env keys exist —
  it talks to whatever key the runtime config loaded (TEST mode first, per the
  2026-10-17 decision: test-mode keys → verify Checkout in the Stripe
  dashboard → then swap in live keys and run again).

  Prices are matched by `lookup_key` (from Annotate.Billing.Plans), so the
  checkout code never depends on price ids. Re-running is safe: existing
  lookup keys are reused, missing ones are created (`transfer_lookup_key`).

  Prints the price table for verification. Never prints key values.
  """

  use Mix.Task

  @shortdoc "Create Annotate products/prices in Stripe (lookup-key idempotent)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    unless Annotate.Billing.Stripe.enabled?() do
      Mix.raise("""
      Stripe is not configured. Set ANNOTATE_STRIPE_SECRET_KEY (plus
      ANNOTATE_STRIPE_WEBHOOK_SECRET / ANNOTATE_STRIPE_PUBLISHABLE_KEY —
      see Infisical /apps/annotate) and re-run.
      """)
    end

    Annotate.Billing.Stripe.ensure_configured()

    product_id = ensure_product()

    # Only plans with a Stripe lookup key get a price (enterprise is
    # ops-assigned and carries no lookup key by design).
    plans =
      Annotate.Billing.Plans.all()
      |> Enum.filter(fn {_key, plan} -> is_binary(plan.lookup_key) end)

    base =
      Enum.map(plans, fn {_key, plan} ->
        {:ok, price} = ensure_price(product_id, plan.lookup_key, plan.price_cents, plan.name)
        {plan.key, plan.price_cents, price["id"], price["lookup_key"]}
      end)

    # Team rides two extra-item prices as quantities.
    extras =
      Enum.flat_map(plans, fn
        {_key, %{extra_gb_lookup_key: lk, extra_gb_price_cents: cents}} ->
          {:ok, price} = ensure_price(product_id, lk, cents, "Team extra GB")
          [{lk, cents, price["id"], price["lookup_key"]}]

        _ ->
          []
      end)

    rows = base ++ extras

    Mix.shell().info("")
    Mix.shell().info("Product: #{product_id}")

    Enum.each(rows, fn {plan_key, cents, price_id, lookup_key} ->
      Mix.shell().info(
        "  #{String.pad_trailing(plan_key, 30)} $#{:erlang.float_to_binary(cents / 100, decimals: 2)}/mo  #{price_id}  (#{lookup_key})"
      )
    end)

    Mix.shell().info("")

    Mix.shell().info(
      "Next: add the webhook endpoint (POST /api/v1/billing/webhook) in the Stripe dashboard, then set ANNOTATE_STRIPE_WEBHOOK_SECRET."
    )
  end

  defp ensure_product do
    case Stripe.Product.list(%{limit: 100}) do
      {:ok, %{data: products}} ->
        case Enum.find(products, &(&1["name"] == "Annotate")) do
          %{"id" => id} ->
            Mix.shell().info("Reusing existing product 'Annotate' (#{id})")
            id

          nil ->
            create_product()
        end

      {:error, reason} ->
        Mix.raise("Listing products failed: #{inspect(reason)}")
    end
  end

  defp create_product do
    case Stripe.Product.create(%{
           name: "Annotate",
           description:
             "Page comments for production websites. Plans: Start, Standard, Team (+ agent add-on waitlist)."
         }) do
      {:ok, %{"id" => id}} ->
        Mix.shell().info("Created product 'Annotate' (#{id})")
        id

      {:error, reason} ->
        Mix.raise("Product creation failed: #{inspect(reason)}")
    end
  end

  defp ensure_price(product_id, lookup_key, unit_amount_cents, nickname) do
    case Stripe.Price.list(%{lookup_keys: [lookup_key], limit: 10}) do
      {:ok, %{data: [%{"id" => _} = price | _]}} ->
        {:ok, price}

      {:ok, _} ->
        Stripe.Price.create(%{
          product: product_id,
          currency: "usd",
          unit_amount: unit_amount_cents,
          recurring: %{interval: "month"},
          lookup_key: lookup_key,
          transfer_lookup_key: true,
          nickname: "Annotate #{nickname} monthly"
        })

      {:error, reason} ->
        Mix.raise("Looking up price #{lookup_key} failed: #{inspect(reason)}")
    end
  end
end
