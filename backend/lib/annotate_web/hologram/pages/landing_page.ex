defmodule AnnotateWeb.Hologram.Pages.LandingPage do
  @moduledoc """
  Marketing landing page (Night Desk direction) — owns `route "/"`.

  Dogfoods the product: the page runs the live page-comments widget (embedded
  by LandingLayout), and the hero CTA drives the real widget into pick mode.
  Copy: `design/landing/COPY.md`. IA: `design/landing/IA.md`.
  """

  use Hologram.Page

  alias AnnotateWeb.Hologram.Components.GithubAuth

  alias AnnotateWeb.Hologram.Components.SiteFooter
  alias AnnotateWeb.Hologram.Layouts.LandingLayout

  route "/"
  layout LandingLayout, page_title: "annotate — site feedback that points at the thing"

  def init(_params, component, _server) do
    cfg = marketing_cfg()

    component
    |> put_state(:copied, false)
    |> put_state(:snippet_src, cfg.widget_src)
    |> put_state(:snippet_api, cfg.api_base)
  end

  def template do
    ~HOLO"""
    <header class="nd-nav">
      <div class="nd-nav__inner">
        <a class="nd-nav__brand" href="/"><span class="nd-nav__dot" aria-hidden="true"></span>annotate</a>
        <nav class="nd-nav__links" aria-label="Sections">
          <a class="nd-nav__link" href="#the-loop">The loop</a>
          <a class="nd-nav__link" href="#features">Features</a>
          <a class="nd-nav__link" href="#agents">For agents</a>
          <a class="nd-nav__link" href="/privacy">Privacy</a>
          <a class="nd-nav__link" href="/terms">Terms</a>
          <a class="nd-nav__link" href="#faq">FAQ</a>
        </nav>
        <button type="button" class="nd-btn nd-btn--primary nd-btn--sm nd-nav__cta" $click="try_it">
          Try it on this page
        </button>
        <GithubAuth cid="landing_github_auth" variant="nd" />
      </div>
    </header>

    <main id="main">
      <section class="nd-hero">
        <div class="nd-hero__inner">
          <div>
            <p class="nd-hero__eyebrow">annotate</p>
            <h1>From a comment on the page to a fix in the repo.</h1>
            <p class="nd-hero__sub">
              annotate anchors visitor feedback to the element it's about and streams
              it to your dashboard and API. The next leg — MCP hooks so agents triage,
              investigate, and patch — is in development.
            </p>
            <div class="nd-hero__ctas">
              <button type="button" class="nd-btn nd-btn--primary" $click="try_it">
                Try it on this page
              </button>
              <a class="nd-btn nd-btn--secondary" href="#add-to-your-site">Add to your site</a>
            </div>
            <p class="nd-hero__caption">No signup needed to look around. Sign-in is required to post.</p>
          </div>
          <figure class="nd-hero__art">
            <picture>
              <source type="image/webp" srcset="/images/landing/hero-loop-1600.webp" />
              <img
                src="/images/landing/hero-loop-1600.png"
                alt="A comment pinned to a page's Export button becomes a ticket, then an agent reports a patch ready."
                width="1600"
                height="1000"
                fetchpriority="high"
              />
            </picture>
            <figcaption>
              The rail on this page is the real widget.
            </figcaption>
          </figure>
        </div>
      </section>

      <section class="nd-section" id="the-loop">
        <div class="nd-section__inner">
          <p class="nd-section__label">The loop</p>
          <h2>Comment. Triage. Ticket. Patch. Resolve.</h2>
          <ol class="nd-loop">
            <li class="nd-step">
              <h3>Comment on the page</h3>
              <p>A visitor selects the button, the sentence, the price row. The thread pins to that element, not to a screenshot of it.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Triage in the dashboard</h3>
              <p>Open the inbox: filter open and resolved, reply as the site team, resolve what's noise, reopen what isn't. Updates arrive live.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Ticket in your tracker</h3>
              <p>Push a thread to Jira, Notion, ClickUp, Asana, or The Robot Plans with its anchor and page context attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
            </li>
            <li class="nd-step">
              <h3>Agents investigate and patch</h3>
              <p>MCP tools let an agent query open issues, pull the anchor and context, reproduce, and open a patch.</p>
              <span class="nd-chip nd-chip--dev">In development</span>
            </li>
            <li class="nd-step">
              <h3>Resolve back on the page</h3>
              <p>The thread closes where it started, and anyone viewing the page sees it settled.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
          </ol>
          <p class="nd-footnote">
            Steps 1, 2, and 5 work today. Step 3 is planned and step 4 is in development —
            the REST API already carries what they need.
          </p>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="features">
        <div class="nd-section__inner">
          <p class="nd-section__label">Features</p>
          <h2>What ships in the script</h2>
          <div class="nd-bento">
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">anchor</span>
              <h3>Anchor that survives</h3>
              <p>
                id, CSS, XPath, text quote, and position strategies with fallbacks;
                repair an anchor when the DOM shifts. Deep links reopen the exact spot.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">rail + ring</span>
              <h3>Rail and ring</h3>
              <p>
                The rail floats beside the element and follows scroll; open a comment
                and the element rings on the page.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">threads</span>
              <h3>Threads with a lifecycle</h3>
              <p>
                Nested replies, resolve, reopen. Edit and delete stay with the author;
                moderation stays with the site owner.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <figure class="nd-tile__media">
                <picture>
                  <source type="image/avif" srcset="/images/landing/feature-annotate-1184.avif" />
                  <source type="image/webp" srcset="/images/landing/feature-annotate-1088.webp 1x, /images/landing/feature-annotate-1184.webp 2x" />
                  <img
                    src="/images/landing/feature-annotate-1184.png"
                    alt="Illustration of the screenshot editor with a cropped region, a drawn box, arrow, pen squiggle, text label, and a blurred area"
                    width="1184"
                    height="864"
                    loading="lazy"
                  />
                </picture>
              </figure>
              <h3>Screenshots and attachments</h3>
              <p>
                Crop the page and draw boxes, arrows, freehand, text, and blur; attach
                files and images to any comment. Failed uploads retry on their own.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">live</span>
              <h3>Live updates</h3>
              <p>New comments, replies, and resolutions arrive over a websocket, no refresh.</p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">rules</span>
              <h3>Rules, roles, sign-in</h3>
              <p>
                Per-site comment policy (anonymous opt-in, guest names), team members
                with roles, GitHub sign-in for the dashboard, and visitor sign-in through
                your identity provider or your own site vouching for its users.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section" id="agents">
        <div class="nd-section__inner">
          <p class="nd-section__label">For agents</p>
          <h2>Built to be read by software.</h2>
          <div class="nd-agents">
            <div class="nd-agents__copy">
              <p>
                <span class="nd-chip nd-chip--live">Today</span>
                annotate is API-first. Threads, comments, anchors, and resolve state are
                served as JSON over REST, with live events over a websocket. Reads are
                public unless you restrict them; writes take a 15-minute access token
                bound to your site and its origins, refreshed with single-use tokens.
                The API reference isn't public yet.
              </p>
              <p>
                <span class="nd-chip nd-chip--dev">In development</span>
                MCP tools that package those calls for Claude and other agents — query
                open issues, triage, investigate the anchored element, patch, resolve — so
                the loop from "someone complained here" to "merged" closes without a human
                carrying the context.
              </p>
              <p>
                <a class="nd-btn nd-btn--secondary" href="#waitlist" data-waitlist-interest="mcp">Tell me when MCP tools ship</a>
              </p>
            </div>
            <ul class="nd-agents__status" aria-label="Agent surface status">
              <li><span>REST API</span><span class="nd-chip nd-chip--live">Available today</span></li>
              <li><span>Realtime events</span><span class="nd-chip nd-chip--live">Available today</span></li>
              <li><span>MCP tools</span><span class="nd-chip nd-chip--dev">In development</span></li>
            </ul>
          </div>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="integrations">
        <div class="nd-section__inner">
          <p class="nd-section__label">Integrations</p>
          <h2>Where the work goes next.</h2>
          <ul class="nd-roster">
            <li>
              <h3>REST API and realtime</h3>
              <p>Everything below is reachable through it today.</p>
              <span class="nd-chip nd-chip--live">Available today</span>
            </li>
            <li>
              <h3>The Robot Plans</h3>
              <p>Our sibling planning tool.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
              <a href="#waitlist" data-waitlist-interest="robot-plans">Tell me when it ships</a>
            </li>
            <li>
              <h3>Jira</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
              <a href="#waitlist" data-waitlist-interest="jira">Tell me when it ships</a>
            </li>
            <li>
              <h3>Notion</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
              <a href="#waitlist" data-waitlist-interest="notion">Tell me when it ships</a>
            </li>
            <li>
              <h3>ClickUp</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
              <a href="#waitlist" data-waitlist-interest="clickup">Tell me when it ships</a>
            </li>
            <li>
              <h3>Asana</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
              <a href="#waitlist" data-waitlist-interest="asana">Tell me when it ships</a>
            </li>
          </ul>
          <p class="nd-footnote">
            Ticket creation lands tracker by tracker. None are live yet; the REST API is the
            honest today-answer. Product names are text only: Jira, Notion, ClickUp, and Asana
            belong to their owners, and annotate isn't affiliated with them.
          </p>
        </div>
      </section>

      <section class="nd-section" id="waitlist">
        <div class="nd-section__inner">
          <p class="nd-section__label">Waitlist</p>
          <h2>Get one email when these ship.</h2>
          <p class="nd-section__intro">
            Pick what you want to hear about. One email per feature when it's live, nothing else.
          </p>
          <div class="nd-waitlist" data-waitlist-box>
            <form action="/waitlist" method="post" data-waitlist novalidate>
              <fieldset>
                <legend class="nd-waitlist__legend">Tell me about</legend>
                <div class="nd-waitlist__opts">
                  <label><input type="checkbox" name="interests" value="mcp" checked /> MCP agent tools</label>
                  <label><input type="checkbox" name="interests" value="robot-plans" /> The Robot Plans</label>
                  <label><input type="checkbox" name="interests" value="jira" /> Jira</label>
                  <label><input type="checkbox" name="interests" value="notion" /> Notion</label>
                  <label><input type="checkbox" name="interests" value="clickup" /> ClickUp</label>
                  <label><input type="checkbox" name="interests" value="asana" /> Asana</label>
                </div>
              </fieldset>
              <div class="nd-hp" aria-hidden="true">
                <label>Leave this empty <input type="text" name="website" tabindex="-1" autocomplete="off" /></label>
              </div>
              <div class="nd-waitlist__row">
                <label class="nd-sr-only" for="waitlist-email">Email address</label>
                <input id="waitlist-email" type="email" name="email" placeholder="you@company.com" autocomplete="email" required />
                <button type="submit" class="nd-btn nd-btn--primary">Notify me</button>
              </div>
              <p class="nd-waitlist__msg" data-waitlist-msg role="alert"></p>
              <p class="nd-waitlist__note">We store your email and the boxes you ticked. See the <a href="/privacy">privacy policy</a>.</p>
            </form>
            <div class="nd-waitlist__done" data-waitlist-done hidden tabindex="-1" role="status">
              <h3>You're on the list.</h3>
              <p>We'll email you when it ships.</p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="add-to-your-site">
        <div class="nd-section__inner">
          <p class="nd-section__label">Add to your site</p>
          <h2>Paste one snippet</h2>
          <p class="nd-section__intro">
            Paste this before &lt;/body&gt;. Replace the key with the service key for
            your site.
          </p>
          <div class="nd-snippet">
            <pre class="nd-snippet__code" tabindex="0"><code id="nd-snippet-code">&lt;<span class="nd-tok-tag">script</span> <span class="nd-tok-attr">type</span>=<span class="nd-tok-str">"module"</span> <span class="nd-tok-attr">src</span>=<span class="nd-tok-str">"{@snippet_src}"</span>&gt;&lt;/<span class="nd-tok-tag">script</span>&gt;
    &lt;<span class="nd-tok-tag">noizu-page-comments</span> <span class="nd-tok-attr">site</span>=<span class="nd-tok-str">"your-site"</span> <span class="nd-tok-attr">api-base</span>=<span class="nd-tok-str">"{@snippet_api}"</span> <span class="nd-tok-attr">enabled</span>&gt;&lt;/<span class="nd-tok-tag">noizu-page-comments</span>&gt;</code></pre>
            <div class="nd-snippet__aside">
              <button type="button" class="nd-btn nd-btn--secondary" $click="copy_snippet">
                {%if @copied}Copied ✓{%else}Copy code{/if}
              </button>
              <p class="nd-snippet__note">Create keys and set rules in the dashboard.</p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section" id="privacy">
        <div class="nd-section__inner">
          <p class="nd-section__label">Privacy &amp; security</p>
          <h2>Built to stay out of the way</h2>
          <ul class="nd-privacy">
            <li>Tokens are bound to your origin — a key only works on the domains you register.</li>
            <li>No third-party cookies; the widget stores only what it needs to keep you signed in.</li>
            <li>Comments are publicly readable by default; you can restrict reading per site.</li>
            <li>Your comment data is yours — delete it from the dashboard, or ask us for an export.</li>
          </ul>
        </div>
      </section>

      <section class="nd-dogfood">
        <div class="nd-dogfood__inner">
          <p class="nd-dogfood__text">
            <strong>This page runs annotate.</strong> Select anything on it and leave
            a comment — you're looking at the product.
          </p>
          <button type="button" class="nd-btn nd-btn--primary nd-btn--sm" $click="try_it">
            Try it on this page
          </button>
        </div>
      </section>

      <section class="nd-section" id="faq">
        <div class="nd-section__inner">
          <p class="nd-section__label">FAQ</p>
          <h2>Questions</h2>
          <div class="nd-faq">
            <details>
              <summary>Does the script slow my page down?</summary>
              <p>
                The widget loads asynchronously after your page renders and is cached
                at the edge. It doesn't block rendering and doesn't shift layout.
              </p>
            </details>
            <details>
              <summary>Who can see the comments?</summary>
              <p>
                By default anyone on the page can read, and only signed-in visitors
                can post. Both can be changed per site.
              </p>
            </details>
            <details>
              <summary>How do visitors sign in?</summary>
              <p>
                Through an Authentik popup, or — if you enable it — your own site
                vouches for its logged-in users, so your users never see our sign-in.
                Site owners sign in to the dashboard with GitHub.
              </p>
            </details>
            <details>
              <summary>Can someone use my key on their site?</summary>
              <p>
                No. Keys are bound to the origins you register; requests from other
                domains are rejected.
              </p>
            </details>
            <details>
              <summary>What can people attach?</summary>
              <p>
                Files and images on any comment, plus screenshots taken on the page —
                cropped, with boxes, arrows, freehand pen, text, and blur drawn on top.
              </p>
            </details>
            <details>
              <summary>Does it work with my stack?</summary>
              <p>
                If your page runs in a browser, yes — one script tag, no framework
                requirements, no build step.
              </p>
            </details>
            <details>
              <summary>Can an AI agent read the feedback?</summary>
              <p>
                Over the REST API, yes: threads, comments, anchors, and resolve state are
                served as JSON, and reads are public unless you restrict them. MCP tools
                that make that a one-liner for Claude and other agents are in development;
                the waitlist above is how you hear when they ship.
              </p>
            </details>
            <details>
              <summary>What data is stored per comment?</summary>
              <p>
                The thread's page URL, path, query parameters, hash, page title, and a
                multi-strategy anchor (CSS selector, XPath, text quote, position) — the
                minimum needed to find the exact spot again. The privacy policy lists the rest.
              </p>
            </details>
            <details>
              <summary>Which trackers does it sync with?</summary>
              <p>
                None yet. Jira, Notion, ClickUp, Asana, and The Robot Plans are planned;
                the REST API covers programmatic export today.
              </p>
            </details>
          </div>
        </div>
      </section>
    </main>

    <SiteFooter />

    <window $click={action: :reset_copied, delay: 2000} />
    """
  end

  # Hero CTA: arm the widget and enter pick mode. The widget bootstraps after
  # its module script loads, so poll briefly for the rail's pick control and
  # click it (see tobor-kit page-comments: `[data-cy="comments.pick"]`).
  def action(:try_it, _params, component) do
    Hologram.JS.exec("""
    var w = document.querySelector('noizu-page-comments');
    if (w) { try { w.enabled = true; } catch (e) {} }
    var tries = 0;
    var timer = setInterval(function() {
      var rail = document.querySelector('noizu-page-comments-rail');
      var pick = rail && rail.shadowRoot &&
        rail.shadowRoot.querySelector('[data-cy="comments.pick"]');
      if (pick) { clearInterval(timer); pick.click(); }
      else if (++tries > 40) { clearInterval(timer); }
    }, 50);
    """)

    component
  end

  # The client reads the rendered snippet text straight from the DOM. The
  # snippet never travels in page state: Hologram's runtime state serializer
  # does not escape newlines (or "</script>"), so a multi-line string here
  # would corrupt the inline mount script and break hydration.
  def action(:copy_snippet, _params, component) do
    Hologram.JS.exec(
      "var e=document.getElementById('nd-snippet-code');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    put_state(component, :copied, true)
  end

  def action(:reset_copied, _params, component) do
    put_state(component, :copied, false)
  end

  defp marketing_cfg do
    case Application.get_env(:annotate, :marketing) do
      kw when is_list(kw) ->
        %{
          api_base: Keyword.get(kw, :api_base, "https://annotate-srv.therobotlives.com"),
          widget_src:
            Keyword.get(
              kw,
              :widget_src,
              "https://cdn.derobot.is/tobor-kit/sha-5239abef2237bb118cdd75f67eb8b38023ae6620/components/page-comments/page-comments.js"
            )
        }

      _ ->
        %{
          api_base: "https://annotate-srv.therobotlives.com",
          widget_src:
            "https://cdn.derobot.is/tobor-kit/sha-5239abef2237bb118cdd75f67eb8b38023ae6620/components/page-comments/page-comments.js"
        }
    end
  end
end
