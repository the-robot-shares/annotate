defmodule Annotate.Billing.Stripe do
  @moduledoc """
  Thin adapter over **stripity_stripe** for annotate subscriptions (pattern
  ported from meetme.noizu.com). Owns exactly the Stripe calls the app makes;
  every entry point fails soft — with no key configured `enabled?/0` is false
  and calls return `{:error, :stripe_disabled}` rather than raising, so dev,
  test and an unconfigured prod boot enforce nothing.

  Config (runtime.exs, from ANNOTATE_STRIPE_* env):

      config :annotate, Annotate.Billing.Stripe,
        enabled: true,
        api_key: ...,
        webhook_secret: ...,
        publishable_key: ...,
        portal_return_url: "https://annotate.therobotlives.com/dashboard/billing"

  Live objects: ONE product ("Annotate") with monthly prices carrying lookup
  keys `annotate_start_monthly`, `annotate_standard_monthly`,
  `annotate_team_monthly`, `annotate_extra_user_monthly`,
  `annotate_extra_gb_monthly`, `annotate_agent_addon_monthly`
  (`mix annotate.stripe.setup` creates them in TEST mode).
  """

  defp base_url do
    System.get_env("FRONTEND_URL") ||
      Application.get_env(:annotate, :frontend_url) ||
      "https://annotate.therobotlives.com"
  end

  @doc "True when a Stripe secret key is configured and billing is switched on."
  def enabled? do
    conf = config()
    conf[:enabled] == true and present?(conf[:api_key])
  end

  @doc "Configured webhook signing secret, or nil."
  def webhook_secret, do: config()[:webhook_secret]

  def webhook_enabled?, do: present?(webhook_secret())

  @doc "Publishable key (client side), or nil."
  def publishable_key, do: presence(config()[:publishable_key])

  def portal_return_url,
    do: config()[:portal_return_url] || trim(base_url()) <> "/dashboard/billing"

  def checkout_success_url, do: trim(base_url()) <> "/dashboard/billing?checkout=success"
  def checkout_cancel_url, do: trim(base_url()) <> "/dashboard/billing?checkout=cancelled"

  @doc "Resolves the active price id for a lookup key."
  def price_id(lookup_key) when is_binary(lookup_key) do
    with :ok <- ensure_configured(),
         {:ok, %{data: [%{id: id} | _]}} <-
           Stripe.Price.list(%{lookup_keys: [lookup_key], active: true, limit: 1}) do
      {:ok, id}
    else
      {:ok, %{data: []}} -> {:error, :price_not_found}
      {:error, _} = err -> err
    end
  end

  @doc """
  Creates a Stripe customer for a dashboard user. `user_id` rides in metadata
  so the Stripe dashboard maps customers back to users.
  """
  def create_customer(user_id, attrs \\ %{}) do
    with :ok <- ensure_configured() do
      params =
        %{}
        |> maybe_put(:email, attrs[:email] || attrs["email"])
        |> Map.put(:metadata, %{"user_id" => to_string(user_id), "source" => "annotate"})

      Stripe.Customer.create(params)
    end
  end

  @doc "Creates a subscription-mode Checkout Session for `price_id`."
  def create_checkout_session(customer_id, price_id, opts \\ []) do
    with :ok <- ensure_configured() do
      params = %{
        mode: "subscription",
        customer: customer_id,
        line_items: [
          %{
            price: price_id,
            quantity: 1
          }
        ],
        success_url: checkout_success_url(),
        cancel_url: checkout_cancel_url(),
        subscription_data: %{
          metadata: %{
            "user_id" => to_string(Keyword.get(opts, :user_id)),
            "plan" => to_string(Keyword.get(opts, :plan))
          }
        },
        metadata: %{
          "user_id" => to_string(Keyword.get(opts, :user_id)),
          "plan" => to_string(Keyword.get(opts, :plan))
        },
        allow_promotion_codes: true
      }

      Stripe.Checkout.Session.create(params)
    end
  end

  @doc "Billing Portal session — card changes, cancellation, invoices."
  def create_portal_session(customer_id, return_url \\ nil) when is_binary(customer_id) do
    with :ok <- ensure_configured(),
         {:ok, %{url: url}} <-
           Stripe.BillingPortal.Session.create(%{
             customer: customer_id,
             return_url: return_url || portal_return_url()
           }) do
      {:ok, url}
    end
  end

  @doc "Retrieves a subscription WITH its items (price + lookup keys)."
  def retrieve_subscription(subscription_id) when is_binary(subscription_id) do
    with :ok <- ensure_configured() do
      Stripe.Subscription.retrieve(subscription_id, expand: ["items.data.price"])
    end
  end

  @doc """
  Replaces the quantity-priced extra items (extra users / extra GB) on a
  subscription, preserving every other item. `extras` is a map of lookup_key
  => quantity (0 removes the item).
  """
  def update_subscription_items(subscription, extras) when is_map(extras) do
    with :ok <- ensure_configured(),
         {:ok, sub} <- retrieve_subscription(subscription) do
      by_lookup =
        sub.items.data
        |> Enum.map(fn item -> {item.price.lookup_key, item} end)
        |> Map.new()

      keep =
        Enum.flat_map(sub.items.data, fn item ->
          if MapSet.member?(extra_lookup_keys(), item.price.lookup_key || "") do
            []
          else
            [%{id: item.id}]
          end
        end)

      extra_items =
        Enum.flat_map(extras, fn {lookup_key, qty} ->
          qty = max(qty || 0, 0)

          cond do
            qty == 0 ->
              []

            item = by_lookup[lookup_key] ->
              [%{id: item.id, quantity: qty}]

            true ->
              case price_id(lookup_key) do
                {:ok, price_id} -> [%{price: price_id, quantity: qty}]
                _ -> []
              end
          end
        end)

      Stripe.Subscription.update(subscription, %{items: keep ++ extra_items})
    end
  end

  defp extra_lookup_keys,
    do: Annotate.Billing.Plans.extra_lookup_keys()

  @doc """
  Verifies a raw webhook payload against the `stripe-signature` header and
  returns the event as a plain string-keyed map (tolerant of API drift).
  """
  def construct_event(raw_body, signature) do
    cond do
      not webhook_enabled?() ->
        {:error, :stripe_disabled}

      not is_binary(raw_body) ->
        {:error, :missing_body}

      is_nil(signature) ->
        {:error, :missing_signature}

      true ->
        Stripe.Webhook.construct_event(raw_body, signature, webhook_secret(), response_as: :map)
    end
  end

  # stripity_stripe reads :stripity_stripe, :api_key; we keep the value in our
  # own app env and push it over on demand (re-readable at runtime).
  @doc false
  def ensure_configured do
    if enabled?() do
      Application.put_env(:stripity_stripe, :api_key, config()[:api_key])
      :ok
    else
      {:error, :stripe_disabled}
    end
  end

  defp config, do: Application.get_env(:annotate, __MODULE__, [])

  defp present?(value), do: is_binary(value) and value != ""
  defp presence(value), do: if(present?(value), do: value)
  defp trim(url) when is_binary(url), do: String.trim_trailing(url, "/")

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, _k, ""), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
