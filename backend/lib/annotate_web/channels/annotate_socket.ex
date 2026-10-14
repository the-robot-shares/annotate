defmodule AnnotateWeb.AnnotateSocket do
  @moduledoc """
  Realtime socket for the annotate embed (`/socket/annotate`, websocket only).

  ## Connect params

      %{"site" => site_slug, "token" => optional_access_jwt}

  ## Origin checking (two layers)

  Phoenix invokes the transport `check_origin/1` MFA with the parsed
  `Origin` header (and nothing else — Phoenix 1.8 does not hand the conn or
  the connect params to the MFA), so per-site origin binding is done in two
  cooperating layers:

  1. `check_origin/1` (transport gate, CSWSH protection): rejects malformed
     origins and any origin not registered in ANY annotate site's
     `allowed_origins`, and stashes the validated origin in the process
     dictionary — the transport process is the same process that later runs
     `connect/3` (Bandit upgrades the request process in place).
  2. `connect/3` (per-site binding): resolves the site from the connect
     params and, when a stashed handshake origin exists (browser clients),
     requires it to be in THAT site's `allowed_origins`. Origin-less native
     clients are tolerated, mirroring the REST API's read tolerance.

  ## Token handling

  A presented token must verify (HS256, `annotate_access`, unexpired) or the
  connect is refused (`invalid_token`) — matching the REST plug, which never
  lets a *presented but invalid* token fall through to anonymous access.
  Site/origin claim binding is enforced at join time (see
  `AnnotateWeb.PageChannel`), where the page topic names the site.
  """

  use Phoenix.Socket

  alias Annotate.Auth.ApiToken
  alias Annotate.Sites
  alias Annotate.Schema.Annotate.Site

  channel "page:*", AnnotateWeb.PageChannel

  @origin_pd_key :annotate_ws_handshake_origin

  # ── Transport check_origin MFA ────────────────────────────────

  @doc """
  `check_origin: {__MODULE__, :check_origin, []}` — receives the parsed
  Origin header URI from the websocket handshake.

  Returns true only for a well-formed http(s) origin that at least one
  annotate site lists in `allowed_origins`; also stashes the origin for the
  per-site check in `connect/3`.
  """
  def check_origin(%URI{host: nil}), do: false

  def check_origin(%URI{scheme: scheme, host: host} = uri)
      when scheme in ["http", "https"] and byte_size(host) > 0 do
    origin = origin_string(uri)
    Process.put(@origin_pd_key, origin)
    Sites.origin_registered?(origin)
  end

  def check_origin(_), do: false

  # ── Connect ───────────────────────────────────────────────────

  @impl true
  def connect(%{"site" => slug} = params, socket, _connect_info) when is_binary(slug) do
    case Sites.get_site_by_slug(slug) do
      %Site{} = site ->
        with :ok <- check_handshake_origin(site),
             {:ok, claims} <- resolve_claims(params["token"]) do
          {:ok, socket |> assign(:site, site) |> assign(:claims, claims)}
        end

      nil ->
        {:error, %{reason: "site_not_found"}}
    end
  end

  def connect(_params, _socket, _connect_info), do: {:error, %{reason: "invalid_params"}}

  @impl true
  def id(%{assigns: %{claims: %{"sub" => commenter_id}}}),
    do: "annotate_socket:#{commenter_id}"

  # Anonymous sockets stay untracked (nil id) — nothing to target with a
  # server-side disconnect.
  def id(_socket), do: nil

  # ── Internals ─────────────────────────────────────────────────

  defp check_handshake_origin(%Site{} = site) do
    case Process.get(@origin_pd_key) do
      # No Origin header on the handshake (native client) — the transport
      # MFA never ran; same tolerance the REST API has for origin-less reads.
      nil ->
        :ok

      origin ->
        if Sites.allowed_origin?(site, origin),
          do: :ok,
          else: {:error, %{reason: "origin_not_allowed"}}
    end
  end

  # A presented token must verify; only its ABSENCE yields anonymous access.
  defp resolve_claims(nil), do: {:ok, nil}

  defp resolve_claims(token) when is_binary(token) do
    case ApiToken.verify(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, _} -> {:error, %{reason: "invalid_token"}}
    end
  end

  defp resolve_claims(_), do: {:error, %{reason: "invalid_token"}}

  # Rebuild the raw origin string. URI.parse fills in the scheme's default
  # port (80/443), but browsers omit default ports in the Origin header and
  # stored origins carry none — so default ports are stripped while explicit
  # non-default ports are kept.
  defp origin_string(%URI{scheme: scheme, host: host, port: port})
       when port in [80, 443] and scheme in ["http", "https"],
       do: scheme <> "://" <> host

  defp origin_string(%URI{scheme: scheme, host: host, port: port}),
    do: scheme <> "://" <> host <> ":" <> Integer.to_string(port)
end
