defmodule AnnotateWeb.Hologram.Pages.LandingPage do
  @moduledoc """
  Marketing landing page (Daylight Margin v2 direction) — owns `route "/"`.

  Dogfoods the product: the page runs the live page-comments widget (embedded
  by LandingLayout), and the hero CTA drives the real widget into pick mode.
  Copy: `design/landing/COPY-v2.md` (authoritative). IA: the approved revamp
  order — hero, try-it demo, walkthrough, features, embed, agents/MCP,
  roadmap+waitlist, FAQ, final CTA. Visual direction:
  `design/landing/prompts/d3-daylight-margin-v2/`.
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
          <a class="nd-nav__link" href="/pricing">Pricing</a>
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
            <h1>Feedback that points at the thing.</h1>
            <p class="nd-hero__sub">
              annotate pins threaded comments to the exact element or text they're about.
              Triage them in your dashboard, over the REST API — or hand the inbox to
              your AI agent over MCP.
            </p>
            <div class="nd-hero__ctas">
              <button type="button" class="nd-btn nd-btn--primary" $click="try_it">
                Try it on this page
              </button>
              <a class="nd-btn nd-btn--secondary" href="#add-to-your-site">Start free</a>
            </div>
            <p class="nd-hero__caption">No signup to look around. To post or install: create an account, add your site, paste your tag.</p>
          </div>
          <figure class="nd-hero__art">
            <div class="nd-hero__mock" aria-hidden="true">
              <div class="nd-hero__mock-bar">
                <i></i>
                <i></i>
                <i></i>
              </div>
              <div class="nd-hero__mock-body">
                <div class="nd-hero__mock-line nd-hero__mock-line--w80"></div>
                <div class="nd-hero__mock-line nd-hero__mock-line--w60"></div>
                <div class="nd-hero__mock-line nd-hero__mock-line--w45"></div>
                <div class="nd-hero__mock-card">
                  <div class="nd-hero__mock-line nd-hero__mock-line--w70"></div>
                  <div class="nd-hero__mock-line nd-hero__mock-line--w45"></div>
                </div>
                <span class="nd-hero__mock-export">Export</span>
                <span class="nd-hero__mock-pin"></span>
                <span class="nd-hero__mock-connector"></span>
                <div class="nd-hero__mock-rail">
                  <div class="nd-hero__mock-row"><i></i><span></span></div>
                  <div class="nd-hero__mock-row"><i></i><span></span></div>
                </div>
              </div>
            </div>
            <figcaption>
              The rail on this page is the real widget.
            </figcaption>
          </figure>
        </div>
      </section>

      <section class="nd-section" id="try-it">
        <div class="nd-section__inner">
          <p class="nd-section__label">Live demo</p>
          <h2>Try it on this page</h2>
          <p class="nd-section__intro">
            The comment rail beside this text is the product, running on this page.
            Here is what happens when you use it.
          </p>
          <ul class="nd-demo__grid">
            <li data-step="Pick">
              Pick anything on this page — a button, a chart, a sentence. The dashed ring is your target.
            </li>
            <li data-step="Post">
              Sign in to post — reading never needs an account.
            </li>
            <li data-step="Watch">
              On the rail. The site's team sees it the moment it lands — replies and resolutions arrive live.
            </li>
            <li data-step="Exit">
              Done pointing? Exit from the pill — the page goes back to normal.
            </li>
          </ul>
          <div class="nd-demo__stage">
            <div class="nd-demo__target" aria-hidden="true">
              <div class="nd-demo__line nd-demo__line--w70"></div>
              <div class="nd-demo__line nd-demo__line--w50"></div>
              <span class="nd-demo__ring"></span>
              <span class="nd-demo__pill"><i></i><span></span></span>
            </div>
          </div>
          <p class="nd-mcp__ctas">
            <button type="button" class="nd-btn nd-btn--primary" $click="try_it">
              Try it on this page
            </button>
          </p>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="how-it-works">
        <div class="nd-section__inner">
          <p class="nd-section__label">How it works</p>
          <h2>Three steps from "no feedback tool" to "feedback that closes itself".</h2>
          <p class="nd-section__intro">Everything below ships in the script today.</p>
          <ol class="nd-steps">
            <li class="nd-step">
              <h3>Drop in one script tag.</h3>
              <p>
                Paste two lines before &lt;/body&gt; — a loader and the
                <code>noizu-page-comments</code> element with your site slug. Pick the
                always-newest loader or pin an exact version that never changes.
              </p>
            </li>
            <li class="nd-step">
              <h3>Visitors pick the exact spot.</h3>
              <p>
                A click marks the element; a highlight marks the text. The thread anchors
                with fallback strategies — id, CSS, XPath, text quote, position — so it
                re-finds its spot after redesigns.
              </p>
            </li>
            <li class="nd-step">
              <h3>Triage where you already work.</h3>
              <p>
                The dashboard inbox for humans, a JSON REST API with live events for your
                stack, MCP for your agents. Same threads, same anchors, all three.
              </p>
            </li>
          </ol>
          <p class="nd-section__intro">
            Frames from a demo dashboard running the embed — the same loop, up close.
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
          <h2>Comment. Triage. Fix. Resolve.</h2>
          <ol class="nd-loop">
            <li class="nd-step">
              <h3>Comment on the page</h3>
              <p>A visitor selects the button, the sentence, the price row. The thread pins to that element — not to a screenshot of it.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Triage in the dashboard</h3>
              <p>Open the inbox: filter open and resolved, reply as the site team, resolve the noise, reopen what isn't. Updates arrive live.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Ticket in your tracker</h3>
              <p>Push a thread to Jira, Notion, ClickUp, Asana, or The Robot Plans — anchor and page context attached.</p>
              <span class="nd-chip nd-chip--planned">Planned</span>
            </li>
            <li class="nd-step">
              <h3>Agents investigate and patch</h3>
              <p>Connect Claude Code or any MCP client: it lists open threads, pulls the anchor, reproduces, patches your repo, replies on the thread.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
            <li class="nd-step">
              <h3>Resolve back on the page</h3>
              <p>The thread closes where it started, and anyone on the page sees it settled.</p>
              <span class="nd-chip nd-chip--live">Shipped</span>
            </li>
          </ol>
          <p class="nd-footnote">
            Steps 1, 2, 4 and 5 work today (step 4 over MCP). Step 3 is planned — the
            REST API already carries everything it needs.
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
                the thread re-finds its element when the DOM shifts. Deep links reopen
                the exact spot.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">rail + ring</span>
              <h3>Rail and ring</h3>
              <p>
                The rail floats beside the element and follows scroll. Open a comment
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
                Crop the page and draw boxes, arrows, freehand, text, and blur. Attach
                files to any comment; failed uploads retry on their own.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">live</span>
              <h3>Live updates</h3>
              <p>New comments, replies, and resolutions arrive over a websocket — no refresh.</p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">rules</span>
              <h3>Rules, roles, sign-in</h3>
              <p>
                Per-site rules: anonymous opt-in, guest names, who can read. GitHub
                sign-in for owners; visitors sign in through your identity provider —
                or your site vouches for them, no popup at all.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section" id="add-to-your-site">
        <div class="nd-section__inner">
          <p class="nd-section__label">Add to your site</p>
          <h2>Add your site, get your tag</h2>
          <ol class="nd-embedsteps">
            <li>Create an account — sign in with GitHub.</li>
            <li>Add your site's domain to your account.</li>
            <li>Copy your script tag into your pages.</li>
          </ol>
          <p class="nd-section__intro">
            Your tag is two lines — the loader and the element — pasted before
            &lt;/body&gt;. The loader you get tracks the newest build; pin a version if
            you'd rather nothing moves until you say so.
          </p>
          <div class="nd-snippet">
            <pre class="nd-snippet__code" tabindex="0"><code id="nd-snippet-code">&lt;<span class="nd-tok-tag">script</span> <span class="nd-tok-attr">type</span>=<span class="nd-tok-str">"module"</span> <span class="nd-tok-attr">src</span>=<span class="nd-tok-str">"{@snippet_src}"</span>&gt;&lt;/<span class="nd-tok-tag">script</span>&gt;
    &lt;<span class="nd-tok-tag">noizu-page-comments</span> <span class="nd-tok-attr">site</span>=<span class="nd-tok-str">"your-site"</span> <span class="nd-tok-attr">api-base</span>=<span class="nd-tok-str">"{@snippet_api}"</span>&gt;&lt;/<span class="nd-tok-tag">noizu-page-comments</span>&gt;</code></pre>
            <div class="nd-snippet__aside">
              <button type="button" class="nd-btn nd-btn--secondary" $click="copy_snippet">
                {%if @copied}Copied ✓{%else}Copy code{/if}
              </button>
              <p class="nd-snippet__note">Bound to the domain you registered — it won't fire anywhere else.</p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="agents">
        <div class="nd-section__inner">
          <p class="nd-section__label">For agents</p>
          <h2>Your agents read the feedback too.</h2>
          <div class="nd-agents">
            <div class="nd-agents__copy">
              <p>
                annotate ships a remote MCP server over Streamable HTTP. Connect Claude
                Code, Claude Desktop or claude.ai, Cursor, VS Code, or Codex. An agent
                signs in as you — OAuth in your browser, no API keys — and works your
                sites' threads: query what's open, investigate the anchored element,
                patch, reply, resolve.
              </p>
              <h3 class="nd-mcp__title">The agent loop</h3>
              <ol class="nd-mcp__steps">
                <li>Query open issues — <code>list_threads</code></li>
                <li>Pull one with its anchor, page context, attachments — <code>get_thread</code></li>
                <li>Triage: reproduce what the visitor saw, find the element in your repo — the anchor names the id, CSS, XPath, and text quote</li>
                <li>Patch</li>
                <li>Reply as the site team — <code>reply_to_thread</code></li>
                <li>Resolve — <code>resolve_thread</code></li>
              </ol>
              <p class="nd-mcp__note">
                Also exposed: <code>list_sites</code>, <code>get_site_config</code>,
                <code>reopen_thread</code>, <code>delete_comment</code>, resources for
                sites and threads, and two prompts — <code>triage_open_threads</code> and
                <code>investigate_thread</code>. Full reference:
                <a href="/mcp-server">/mcp-server</a>.
              </p>
              <p class="nd-mcp__note">
                Prefer plain HTTP? The same threads, anchors, and live events are on the
                REST API — reads are public unless you restrict them.
              </p>
              <p class="nd-mcp__ctas">
                <a class="nd-btn nd-btn--secondary" href="/dashboard/agents">Connect an agent</a>
                <a class="nd-btn nd-btn--ghost" href="/mcp-server">Full MCP reference</a>
              </p>
            </div>
            <div>
              <h3 class="nd-mcp__title">Connect a client</h3>
              <div class="nd-mcp__snippet">
                <label for="nd-mcp-claude-code">Claude Code</label>
                <pre class="nd-snippet__code" tabindex="0"><code id="nd-mcp-claude-code">claude mcp add --transport http annotate {@mcp_url}</code></pre>
                <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-mcp-claude-code"}}>Copy</button>
              </div>
              <p class="nd-mcp__caption">
                Then <code>/mcp</code> → annotate → Authenticate. The client opens a
                browser; you pick what it may do.
              </p>
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
              <h3 class="nd-mcp__title">How the keys stay yours</h3>
              <ul class="nd-mcp__trust">
                <li>OAuth 2.1 with PKCE. Sign-in as an annotate dashboard user — GitHub or Google. Nothing to paste.</li>
                <li><code>comments:read</code> is granted by default. Replying and resolving (<code>comments:write</code>) and deleting (<code>comments:moderate</code>) are opt-in on the consent screen.</li>
                <li>Revoke any client at <a href="/dashboard/agents">/dashboard/agents</a> — its next request is refused.</li>
                <li>Every write and every refusal is audited. Reads are never logged.</li>
                <li>Comment text is visitor-written: it arrives under an <code>untrusted</code> key, and the server tells the agent to treat it as data — never as instructions.</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section" id="waitlist">
        <div class="nd-section__inner">
          <p class="nd-section__label">Roadmap</p>
          <h2>Where the work goes next.</h2>
          <ul class="nd-roster">
            <li>
              <h3>REST API and realtime</h3>
              <p>Everything above is reachable through it today.</p>
              <span class="nd-chip nd-chip--live">Available today</span>
            </li>
            <li>
              <h3>The Robot Plans</h3>
              <p>Our sibling planning tool.</p>
              <span class="nd-chip nd-chip--planned">Soon</span>
              <a href="#waitlist" data-waitlist-interest="robot-plans">Tell me when it ships</a>
            </li>
            <li>
              <h3>Jira</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Soon</span>
              <a href="#waitlist" data-waitlist-interest="jira">Tell me when it ships</a>
            </li>
            <li>
              <h3>Notion</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Soon</span>
              <a href="#waitlist" data-waitlist-interest="notion">Tell me when it ships</a>
            </li>
            <li>
              <h3>ClickUp</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Soon</span>
              <a href="#waitlist" data-waitlist-interest="clickup">Tell me when it ships</a>
            </li>
            <li>
              <h3>Asana</h3>
              <p>Ticket from a thread, anchor attached.</p>
              <span class="nd-chip nd-chip--planned">Soon</span>
              <a href="#waitlist" data-waitlist-interest="asana">Tell me when it ships</a>
            </li>
          </ul>
          <p class="nd-footnote">
            Ticket creation lands tracker by tracker. None are live yet; the REST API is the
            honest today-answer. Product names are text only: Jira, Notion, ClickUp, and Asana
            belong to their owners, and annotate isn't affiliated with them.
          </p>
          <h3 class="nd-mcp__title">Get one email when these ship.</h3>
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

      <section class="nd-section nd-section--canvas" id="faq">
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
              <summary>Who can read the comments?</summary>
              <p>
                By default, anyone on the page can read and only signed-in visitors can
                post. Both are per-site switches.
              </p>
            </details>
            <details>
              <summary>Do my visitors need annotate accounts?</summary>
              <p>
                No. They sign in through an Authentik popup — or, if you enable it, your
                own site vouches for its logged-in users and they never see our sign-in.
                Guest names and anonymous posting are per-site options.
              </p>
            </details>
            <details>
              <summary>Can someone steal my key and use it on their site?</summary>
              <p>
                No. Keys are bound to the origins you register; requests from other
                domains are rejected.
              </p>
            </details>
            <details>
              <summary>What happens to my comments if I cancel?</summary>
              <p>
                They stay readable — your sites go read-only until you pick a plan.
                Nothing is deleted on downgrade, and export is yours on request.
              </p>
            </details>
            <details>
              <summary>Does it work with my stack?</summary>
              <p>
                If your page runs in a browser, yes. One script tag, no framework
                requirements, no build step.
              </p>
            </details>
            <details>
              <summary>Can an AI agent act on the feedback — safely?</summary>
              <p>
                Over MCP, yes: the agent signs in as you, read is granted by default and
                writing is opt-in, every action is audited, and visitor text arrives
                labeled <code>untrusted</code> so the agent treats it as data, never
                instructions. Revoke any client at <a href="/dashboard/agents">/dashboard/agents</a>.
              </p>
            </details>
            <details>
              <summary>Which trackers does it sync with — Jira, Notion, ClickUp?</summary>
              <p>
                None yet. Those integrations are planned; today the REST API covers
                programmatic export, and an agent over MCP can file the ticket on your
                side. Tick the boxes in the waitlist and you'll get one email per
                integration when it ships.
              </p>
            </details>
          </div>
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

    <section class="nd-section">
      <div class="nd-section__inner">
        <h2>Point at something.</h2>
        <p class="nd-section__intro">
          Install takes one snippet. The 14-day trial needs no card — and the comments
          you collect are yours to export or delete.
        </p>
        <div class="nd-final__ctas">
          <button type="button" class="nd-btn nd-btn--primary" $click="try_it">
            Try it on this page
          </button>
          <a class="nd-btn nd-btn--secondary" href="#add-to-your-site">Add it to your site</a>
          <a class="nd-final__quiet" href="/pricing">See pricing</a>
        </div>
        <div class="nd-final__privacy">
          <h3>Built to stay out of the way</h3>
          <ul class="nd-privacy">
            <li>Tokens are bound to your origins — a key only works on the domains you register.</li>
            <li>No third-party cookies. The widget stores only what keeps a visitor signed in.</li>
            <li>Comments are publicly readable by default — restrict reading per site if you'd rather.</li>
            <li>Your comment data is yours: delete it from the dashboard, or ask us for an export.</li>
          </ul>
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
