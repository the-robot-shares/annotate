defmodule Annotate.MCP.Config do
  @moduledoc """
  Runtime configuration for annotate's MCP server and its OAuth 2.1
  authorization server (noizu_mcp `Noizu.MCP.Auth.Server`).

  Everything here is read from app env **inside the functions**, never in a
  router `forward` (compile time): an issuer or resource baked at build time
  that disagrees with the protected-resource metadata makes every MCP client
  refuse to authenticate.

  * issuer   — `config :annotate, :mcp, issuer:` (origin, no path)
  * resource — `issuer <> "/mcp"` (the single mount; tokens are `aud`-bound to it)
  * signing  — HS256 with `ANNOTATE_MCP_SIGNING_SECRET`, MCP-only (never the
    embed `ANNOTATE_JWT_SECRET`, T-05)

  Scopes: `comments:read`, `comments:write` (reply, resolve, reopen) and
  `comments:moderate` (delete). The 401 challenge and the default scope are
  all three, so a standard client asks for them and the user approves them on
  the consent screen; a client may request less. Tools re-check the granted
  scope on every call (`Annotate.MCP.Authz`).
  """

  @scopes ["comments:read", "comments:write", "comments:moderate"]
  @path "/mcp"

  # Redirect hosts a dynamically-registered (or CIMD) client may use, besides
  # loopback (always allowed, port-agnostic — Claude Code, Codex, VS Code).
  @redirect_hosts ["claude.ai", "claude.com", "vscode.dev", "chatgpt.com"]

  # Private-use redirect schemes native clients may register (exact scheme;
  # noizu_mcp >= 0.6.2 refuses javascript/data/file/web schemes regardless).
  # Cursor returns to cursor://anysphere.cursor-mcp/oauth/callback.
  @redirect_schemes ["cursor"]

  def scopes, do: @scopes
  def path, do: @path

  def issuer do
    case Application.get_env(:annotate, :mcp, [])[:issuer] do
      issuer when is_binary(issuer) and issuer != "" -> issuer
      _ -> raise "config :annotate, :mcp, issuer: is not set"
    end
  end

  def resource, do: issuer() <> @path

  @doc "HS256 signing key (domain-separated from the raw env value)."
  def secret do
    raw =
      case Application.get_env(:annotate, :mcp, [])[:signing_secret] do
        s when is_binary(s) and byte_size(s) >= 32 -> s
        _ -> raise "config :annotate, :mcp, signing_secret: missing or < 32 bytes"
      end

    :crypto.mac(:hmac, :sha256, raw, "annotate mcp oauth access tokens v1")
  end

  @doc "Store options (shared by the AS and by Annotate.MCP.Grants)."
  def store, do: {Noizu.MCP.Auth.Server.Store.Ecto, repo: Annotate.Repo}

  @doc "The `Noizu.MCP.Auth.Server.Config` for every OAuth endpoint."
  def auth_server do
    Noizu.MCP.Auth.Server.config(
      issuer: issuer(),
      store: store(),
      signing: {:hs256, {__MODULE__, :secret}},
      scopes_supported: @scopes,
      # A client that registers (DCR) or authorizes without a `scope` gets all
      # three, shown on the consent screen. Not read-only: noizu_mcp fixes a
      # DCR client's scope at registration (default_scope), and common MCP
      # clients register without one — a read-only default would make every
      # write tool permanently unreachable for them. Clients that ask for less
      # get less; tools re-check per call.
      default_scope: @scopes,
      access_token_ttl: 900,
      refresh_token_ttl: 30 * 24 * 3600,
      refresh_family_ttl: 90 * 24 * 3600,
      track_access_tokens: true,
      resources: [[resource: resource(), name: "annotate comments"]],
      dcr: [
        enabled: true,
        allowed_redirect_hosts: @redirect_hosts,
        allowed_redirect_schemes: @redirect_schemes
      ],
      cimd: [
        enabled: true,
        allowed_redirect_hosts: @redirect_hosts,
        allowed_redirect_schemes: @redirect_schemes
      ],
      upstream:
        {Noizu.MCP.Auth.Server.Upstream.HostSession,
         current_subject: {Annotate.MCP.Bridge, :current_subject},
         login_url: {Annotate.MCP.Bridge, :login_url}},
      consent: [enabled: true, renderer: {AnnotateWeb.MCP.Consent, :render}],
      rate_limit: {Annotate.MCP.RateLimit, :oauth}
    )
  end

  @doc "Resource-server options for the Streamable HTTP plug on `/mcp`."
  def transport_auth do
    [
      verifier: {Annotate.MCP.Verifier, []},
      resource_metadata: issuer() <> "/.well-known/oauth-protected-resource" <> @path,
      scope: Enum.join(@scopes, " ")
    ]
  end

  @doc "RFC 9728 protected-resource metadata (path-inserted and bare)."
  def protected_resource_metadata do
    [
      authorization_servers: [issuer()],
      scopes_supported: @scopes,
      bearer_methods_supported: ["header"],
      default_resource: @path,
      resources: %{@path => [resource: resource(), resource_name: "annotate comments"]}
    ]
  end
end
