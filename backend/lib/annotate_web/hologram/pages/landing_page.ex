defmodule AnnotateWeb.Hologram.Pages.LandingPage do
  @moduledoc """
  Marketing landing page (Night Desk direction) — owns `route "/"`.

  Dogfoods the product: the page runs the live page-comments widget (embedded
  by LandingLayout), and the hero CTA drives the real widget into pick mode.
  Copy: `design/landing/COPY.md`. IA: `design/landing/IA.md`. Images are
  AI-generated and carry a disclosure caption.
  """

  use Hologram.Page

  alias AnnotateWeb.Hologram.Components.GithubAuth

  alias AnnotateWeb.Hologram.Layouts.LandingLayout

  route "/"
  layout LandingLayout, page_title: "annotate — Feedback that points at the thing"

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
          <a class="nd-nav__link" href="#how-it-works">How it works</a>
          <a class="nd-nav__link" href="#features">Features</a>
          <a class="nd-nav__link" href="#privacy">Privacy</a>
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
              annotate adds a comment rail to any webpage. Visitors select an element
              or some text, and the thread attaches to exactly that spot.
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
              <source
                type="image/webp"
                srcset="/images/landing/hero-1600.webp"
              />
              <img
                src="/images/landing/hero-1600.png"
                alt="Mockup of a dark pricing page where a glowing ember ring marks the words per seat, connected to a comment card asking whether the pricing wording is right"
                width="1600"
                height="914"
                fetchpriority="high"
              />
            </picture>
            <figcaption>
              Product mockup (AI-generated). The rail on this page is the real widget.
            </figcaption>
          </figure>
        </div>
      </section>

      <section class="nd-section" id="how-it-works">
        <div class="nd-section__inner">
          <p class="nd-section__label">How it works</p>
          <h2>One tag. Two clicks. A conversation.</h2>
          <ol class="nd-steps">
            <li class="nd-step">
              <h3>Drop in the script</h3>
              <p>One tag in your HTML with your site's service key.</p>
            </li>
            <li class="nd-step">
              <h3>Pick any element</h3>
              <p>Visitors click a component or highlight text.</p>
            </li>
            <li class="nd-step">
              <h3>Discuss in the rail</h3>
              <p>Threads open beside the element; clicking a comment rings the spot it refers to.</p>
            </li>
          </ol>
        </div>
      </section>

      <section class="nd-section nd-section--canvas" id="features">
        <div class="nd-section__inner">
          <p class="nd-section__label">Features</p>
          <h2>What ships in the script</h2>
          <div class="nd-bento">
            <div class="nd-tile nd-tile--wide">
              <span class="nd-tile__glyph" aria-hidden="true">rail</span>
              <h3>Anchored rail</h3>
              <p>
                The comment rail floats beside the element on any layout; it follows
                scroll and never covers what you're discussing. Docks right on
                desktop, bottom sheet on mobile.
              </p>
            </div>
            <div class="nd-tile nd-tile--wide">
              <span class="nd-tile__glyph" aria-hidden="true">ring</span>
              <h3>Ring highlight</h3>
              <p>
                Open a comment and the element it belongs to rings on the page, so
                review starts at the right spot.
              </p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">threads</span>
              <h3>Threads</h3>
              <p>Replies nest under each comment; resolve a thread when it's settled.</p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">files</span>
              <h3>Attachments</h3>
              <p>Add files and images to any comment.</p>
            </div>
            <div class="nd-tile nd-tile--third">
              <span class="nd-tile__glyph" aria-hidden="true">live</span>
              <h3>Live updates</h3>
              <p>New comments and replies appear without a refresh.</p>
            </div>
            <div class="nd-tile nd-tile--wide">
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
                <figcaption class="nd-tile__caption">
                  Illustration: AI-generated.
                </figcaption>
              </figure>
              <h3>Screenshot + annotate</h3>
              <p>
                Crop the page, then draw boxes, arrows, and freehand, add text, or
                blur anything sensitive.
              </p>
            </div>
            <div class="nd-tile nd-tile--wide">
              <span class="nd-tile__glyph" aria-hidden="true">rules</span>
              <h3>Per-site rules and SSO</h3>
              <p>
                Decide who can post per site: sign-in through your Authentik, or your
                own site vouches for its users. Reading is public by default.
              </p>
            </div>
          </div>
        </div>
      </section>

      <section class="nd-section" id="add-to-your-site">
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

      <section class="nd-section nd-section--canvas" id="privacy">
        <div class="nd-section__inner">
          <p class="nd-section__label">Privacy &amp; security</p>
          <h2>Built to stay out of the way</h2>
          <ul class="nd-privacy">
            <li>Tokens are bound to your origin — a key only works on the domains you register.</li>
            <li>No third-party cookies; the widget stores only what it needs to keep you signed in.</li>
            <li>Comments are publicly readable by default; you can restrict reading per site.</li>
            <li>Your comment data is yours — export or delete it at any time.</li>
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
          </div>
        </div>
      </section>
    </main>

    <footer class="nd-footer">
      <div class="nd-footer__inner">
        <span class="nd-footer__brand">annotate</span>
        <nav class="nd-footer__links" aria-label="Footer">
          <a href="https://therobotlives.com">The Robot Lives</a>
          <a href="https://tobor.dev">tobor-kit docs</a>
          <a href="https://status.noizu.com">Status</a>
          <a href="/sitemap">Sitemap</a>
        </nav>
        <p class="nd-footer__disclosure">
          Hero and feature illustrations on this page are AI-generated. © 2026
          The Robot Lives.
        </p>
      </div>
    </footer>

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
              "https://cdn.derobot.is/tobor-kit/sha-5f07f4c948af8d1b578e10ac4db02d1bec10879b/components/page-comments/page-comments.js"
            )
        }

      _ ->
        %{
          api_base: "https://annotate-srv.therobotlives.com",
          widget_src:
            "https://cdn.derobot.is/tobor-kit/sha-5f07f4c948af8d1b578e10ac4db02d1bec10879b/components/page-comments/page-comments.js"
        }
    end
  end
end
