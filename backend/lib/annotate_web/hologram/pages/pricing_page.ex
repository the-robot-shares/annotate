defmodule AnnotateWeb.Hologram.Pages.PricingPage do
  @moduledoc """
  `/pricing` — plan catalog: Start $0.99, Standard $3.99, Team $9.99
  (+$0.99 per extra user/GB), agent add-on $4.95 coming soon (waitlist).
  Comments are unlimited on every plan; every account starts with a 14-day
  trial. Catalog data is serialized from `Annotate.Billing.Plans` in init
  (server-side) — templates only render plain strings.

  Checkout starts from the dashboard (`/dashboard/billing`) so the session
  user is always the billing owner.
  """

  use Hologram.Page

  alias Annotate.Billing.Plans
  alias Annotate.Billing.SignupCaps
  alias AnnotateWeb.Hologram.Layouts.LandingLayout
  alias AnnotateWeb.Hologram.Components.SiteFooter

  route "/pricing"
  layout LandingLayout, page_title: "Pricing — annotate"

  def init(_params, component, _server) do
    plans =
      Enum.map(Plans.purchasable(), fn key ->
        plan = Plans.get(key)

        %{
          key: key,
          name: plan.name,
          price: price_display(plan.price_cents),
          per: "/mo",
          apps: apps_display(plan.apps),
          users: Integer.to_string(plan.users) <> " users",
          storage: bytes_display(plan.storage_bytes) <> " storage",
          extras: plan[:extras] == true,
          note:
            if plan[:extras] do
              "+$0.99/user/mo and +$0.99/GB/mo beyond the included 5 users / 10 GB"
            else
              nil
            end,
          featured: key == "standard",
          # Same flow as the landing cards: signed-out goes through sign-in,
          # which bounces back to billing with the plan highlighted; a signed-in
          # visitor lands on billing directly.
          href:
            "/sign-in?return_to=" <>
              URI.encode_www_form("/dashboard/billing?plan=" <> key),
          cta: "Pick " <> plan.name
        }
      end)

    agent = Plans.get("agent_addon")

    # The agent add-on is a real, shipping plan — its cap row gates it
    # (cap 0 until the full agent implementation lands). Availability is
    # derived from plan_signup_caps only: flipping cap > 0 re-enables the
    # card and checkout end-to-end with no code change (user decision
    # 2026-10-18).
    agent_status = SignupCaps.status("agent_addon")
    agent_available = is_map(agent_status) and agent_status.cap > 0

    put_state(component,
      plans: plans,
      agent_price: price_display(agent.price_cents),
      agent_unavailable: not agent_available,
      agent_unavailable_message: Plans.unavailable_message(),
      faq_trial: "Every account starts with a 14-day free trial of everything."
    )
  end

  def template do
    ~HOLO"""
    <header class="nd-nav">
      <div class="nd-nav__inner">
        <a class="nd-nav__brand" href="/"><span class="nd-nav__dot" aria-hidden="true"></span>annotate</a>
        <nav class="nd-nav__links" aria-label="Sections">
          <a class="nd-nav__link" href="/#features">Features</a>
          <a class="nd-nav__link" href="/#faq">FAQ</a>
          <a class="nd-nav__link" href="/privacy">Privacy</a>
        </nav>
        <a class="nd-btn nd-btn--primary nd-btn--sm" href="/dashboard/billing" data-cy="pricing-cta">
          Start your trial
        </a>
      </div>
    </header>

    <section class="nd-hero" data-cy="pricing-hero">
      <div class="nd-hero__inner">
        <p class="nd-hero__eyebrow">Pricing</p>
        <h1>Simple plans. Unlimited comments.</h1>
        <p class="nd-hero__sub">
          Every plan includes unlimited page comments. Limits apply to the
          number of sites, team members and attachment storage — not to
          feedback. Start with a 14-day free trial; no card required to try.
        </p>
      </div>
    </section>

    <section class="nd-section nd-section--canvas" data-cy="pricing-plans">
      <div class="nd-section__inner">
        <p class="nd-section__label">Plans</p>
        <h2>Pick a size, change any time</h2>
        <div class="nd-bento">
          {%for p <- @plans}
            <a class="nd-tile nd-tile--third nd-tile--plan" href={p.href} data-cy="pricing-plan">
              <h3>{p.name} — {p.price}{p.per}</h3>
              <p>
                {p.apps} · {p.users} · {p.storage} · unlimited comments.
                {%if p.note}{p.note}.{/if}
              </p>
              <span class="nd-tile__cta">{p.cta} →</span>
            </a>
          {/for}
        </div>
        <p class="nd-footnote">
          Plans fill in limited early batches — if a plan shows full at
          checkout you can join the waitlist and we'll email you when a spot
          opens. Checkout and payment management run on Stripe, from your
          dashboard Billing page.
        </p>
      </div>
    </section>

    <section class="nd-section nd-section--canvas" data-cy="pricing-agent">
      <div class="nd-section__inner">
        <p class="nd-section__label">Add-on</p>
        <h2>Agent triage</h2>
        <p>
          An AI agent that triages your comment inbox for {@agent_price}/mo:
          deduplicates, drafts replies and marks threads resolved.
        </p>
        {%if @agent_unavailable}
          <button type="button" class="nd-btn nd-btn--sm nd-btn--ghost" aria-disabled="true"
            $click={:agent_unavailable} data-cy="pricing-agent-cta">
            Get the agent add-on — {@agent_price}/mo
          </button>
          <p class="nd-footnote" role="status" data-cy="pricing-agent-unavailable">{@agent_unavailable_message}</p>
          <p class="nd-footnote">
            The agent is rolling out in limited batches — join the waitlist on
            your dashboard Billing page and we'll email you when a spot opens.
          </p>
        {%else}
          <a class="nd-btn nd-btn--sm nd-btn--primary" href="/dashboard/billing" data-cy="pricing-agent-cta">
            Get the agent add-on — {@agent_price}/mo
          </a>
        {/if}
      </div>
    </section>

    <section class="nd-section nd-section--canvas" data-cy="pricing-faq">
      <div class="nd-section__inner">
        <p class="nd-section__label">Questions</p>
        <div class="nd-faq">
          <details>
            <summary>How does the trial work?</summary>
            <p>{@faq_trial} When it ends without a subscription, your sites stay
            visible and every existing comment remains readable — they just go
            read-only until you pick a plan.</p>
          </details>
          <details>
            <summary>What counts as a user?</summary>
            <p>Distinct team members across the sites you own. Your site
            visitors never count and never need accounts.</p>
          </details>
          <details>
            <summary>Can I change plans?</summary>
            <p>Any time, from your dashboard Billing page (Stripe hosts
            checkout and payment management).</p>
          </details>
          <details>
            <summary>What happens to comments if I downgrade or cancel?</summary>
            <p>They stay up and stay exportable. New comments pause until a
            plan is active again.</p>
          </details>
        </div>
      </div>
    </section>

    <SiteFooter />
    """
  end

  # ── display helpers (init-only, server side) ──────────────────

  def action(:agent_unavailable, _params, c),
    do: put_state(c, agent_unavailable: true)

  defp price_display(cents) when is_integer(cents),
    do: "$" <> :erlang.float_to_binary(cents / 100, decimals: 2)

  defp apps_display(:unlimited), do: "Unlimited sites"
  defp apps_display(n) when is_integer(n), do: Integer.to_string(n) <> " sites"
  defp apps_display(_), do: "—"

  defp bytes_display(b) when is_integer(b) and b >= 1_073_741_824,
    do: :erlang.float_to_binary(b / 1_073_741_824, decimals: 0) <> " GB"

  defp bytes_display(b) when is_integer(b) and b >= 1_048_576,
    do: :erlang.float_to_binary(b / 1_048_576, decimals: 0) <> " MB"

  defp bytes_display(b) when is_integer(b), do: Integer.to_string(b) <> " B"
end
