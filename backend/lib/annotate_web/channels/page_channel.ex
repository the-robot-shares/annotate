defmodule AnnotateWeb.PageChannel do
  @moduledoc """
  Read-only per-page topic for the annotate embed.

  Topic: `page:<site_slug>:<sha256_hex_lower(page_key)>` — the client hashes
  its page_key with sha256 (lowercase hex) so topics stay bounded
  (`Annotate.Realtime.page_hash/1`).

  Joins are authorized like the REST thread listing:

  - anonymous join only when the site's `settings.public_read` is true;
  - otherwise a valid access token (verified at connect) whose `site` claim
    equals the connecting site AND whose `origin` claim is one of that site's
    `allowed_origins` (the handshake origin itself was validated against the
    same list by the socket's `check_origin`/connect layers).

  The channel is **read-only**: an explicit catch-all `handle_in/3` rejects
  every client push with `read_only` (Phoenix 1.8 defines no default
  `handle_in`, so without it an unmatched push would crash the channel).
  Events arrive as broadcasts from `Annotate.Realtime` after context commits.
  """

  use Phoenix.Channel

  alias Annotate.Sites
  alias Annotate.Schema.Annotate.Site

  @page_hash_format ~r/^[0-9a-f]{64}$/

  @impl true
  def join("page:" <> topic_tail, _payload, socket) do
    with {:ok, slug, page_hash} <- split_topic(topic_tail),
         :ok <- check_site_binding(slug, socket),
         :ok <- authorize(socket) do
      {:ok, assign(socket, :page_slug, slug) |> assign(:page_hash, page_hash)}
    end
  end

  def join(_topic, _payload, _socket), do: {:error, %{reason: "invalid_topic"}}

  # Read-only guard: without this catch-all an unmatched client push would
  # raise UndefinedFunctionError and crash the channel process (Phoenix
  # defines no default handle_in). Every push is rejected — there are no
  # write handlers; state changes only arrive as REST commits → broadcasts.
  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "read_only"}}, socket}
  end

  # Outbound relay: `use Phoenix.Channel` ships no default handle_out in
  # Phoenix 1.8, so broadcasts on the topic are pushed to the client here.
  # Server → client only; no client input flows through it.
  #
  # Per-viewer visibility (comment_policy.read_visibility): every
  # Annotate.Realtime payload carries an internal "__vis" key that is ALWAYS
  # stripped here. For a staff_only site the subscriber's viewer is
  # re-derived LIVE (current site policy + team membership, never the
  # connect-time snapshot) and events for threads it may not read are
  # dropped — the broadcast fan-out is shared, so this is the only place a
  # per-viewer leak can be stopped.
  @impl true
  def handle_out(event, %{"__vis" => vis} = payload, socket) do
    if visible?(vis, socket), do: push(socket, event, Map.delete(payload, "__vis"))
    {:noreply, socket}
  end

  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp visible?(%{"read_visibility" => "public"}, _socket), do: true

  defp visible?(%{"site_id" => site_id, "creator_id" => creator_id}, socket) do
    claims = socket.assigns[:claims]
    commenter = claims && Annotate.Sites.get_commenter(claims["sub"])

    case Sites.get_site(site_id) do
      %Site{} = site ->
        site
        |> Annotate.Embed.Visibility.viewer(commenter, claims)
        |> Annotate.Embed.Visibility.can_read_creator?(creator_id)

      nil ->
        false
    end
  end

  defp visible?(_, _), do: false

  # ── Internals ─────────────────────────────────────────────────

  defp split_topic(tail) do
    case String.split(tail, ":", parts: 2) do
      [slug, hash] when byte_size(slug) > 0 ->
        if hash =~ @page_hash_format,
          do: {:ok, slug, hash},
          else: {:error, %{reason: "invalid_page_hash"}}

      _ ->
        {:error, %{reason: "invalid_topic"}}
    end
  end

  # The topic's site must be the site the socket connected as — a token or
  # subscription for another site cannot ride this socket.
  defp check_site_binding(slug, %{assigns: %{site: %Site{slug: site_slug}}}) do
    if slug == site_slug,
      do: :ok,
      else: {:error, %{reason: "site_mismatch"}}
  end

  defp authorize(%{assigns: %{site: site, claims: nil}}) do
    if Sites.public_read?(site),
      do: :ok,
      else: {:error, %{reason: "invalid_token"}}
  end

  defp authorize(%{assigns: %{site: %Site{} = site, claims: claims}}) do
    cond do
      claims["site"] != site.id ->
        {:error, %{reason: "site_mismatch"}}

      is_binary(claims["origin"]) and claims["origin"] in site.allowed_origins ->
        :ok

      true ->
        {:error, %{reason: "origin_mismatch"}}
    end
  end
end
