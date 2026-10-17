defmodule AnnotateWeb.BillingWebhookController do
  @moduledoc """
  Stripe webhook receiver: `POST /api/v1/billing/webhook`.

  Verifies the `stripe-signature` header against the RAW request body (the
  endpoint's body reader caches it in `conn.private[:raw_body]`), then applies
  the event idempotently — processed event ids are stored in
  `billing_processed_events`, so Stripe's retries are answered `200` and
  skipped. Answers `200` for recognized-but-unhandled types too: anything
  else makes Stripe back off and re-deliver forever.
  """

  use AnnotateWeb, :controller

  require Logger

  def create(conn, _params) do
    raw_body = conn.private[:raw_body]
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Annotate.Billing.Stripe.construct_event(raw_body, signature) do
      {:ok, event} ->
        case Annotate.Billing.Subscriptions.apply_event(event) do
          {:ok, :duplicate} ->
            json(conn, %{"received" => true, "duplicate" => true})

          :ok ->
            json(conn, %{"received" => true})

          {:error, reason} ->
            # Signature verified but application failed: 500 makes Stripe retry.
            Logger.error(
              "billing webhook event #{inspect(event["id"])} failed: #{inspect(reason)}"
            )

            conn |> put_status(:internal_server_error) |> json(%{"error" => "apply_failed"})
        end

      {:error, :stripe_disabled} ->
        conn |> put_status(:service_unavailable) |> json(%{"error" => "stripe_disabled"})

      {:error, _reason} ->
        conn |> put_status(:bad_request) |> json(%{"error" => "invalid_signature"})
    end
  end
end
