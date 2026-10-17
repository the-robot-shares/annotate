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
    # Visitors copy the always-newest loader; this page itself runs the pin.
    |> put_state(:snippet_src, AnnotateWeb.WidgetCdn.latest_src())
    |> put_state(:snippet_api, cfg.api_base)
    |> put_state(:mcp_url, AnnotateWeb.SEO.origin() <> "/mcp")
  end

  def template do
    ~HOLO"""
    <header class="nd-nav">
      <div class="nd-nav__inner">
        <a class="nd-nav__brand" href="/"><span class="nd-nav__dot" aria-hidden="true"></span>annotate</a>
        <nav class="nd-nav__links" aria-label="Sections">
          <a class="nd-nav__link" href="#how-it-works">How it works</a>
          <a class="nd-nav__link" href="#the-loop">The loop</a>
          <a class="nd-nav__link" href="#features">Features</a>
          <a class="nd-nav__link" href="#agents">For agents</a>
          <a class="nd-nav__link" href="/mcp-server">MCP</a>
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
              it to your dashboard, your API and your AI agents — over MCP, an agent
              can triage, investigate, reply and resolve.
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

      <section class="nd-section nd-section--canvas" id="how-it-works">
        <div class="nd-section__inner">
          <p class="nd-section__label">How it works</p>
          <h2>Seven steps, on the real widget.</h2>
          <p class="nd-section__intro">
            Frames from a demo dashboard running the embed — a visitor leaves feedback,
            the site's team answers, the thread closes where it started. Everything
            shown ships in the script today.
          </p>
          <ol class="nd-flow">
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-1-pick.webp?v=1" />
                  <img
                    src="/images/landing/flow-1-pick.png?v=1"
                    alt="Comment rail in pick mode: a dashed target ring highlights the churn KPI's 1.8% value on a dark analytics dashboard."
                    width="1280"
                    height="800"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">1</span> Pick the element</h3>
                <p>Arm the comment pill and click anything on the page — a KPI, a row, a sentence. A dashed ring shows the target while you aim; text selections work too.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-2-compose.webp?v=1" />
                  <img
                    src="/images/landing/flow-2-compose.png?v=1"
                    alt="Composer anchored to the churn KPI, quoting its 1.8% value, with comment text typed and Attach, Capture and Screen capture buttons."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">2</span> Write the comment</h3>
                <p>The composer opens anchored to your pick and quotes it. Post under your sign-in, or as a guest name if the site allows it.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-3-snip.webp?v=1" />
                  <img
                    src="/images/landing/flow-3-snip.png?v=1"
                    alt="Crop screenshot dialog: a crop rectangle with drag handles around the churn KPI, zoom controls, and keyboard hints for move, resize, zoom and pan."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">3</span> Crop the page</h3>
                <p>Capture the page and keep just the region that matters — zoom, pan, and nudge the rectangle with the keyboard.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-4-attach.webp?v=1" />
                  <img
                    src="/images/landing/flow-4-attach.png?v=1"
                    alt="Composer with the cropped screenshot and a churn-definition.txt file attached, ready to post."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">4</span> Mark it up, attach the rest</h3>
                <p>Draw on the crop, then attach files — uploads run while you keep typing, and retry on their own if they fail.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-5-reply.webp?v=1" />
                  <img
                    src="/images/landing/flow-5-reply.png?v=1"
                    alt="Thread view: the visitor's comment with the marked-up crop and attached file, the site team's reply naming the churn window and a ticket, and the element ringed on the page."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">5</span> The team answers</h3>
                <p>Opening a thread rings the element on the page. The site's team sees the marked-up crop and files, and replies as the site team.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-6-rail.webp?v=1" />
                  <img
                    src="/images/landing/flow-6-rail.png?v=1"
                    alt="Comment rail listing two open threads, with Open, Resolved and All tabs."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">6</span> Triage in the rail</h3>
                <p>The rail is the page's inbox — open, resolved, all. Replies and resolutions arrive live, no refresh.</p>
              </div>
            </li>
            <li class="nd-flow__step">
              <figure class="nd-flow__media">
                <picture>
                  <source type="image/webp" srcset="/images/landing/flow-7-resolved.webp?v=1" />
                  <img
                    src="/images/landing/flow-7-resolved.png?v=1"
                    alt="Resolved tab of the comment rail showing the settled timezone thread with Reply and Reopen buttons."
                    width="1280"
                    height="800"
                    loading="lazy"
                    decoding="async"
                  />
                </picture>
              </figure>
              <div class="nd-flow__copy">
                <h3><span class="nd-flow__num" aria-hidden="true">7</span> Resolve where it started</h3>
                <p>Resolve closes the thread on the page where it was pinned — and reopen brings it back if it wasn't really done.</p>
              </div>
            </li>
          </ol>
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
              <p>Connect Claude Code or another MCP client: it lists open threads, pulls the anchor and page context, reproduces, patches in your repo, and replies on the thread.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Resolve back on the page</h3>
              <p>The thread closes where it started, and anyone viewing the page sees it settled.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
          </ol>
          <p class="nd-footnote">
            Steps 1, 2, 4 and 5 work today (step 4 over MCP). Step 3 is planned — the
            REST API already carries what it needs.
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
          <h2>Your agents read the feedback too.</h2>
          <p class="nd-section__intro">
            annotate ships a remote MCP server. Connect Claude Code, Claude Desktop or
            claude.ai, Cursor, VS Code or Codex, and an agent can take a thread from
            "someone complained here" to "fixed" without a human carrying the context.
          </p>
          <div class="nd-mcp">
            <div class="nd-mcp__workflow">
              <h3 class="nd-mcp__title">The agent loop</h3>
              <ol class="nd-mcp__steps">
                <li>Query open issues — <code>list_threads</code></li>
                <li>Pull one with its anchor, page context and attachments — <code>get_thread</code></li>
                <li>Triage: reproduce what the visitor saw, then find the element in your repo — the anchor names the id, CSS, XPath and text quote</li>
                <li>Patch</li>
                <li>Reply as the site team — <code>reply_to_thread</code></li>
                <li>Resolve — <code>resolve_thread</code></li>
              </ol>
              <p class="nd-mcp__note">
                Also exposed: <code>list_sites</code>, <code>get_site_config</code>,
                <code>reopen_thread</code>, <code>delete_comment</code>, resources for
                sites and threads, and two prompts — <code>triage_open_threads</code> and
                <code>investigate_thread</code>. Full reference at
                <a href="/mcp-server">/mcp-server</a>.
              </p>
            </div>
            <div class="nd-mcp__tablewrap">
              <h3 class="nd-mcp__title">What each tool does</h3>
              <table class="nd-mcp__tools">
                <thead>
                  <tr><th scope="col">Tool</th><th scope="col">Does</th></tr>
                </thead>
                <tbody>
                  <tr><td><code>list_sites</code></td><td>Your member sites, your role on each, open/resolved counts.</td></tr>
                  <tr><td><code>get_site_config</code></td><td>A site's allowed origins and read/comment policy.</td></tr>
                  <tr><td><code>list_threads</code></td><td>Filter by status, page path, origin, date, text, author.</td></tr>
                  <tr><td><code>get_thread</code></td><td>Live comments, the anchor, page context; attachment links (short-lived).</td></tr>
                  <tr><td><code>reply_to_thread</code></td><td>Post as the site team; visitors see it live.</td></tr>
                  <tr><td><code>resolve_thread</code> / <code>reopen_thread</code></td><td>Close a thread, or open it again.</td></tr>
                  <tr><td><code>delete_comment</code></td><td>Soft-delete a comment (moderators).</td></tr>
                </tbody>
              </table>
            </div>
            <div class="nd-mcp__connect">
              <h3 class="nd-mcp__title">Connect a client</h3>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-claude-code">Claude Code</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-claude-code">claude mcp add --transport http annotate {@mcp_url}</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-claude-code"}}>Copy</button>
              </div>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-claude-ai">Claude.ai / Claude Desktop</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-claude-ai">Settings → Connectors → Add custom connector
    Name: annotate
    URL:  {@mcp_url}</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-claude-ai"}}>Copy</button>
              </div>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-cursor">Cursor (~/.cursor/mcp.json)</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-cursor">\{"mcpServers": \{"annotate": \{"url": "{@mcp_url}"}}}</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-cursor"}}>Copy</button>
              </div>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-vscode">VS Code (.vscode/mcp.json)</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-vscode">\{"servers": \{"annotate": \{"type": "http", "url": "{@mcp_url}"}}}</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-vscode"}}>Copy</button>
              </div>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-codex">OpenAI Codex CLI</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-codex">codex mcp add annotate --url {@mcp_url}
    codex mcp login annotate</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-codex"}}>Copy</button>
              </div>
            </div>
            <div class="nd-mcp__trust">
              <h3 class="nd-mcp__title">How the keys stay yours</h3>
              <ul>
                <li>OAuth 2.1: the agent's client opens a browser and signs in as you — GitHub or Google. No API keys to paste.</li>
                <li><code>comments:read</code> is granted by default; replying, resolving and deleting are opt-in on the consent screen.</li>
                <li>Revoke any connected client at <a href="/dashboard/agents">/dashboard/agents</a> — its next request is refused.</li>
                <li>Every write and every refusal is audited; reads are never logged.</li>
                <li>Comment text is visitor-written: it's labelled <code>untrusted</code> so the agent treats it as data, never as instructions.</li>
              </ul>
              <p class="nd-mcp__note">
                Prefer plain HTTP? The same data is served as JSON over the REST API with
                live websocket events; reads are public unless you restrict them.
              </p>
              <p class="nd-mcp__ctas">
                <a class="nd-btn nd-btn--secondary" href="/dashboard/agents">Connect an agent</a>
                <a class="nd-btn nd-btn--ghost" href="/mcp-server">Full MCP reference</a>
              </p>
            </div>
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
    &lt;<span class="nd-tok-tag">noizu-page-comments</span> <span class="nd-tok-attr">site</span>=<span class="nd-tok-str">"your-site"</span> <span class="nd-tok-attr">api-base</span>=<span class="nd-tok-str">"{@snippet_api}"</span>&gt;&lt;/<span class="nd-tok-tag">noizu-page-comments</span>&gt;</code></pre>
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
                served as JSON, and reads are public unless you restrict them. Or connect it
                over MCP: <code>claude mcp add --transport http annotate https://annotate.therobotlives.com/mcp</code>,
                sign in, and choose what it may do.
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

  # MCP connect snippets: same DOM-read pattern as copy_snippet — ids are this
  # template's fixed literals, the code never travels through page state.
  def action(:copy_mcp, params, component) do
    Hologram.JS.exec(
      "var e=document.getElementById('" <>
        params.id <>
        "');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    component
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
              AnnotateWeb.WidgetCdn.pinned_src()
            )
        }

      _ ->
        %{
          api_base: "https://annotate-srv.therobotlives.com",
          widget_src: AnnotateWeb.WidgetCdn.pinned_src()
        }
    end
  end
end
