defmodule AnnotateWeb.Hologram.Pages.DashboardAgentsPage do
  @moduledoc """
  `/dashboard/agents` — connect AI agents / MCP clients to annotate, see
  which ones are connected (with the scopes each was granted), revoke any of
  them, and read the recent MCP activity log (`mcp_audit_events`).

  Connected-client names are chosen by the clients themselves (dynamic
  registration), so — like the inbox — list data never rides the
  server-rendered page state: `init/3` renders snippets only and queues
  `:load`; the lists arrive through the `:load_agents` command. Every
  command re-reads the session user and the invite gate.

  Revoking (`Annotate.MCP.Grants.revoke/2`) removes the consent, marks the
  client's access tokens revoked and revokes its refresh tokens: the
  client's next `/mcp` request is refused.
  """

  use Hologram.Page

  alias Annotate.Hologram.Auth
  alias Annotate.Hologram.DashboardAuth
  alias Annotate.MCP.Grants
  alias AnnotateWeb.Hologram.Components.DashboardShell
  alias AnnotateWeb.Hologram.Layouts.DashboardLayout
  alias AnnotateWeb.Hologram.Middleware.RequireAuth

  route "/dashboard/agents"
  layout DashboardLayout, page_title: "Agents — annotate dashboard"
  middleware RequireAuth

  def init(_params, component, server) do
    url = Annotate.MCP.Config.resource()

    component
    |> put_state(
      user: DashboardAuth.shell_user(Auth.current_user(server)),
      url: url,
      snippets: snippets(url),
      clients: [],
      activity: [],
      loading: true,
      error: nil,
      flash: nil
    )
    |> put_action(:load)
  end

  def template do
    ~HOLO"""
    <DashboardShell user={@user} sites={[]} title="Agents"
      subtitle="Let Claude, Cursor-style editors and other MCP clients read and triage your sites' comments — as you, with your role on each site.">
      {%if @flash}<p class="dsh-flash" role="status">{@flash}</p>{/if}
      {%if @error}<p class="dsh-error" role="alert" data-cy="dsh-agents-error">{@error}</p>{/if}

      <section class="dsh-panel" data-cy="dsh-agents-connect">
        <h2 class="dsh-panel__title">Connect an agent</h2>
        <div class="dsh-panel__body">
          <p>MCP server URL: <code id="mcp-url" data-cy="dsh-agents-url">{@url}</code>
            <button type="button" class="dsh-btn dsh-btn--ghost dsh-btn--sm" $click={action: :copy, params: %{id: "mcp-url"}}>Copy</button></p>
          <p class="dsh-hint">Your client opens a browser to sign in here (GitHub or Google) and asks what to allow. Reading is always granted; replying/resolving and deleting are opt-in on that screen. Nothing to paste — no API keys.</p>
          {%for s <- @snippets}
            <div class="dsh-field" data-cy="dsh-agents-snippet">
              <label for={"snip-" <> s.id}>{s.label}</label>
              <pre class="dsh-code" id={"snip-" <> s.id}>{s.code}</pre>
              <p class="dsh-hint">{s.hint}
                <button type="button" class="dsh-btn dsh-btn--ghost dsh-btn--sm" $click={action: :copy, params: %{id: "snip-" <> s.id}}>Copy</button></p>
            </div>
          {/for}
          <p class="dsh-hint">Comment text is written by your sites' visitors. annotate labels it <code>untrusted</code> for agents, but review what an agent proposes before letting it reply, resolve or delete.</p>
        </div>
      </section>

      <section class="dsh-panel" data-cy="dsh-agents-clients">
        <h2 class="dsh-panel__title">Connected clients</h2>
        <div class="dsh-panel__body">
          {%if @loading && @clients == []}<p class="dsh-empty" role="status">Loading…</p>{/if}
          {%if !@loading && @clients == []}<p class="dsh-empty" data-cy="dsh-agents-none">No agents connected yet.</p>{/if}
          {%if @clients != []}
            <table class="dsh-table">
              <thead><tr><th>Client</th><th>Allowed</th><th>Connected</th><th>Last token</th><th></th></tr></thead>
              <tbody>
                {%for c <- @clients}
                  <tr data-cy="dsh-agents-client">
                    <td><strong>{c.name}</strong> <span class="dsh-chip dsh-chip--muted">{c.kind}</span><br /><span class="dsh-hint">Name chosen by the client.</span></td>
                    <td>{%for sc <- c.scopes}<span class="dsh-chip" data-cy="dsh-agents-scope">{sc}</span> {/for}</td>
                    <td>{c.granted_at}</td>
                    <td>{c.last_token_at}</td>
                    <td><button type="button" class="dsh-btn dsh-btn--danger dsh-btn--sm" $click={action: :revoke, params: %{client_id: c.client_id}} data-cy="dsh-agents-revoke">Revoke</button></td>
                  </tr>
                {/for}
              </tbody>
            </table>
          {/if}
        </div>
      </section>

      <section class="dsh-panel" data-cy="dsh-agents-activity">
        <h2 class="dsh-panel__title">Recent agent activity</h2>
        <div class="dsh-panel__body">
          {%if @activity == []}
            <p class="dsh-empty">No writes or refusals yet. (Reads are not logged.)</p>
          {%else}
            <table class="dsh-table">
              <thead><tr><th>When</th><th>Tool</th><th>Site</th><th>Outcome</th></tr></thead>
              <tbody>
                {%for a <- @activity}
                  <tr data-cy="dsh-agents-event">
                    <td>{a.at}</td><td><code>{a.tool}</code></td><td>{a.site}</td><td><span class="dsh-chip">{a.outcome}</span> {a.reason}</td>
                  </tr>
                {/for}
              </tbody>
            </table>
          {/if}
        </div>
      </section>
    </DashboardShell>
    """
  end

  # ── actions ───────────────────────────────────────────────────

  def action(:load, _params, c), do: put_command(c, :load_agents, %{})

  def action(:loaded, params, c),
    do:
      put_state(c, loading: false, error: nil, clients: params.clients, activity: params.activity)

  def action(:revoke, params, c),
    do:
      c |> put_state(flash: nil, error: nil) |> put_command(:revoke, client_id: params.client_id)

  def action(:revoked, params, c),
    do:
      put_state(c,
        clients: params.clients,
        activity: params.activity,
        flash: "Revoked. That client's next request is refused; reconnecting needs a new sign-in."
      )

  def action(:copy, params, c) do
    # Runs client-side (transpiled): ids are this template's fixed literals.
    Hologram.JS.exec(
      "var e=document.getElementById('" <>
        params.id <>
        "');if(e){navigator.clipboard.writeText(e.textContent).catch(function(){});}"
    )

    put_state(c, flash: "Copied.")
  end

  def action(:failed, params, c), do: put_state(c, loading: false, error: params.error)

  # ── commands (re-authorized every call) ──────────────────────

  def command(:load_agents, _params, server) do
    case allowed_user(server) do
      {:ok, user} -> put_action(server, :loaded, lists(user.id))
      :error -> put_action(server, :failed, error: DashboardAuth.message(:unauthenticated))
    end
  end

  def command(:revoke, params, server) do
    with {:ok, user} <- allowed_user(server),
         client_id when is_binary(client_id) and client_id != "" <- to_string(params.client_id),
         :ok <- Grants.revoke(user.id, client_id) do
      put_action(server, :revoked, lists(user.id))
    else
      _ -> put_action(server, :failed, error: "Could not revoke that client.")
    end
  end

  # ── helpers ───────────────────────────────────────────────────

  defp allowed_user(server) do
    case Auth.current_user(server) do
      %{id: id} = user when is_binary(id) ->
        if Annotate.MCP.Authz.user_allowed?(Annotate.Repo.get(Annotate.Schema.Users.User, id)),
          do: {:ok, user},
          else: :error

      _ ->
        :error
    end
  end

  defp lists(user_id) do
    [
      clients:
        Enum.map(Grants.list(user_id), fn g ->
          %{
            client_id: g.client_id,
            name: g.untrusted_client_name || g.client_id,
            kind: kind_label(g.kind),
            scopes: g.scopes,
            granted_at: fmt(g.granted_at),
            last_token_at: fmt(g.last_token_at)
          }
        end),
      activity:
        Enum.map(Annotate.MCP.Authz.recent_audit(user_id, 25), fn a ->
          %{
            at: fmt(a.at),
            tool: a.tool,
            site: a.site_slug || "—",
            outcome: a.outcome,
            reason: a.reason || ""
          }
        end)
    ]
  end

  defp kind_label("cimd"), do: "metadata URL"
  defp kind_label("preconfigured"), do: "preconfigured"
  defp kind_label(_), do: "self-registered"

  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp fmt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp fmt(_), do: "—"

  @doc false
  def snippets(url) do
    [
      %{
        id: "claude-code",
        label: "Claude Code",
        code: "claude mcp add --transport http annotate " <> url,
        hint: "Then run /mcp in Claude Code and choose annotate → Authenticate."
      },
      %{
        id: "claude-ai",
        label: "Claude.ai / Claude Desktop",
        code: "Settings → Connectors → Add custom connector\nName: annotate\nURL:  " <> url,
        hint: "Connect, then sign in and choose what to allow."
      },
      %{
        id: "vscode",
        label: "VS Code (.vscode/mcp.json)",
        code: Jason.encode!(%{servers: %{annotate: %{type: "http", url: url}}}, pretty: true),
        hint: "Start the server from the MCP view; VS Code opens the sign-in."
      },
      %{
        id: "codex",
        label: "OpenAI Codex CLI",
        code: "codex mcp add annotate --url " <> url <> "\ncodex mcp login annotate",
        hint: "Remote MCP OAuth needs a recent Codex CLI."
      },
      %{
        id: "cursor",
        label: "Cursor (~/.cursor/mcp.json)",
        code: Jason.encode!(%{mcpServers: %{annotate: %{url: url}}}, pretty: true),
        hint:
          "Cursor opens the sign-in from Settings → MCP; it returns to Cursor when you approve."
      }
    ]
  end
end
