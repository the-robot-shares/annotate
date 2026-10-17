defmodule AnnotateWeb.MCP.Consent do
  @moduledoc """
  annotate's MCP consent screen (`consent: [renderer: …]`).

  Shown for every dynamically-registered / CIMD client before any code is
  issued (confused-deputy guard). It names the signed-in account, the
  client, where the client will be sent back to, and each requested scope in
  plain words. **Everything a client chose (name, client_id, redirect URIs,
  scope strings) is HTML-escaped** — a self-registered client controls them
  and they render on annotate's own origin.
  """

  import Plug.Conn

  @scope_text %{
    "comments:read" => "Read your sites' comment threads (bodies, authors, page URLs)",
    "comments:write" => "Reply to threads as your site team, and resolve or reopen them",
    "comments:moderate" =>
      "Delete comments (your own team replies; anyone's on sites where you are admin or owner)"
  }

  def render(conn, assigns) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-frame-options", "DENY")
    # No `form-action`: Chrome applies it to the post-approve 302 to the
    # client's redirect_uri (claude.ai, loopback), which would break the flow.
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'"
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> send_resp(200, html(assigns))
  end

  @doc false
  def html(assigns) do
    client = assigns.client
    name = esc(client.client_name || client.client_id)
    email = account_email(assigns[:subject])

    # Checkboxes: read is required (always granted); write/moderate are
    # opt-in and unchecked. AnnotateWeb.MCP.OAuthPlug.narrow_consent/2 turns
    # the ticked set into the grant.
    scopes =
      Enum.map_join(assigns.scope, "", fn scope ->
        text = Map.get(@scope_text, scope, "Unrecognized permission")
        id = "scope-" <> String.replace(scope, ~r/[^a-z]/, "-")

        if scope == Annotate.MCP.Scopes.base() do
          ~s|<li><label><input type="checkbox" checked disabled> <strong>#{esc(text)}</strong> <code>#{esc(scope)}</code> <span class="muted">(required)</span></label></li>|
        else
          ~s|<li><label for="#{id}"><input type="checkbox" id="#{id}" name="grant_scope[]" value="#{esc(scope)}"> <strong>#{esc(text)}</strong> <code>#{esc(scope)}</code></label></li>|
        end
      end)

    hosts =
      client.redirect_uris
      |> List.wrap()
      |> Enum.map(&redirect_label/1)
      |> Enum.uniq()
      |> Enum.map_join(", ", &"<code>#{esc(&1)}</code>")

    kind_note =
      case client.client_id_kind do
        :registered ->
          ~s(<p class="warn">This app registered itself a moment ago. Approve it only if you just started connecting an AI agent or MCP client.</p>)

        :cimd ->
          ~s(<p class="warn">Identified by <code>#{esc(client.client_id)}</code>. Approve it only if you recognize that address.</p>)

        _ ->
          ""
      end

    """
    <!DOCTYPE html>
    <html lang="en"><head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="robots" content="noindex">
    <title>Connect #{name} to annotate</title>
    <style>
      :root { color-scheme: dark; }
      body { font: 16px/1.55 system-ui, -apple-system, sans-serif; background: #0f1115; color: #e8e6e1; max-width: 34rem; margin: 3.5rem auto; padding: 0 1.25rem; }
      h1 { font-size: 1.35rem; margin: 0 0 1rem; }
      ul { padding-left: 1.2rem; } li { margin: .35rem 0; }
      ul.scopes { list-style: none; padding-left: 0; } ul.scopes li { margin: .6rem 0; }
      input[type=checkbox] { width: 1.05rem; height: 1.05rem; vertical-align: -2px; margin-right: .35rem; }
      code { background: rgba(255,255,255,.08); padding: .08em .35em; border-radius: 4px; font-size: .88em; word-break: break-all; }
      .muted { color: #a8a39a; font-size: .92rem; }
      .warn { background: rgba(232,170,40,.12); border: 1px solid rgba(232,170,40,.35); padding: .75rem .9rem; border-radius: 8px; }
      .actions { display: flex; gap: .75rem; margin-top: 1.75rem; }
      button { font: inherit; padding: .6rem 1.25rem; border-radius: 8px; border: 1px solid transparent; cursor: pointer; }
      .approve { background: #e8e6e1; color: #0f1115; }
      .deny { background: transparent; color: inherit; border-color: rgba(255,255,255,.35); }
    </style>
    </head><body>
    <h1><code>#{name}</code> wants to use annotate as you</h1>
    #{if email, do: ~s(<p class="muted">Signed in as <strong>#{esc(email)}</strong>.</p>), else: ""}
    #{kind_note}
    <form method="post" action="#{esc(assigns.action)}">
    <p>Choose what it may do (you can grant more later by reconnecting):</p>
    <ul class="scopes">#{scopes}</ul>
    <p class="muted">Access covers every site you are a member of, with your current role on each (checked on every request). It returns to #{hosts}. Revoke it any time at <strong>Dashboard → Agents</strong>.</p>
    <p class="muted">Comment text on your sites is written by visitors. An agent should treat it as data, not instructions.</p>
      <input type="hidden" name="login_state" value="#{esc(assigns.login_state)}">
      <input type="hidden" name="csrf_token" value="#{esc(assigns.csrf_token)}">
      <div class="actions">
        <button class="approve" type="submit" name="decision" value="approve">Approve</button>
        <button class="deny" type="submit" name="decision" value="deny">Deny</button>
      </div>
    </form>
    </body></html>
    """
  end

  defp redirect_label(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{host: host} when host in ["localhost", "127.0.0.1", "::1", "[::1]"] ->
        "this computer (#{host})"

      %URI{host: host} when is_binary(host) ->
        host

      _ ->
        uri
    end
  end

  defp redirect_label(other), do: to_string(other)

  defp account_email(subject) when is_binary(subject) do
    with {:ok, id} <- Ecto.UUID.cast(subject),
         %{email: email} <- Annotate.Repo.get(Annotate.Schema.Users.User, id) do
      email
    else
      _ -> nil
    end
  end

  defp account_email(_), do: nil

  defp esc(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
