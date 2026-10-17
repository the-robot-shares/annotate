defmodule AnnotateWeb.Hologram.Pages.McpServerPage do
  @moduledoc """
  `/mcp-server` — public reference for annotate's remote MCP server. Static
  copy grounded in `docs/MCP.md`; the only dynamic value is the server URL,
  which comes from `AnnotateWeb.SEO.origin/0`. Snippet copy reads the rendered
  text from the DOM (ids are this template's fixed literals) so multi-line
  code never travels through Hologram page state.
  """

  use Hologram.Page

  alias AnnotateWeb.Hologram.Components.GithubAuth

  alias AnnotateWeb.Hologram.Components.SiteFooter
  alias AnnotateWeb.Hologram.Layouts.LandingLayout

  route "/mcp-server"

  layout LandingLayout,
    page_title: "MCP server — annotate",
    description:
      "Connect Claude Code, Claude Desktop, Cursor, VS Code or Codex to annotate over MCP: tools, scopes, sign-in and connect snippets.",
    path: "/mcp-server"

  def init(_params, component, _server) do
    put_state(component, :mcp_url, AnnotateWeb.SEO.origin() <> "/mcp")
  end

  def template do
    ~HOLO"""
    <header class="nd-nav">
      <div class="nd-nav__inner">
        <a class="nd-nav__brand" href="/"><span class="nd-nav__dot" aria-hidden="true"></span>annotate</a>
        <nav class="nd-nav__links" aria-label="Sections">
          <a class="nd-nav__link" href="/#how-it-works">How it works</a>
          <a class="nd-nav__link" href="/#features">Features</a>
          <a class="nd-nav__link" href="/#agents">For agents</a>
          <a class="nd-nav__link" href="/#faq">FAQ</a>
        </nav>
        <GithubAuth cid="mcp_server_github_auth" variant="nd" />
      </div>
    </header>

    <main id="main">
      <section class="nd-section nd-doc">
        <div class="nd-section__inner">
          <p class="nd-section__label">MCP server</p>
          <h1>Give your agents the feedback loop.</h1>
          <p class="nd-section__intro">
            annotate runs a remote MCP server over Streamable HTTP. Your AI agents —
            Claude Code, Claude Desktop or claude.ai, Cursor, VS Code, Codex — sign in
            as you and work your sites' comment threads: query open issues, triage,
            investigate the anchored element in your repo, patch, reply, resolve.
          </p>

          <div class="nd-doc__panel">
            <h2>Endpoint and sign-in</h2>
            <table class="nd-mcp__tools">
              <tbody>
                <tr><th scope="row">Endpoint</th><td><code>{@mcp_url}</code> (Streamable HTTP)</td></tr>
                <tr><th scope="row">Sign-in</th><td>OAuth 2.1 in your browser — GitHub or Google, as an annotate dashboard user. Discovery at <code>/.well-known/oauth-authorization-server</code>.</td></tr>
                <tr><th scope="row">Scopes</th><td><code>comments:read</code> by default; <code>comments:write</code> (reply, resolve, reopen) and <code>comments:moderate</code> (delete) are opt-in on the consent screen.</td></tr>
                <tr><th scope="row">Access</th><td>Agents act on the sites you're a member of, with your role. Revoke any client at <a href="/dashboard/agents">/dashboard/agents</a> — its next request is refused.</td></tr>
                <tr><th scope="row">Audit</th><td>Every write and every refusal is recorded (user, client, site, tool) — never comment bodies. Reads are not logged.</td></tr>
              </tbody>
            </table>
          </div>

          <div class="nd-doc__panel">
            <h2>Connect a client</h2>
            <div class="nd-mcp__snippet">
              <label for="nd-doc-claude-code">Claude Code</label>
              <pre class="nd-snippet__code" tabindex="0"><code id="nd-doc-claude-code">claude mcp add --transport http annotate {@mcp_url}</code></pre>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-doc-claude-code"}}>Copy</button>
            </div>
            <div class="nd-mcp__snippet">
              <label for="nd-doc-claude-ai">Claude.ai / Claude Desktop</label>
              <pre class="nd-snippet__code" tabindex="0"><code id="nd-doc-claude-ai">Settings → Connectors → Add custom connector
    Name: annotate
    URL:  {@mcp_url}</code></pre>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-doc-claude-ai"}}>Copy</button>
            </div>
            <div class="nd-mcp__snippet">
              <label for="nd-doc-cursor">Cursor (~/.cursor/mcp.json)</label>
              <pre class="nd-snippet__code" tabindex="0"><code id="nd-doc-cursor">\{"mcpServers": \{"annotate": \{"url": "{@mcp_url}"}}}</code></pre>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-doc-cursor"}}>Copy</button>
            </div>
            <div class="nd-mcp__snippet">
              <label for="nd-doc-vscode">VS Code (.vscode/mcp.json)</label>
              <pre class="nd-snippet__code" tabindex="0"><code id="nd-doc-vscode">\{"servers": \{"annotate": \{"type": "http", "url": "{@mcp_url}"}}}</code></pre>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-doc-vscode"}}>Copy</button>
            </div>
            <div class="nd-mcp__snippet">
              <label for="nd-doc-codex">OpenAI Codex CLI</label>
              <pre class="nd-snippet__code" tabindex="0"><code id="nd-doc-codex">codex mcp add annotate --url {@mcp_url}
    codex mcp login annotate</code></pre>
              <button type="button" class="nd-btn nd-btn--ghost nd-btn--sm" $click={action: :copy_mcp, params: %{id: "nd-doc-codex"}}>Copy</button>
            </div>
            <p class="nd-mcp__note">
              The client opens a browser to sign in and asks what to allow. Reading is
              always granted; replying, resolving and deleting are opt-in. Nothing to
              paste — no API keys.
            </p>
          </div>

          <div class="nd-doc__panel">
            <h2>Tools</h2>
            <table class="nd-mcp__tools">
              <thead>
                <tr><th scope="col">Tool</th><th scope="col">Does</th><th scope="col">Scope</th></tr>
              </thead>
              <tbody>
                <tr><td><code>list_sites</code></td><td>Your member sites, your role on each, open/resolved counts.</td><td>read</td></tr>
                <tr><td><code>get_site_config</code></td><td>A site's allowed origins and read/comment policy; never keys.</td><td>read</td></tr>
                <tr><td><code>list_threads</code></td><td>Filter by status, page path, origin, date, text, author; paginated.</td><td>read</td></tr>
                <tr><td><code>get_thread</code></td><td>Live comments, the anchor, page context; attachment links valid ~5 minutes.</td><td>read</td></tr>
                <tr><td><code>reply_to_thread</code></td><td>Post as the site team; visitors see it live.</td><td>write</td></tr>
                <tr><td><code>resolve_thread</code> / <code>reopen_thread</code></td><td>Close a thread, or open it again.</td><td>write</td></tr>
                <tr><td><code>delete_comment</code></td><td>Soft-delete a comment — your team's replies, or anyone's if you're an admin/owner.</td><td>moderate</td></tr>
              </tbody>
            </table>
            <p class="nd-mcp__note">
              Also exposed: resources (<code>annotate://sites</code>, per-site thread lists,
              single threads) and two prompts — <code>triage_open_threads(site)</code> and
              <code>investigate_thread(thread_id)</code>. A tool call outside the granted
              scope is refused with <code>insufficient_scope</code>; send the user back
              through consent to grant more.
            </p>
          </div>

          <div class="nd-doc__panel">
            <h2>Untrusted content, by construction</h2>
            <p class="nd-section__intro">
              Comment bodies, author names, page titles, anchors and URLs are written by
              your visitors. The server returns them only under <code>untrusted</code> keys
              and tells the agent to treat them as data — never as instructions. Nothing
              auto-resolves: a human or an agent you explicitly asked does the triage.
            </p>
          </div>

          <p class="nd-mcp__ctas nd-mcp__ctas--doc">
            <a class="nd-btn nd-btn--primary" href="/dashboard/agents">Connect an agent</a>
            <a class="nd-btn nd-btn--ghost" href="/">Back to the overview</a>
          </p>
        </div>
      </section>
    </main>

    <SiteFooter />
    """
  end

  def action(:copy_mcp, params, component) do
    Hologram.JS.exec(
      "var e=document.getElementById('" <>
        params.id <>
        "');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    component
  end
end
