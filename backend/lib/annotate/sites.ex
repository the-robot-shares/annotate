defmodule Annotate.Sites do
  @moduledoc """
  Site tenancy, service keys, and commenter identities for the annotate API.
  """

  import Ecto.Query
  alias Annotate.Auth.ServiceKey
  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Commenter
  alias Annotate.Schema.Annotate.Site

  @default_settings %{
    "public_read" => true,
    "page_key_strategy" => "strip_query_hash",
    "max_upload_mb" => 20
  }

  # ── Sites ─────────────────────────────────────────────────────

  def get_site(id), do: Repo.get(Site, id)

  def get_site_by_slug(slug) when is_binary(slug), do: Repo.get_by(Site, slug: slug)
  def get_site_by_slug(_), do: nil

  def get_site!(id), do: Repo.get!(Site, id)

  @doc """
  Creates a site and its service key. Returns `{:ok, site, service_key}` —
  the key is shown ONCE (the operator stores it; the DB keeps hash + sealed).
  """
  def create_site(attrs) do
    service_key = ServiceKey.generate()

    attrs =
      attrs
      |> Map.put_new("settings", @default_settings)
      |> Map.put("service_key_hash", ServiceKey.hash(service_key))
      |> Map.put("service_key_encrypted", ServiceKey.encrypt(service_key))

    %Site{}
    |> Site.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, site} -> {:ok, site, service_key}
      error -> error
    end
  end

  @doc "Exact-match origin check against `sites.allowed_origins` (no wildcards)."
  def allowed_origin?(%Site{allowed_origins: origins}, origin)
      when is_binary(origin) and is_list(origins),
      do: origin in origins

  def allowed_origin?(_, _), do: false

  @doc """
  True when at least one site lists `origin` in its `allowed_origins`.

  First gate of the annotate websocket handshake (`AnnotateWeb.AnnotateSocket.
  check_origin/1`): Phoenix hands that MFA only the parsed Origin header, so
  the registry-wide check runs at the transport and the per-site binding
  runs in `connect/3` where the site connect param is available.
  """
  def origin_registered?(origin) when is_binary(origin) do
    Repo.exists?(from(s in Site, where: ^origin in s.allowed_origins))
  end

  def origin_registered?(_), do: false

  # Settings accessors (jsonb-backed; tolerant of absent keys).

  def public_read?(%Site{} = site), do: get_in_settings(site, ["public_read"], true) == true
  def public_read?(_), do: false

  @doc """
  Per-site opt-in for anonymous (token-less) thread creation, default **false**.

  Stored on `comment_policy["allow_anonymous"]` (not `settings`) so it sits
  next to the other comment-admission rules enforced by `Annotate.Embed.Policy`.
  When false (the default), thread creation requires a token like every other
  write.
  """
  def allow_anonymous?(%Site{comment_policy: policy}) when is_map(policy),
    do: policy["allow_anonymous"] == true

  def allow_anonymous?(_), do: false

  def max_upload_mb(%Site{} = site) do
    case get_in_settings(site, ["max_upload_mb"], 20) do
      n when is_integer(n) and n > 0 -> n
      _ -> 20
    end
  end

  def page_key_strategy(%Site{} = site),
    do: get_in_settings(site, ["page_key_strategy"], "strip_query_hash")

  def get_in_settings(%Site{settings: settings}, key_path, default)
      when is_map(settings) do
    # `false` is a meaningful value (e.g. public_read: false) — only fall back
    # to the default when the key is absent.
    case get_in(settings, key_path) do
      nil -> default
      value -> value
    end
  end

  def get_in_settings(_, _, default), do: default

  # ── Commenters ────────────────────────────────────────────────

  def get_commenter(id) when is_binary(id), do: Repo.get(Commenter, id)
  def get_commenter(_), do: nil

  @doc "Upserts an Authentik-identified commenter by `authentik_sub`."
  def upsert_commenter_by_sub(site, claims) do
    sub = claims["sub"]

    case Repo.get_by(Commenter, authentik_sub: sub) do
      %Commenter{} = commenter ->
        {:ok, update_commenter_profile(commenter, claims)}

      nil ->
        %Commenter{}
        |> Commenter.changeset(%{
          authentik_sub: sub,
          display_name: display_name(claims),
          email: claims["email"],
          avatar_url: claims["picture"],
          site_id: site && site.id
        })
        |> Repo.insert()
    end
  end

  @doc "Upserts a host-asserted commenter by `(site_id, external_id)`."
  def upsert_commenter_by_external(site, external_id, claims) do
    case Repo.get_by(Commenter, site_id: site.id, external_id: external_id) do
      %Commenter{} = commenter ->
        {:ok, update_commenter_profile(commenter, claims)}

      nil ->
        %Commenter{}
        |> Commenter.changeset(%{
          site_id: site.id,
          external_id: external_id,
          display_name: display_name(claims),
          email: claims["email"],
          avatar_url: claims["avatar"]
        })
        |> Repo.insert()
    end
  end

  @doc """
  Upserts a site-scoped **guest** commenter row for an anonymous display name.

  Guests have no credentials (no `authentik_sub`, no host assertion): the row
  exists only so comments never carry a NULL author. `external_id` is derived
  as `"guest:" <> name` and unique per site, so repeat posts under the same
  name reuse one row; names are namespaced per site and never collide across
  sites. Guest rows can never authenticate (no token path issues for them).
  """
  def upsert_guest_commenter(%Site{} = site, guest_name) when is_binary(guest_name) do
    external_id = "guest:" <> guest_name

    case Repo.get_by(Commenter, site_id: site.id, external_id: external_id) do
      %Commenter{} = commenter ->
        {:ok, commenter}

      nil ->
        %Commenter{}
        |> Commenter.changeset(%{
          site_id: site.id,
          external_id: external_id,
          display_name: guest_name
        })
        |> Repo.insert()
    end
  end

  defp update_commenter_profile(commenter, claims) do
    attrs =
      %{}
      |> maybe_put(:display_name, display_name(claims))
      |> maybe_put(:email, claims["email"] || claims["avatar_email"])
      |> maybe_put(:avatar_url, claims["picture"] || claims["avatar"])

    commenter
    |> Commenter.changeset(attrs)
    |> Repo.update!()
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp display_name(claims),
    do:
      claims["name"] || claims["given_name"] || claims["preferred_username"] ||
        claims["nickname"]

  @doc "Promotes a commenter to site owner (used by ops; keeps FK constraint)."
  def set_site_owner(%Site{} = site, %Commenter{} = commenter) do
    site
    |> Ecto.Changeset.change(owner_commenter_id: commenter.id)
    |> Repo.update!()
  end

  @doc "Site owner for a given site, if any."
  def site_owner(%Site{owner_commenter_id: nil}), do: nil

  def site_owner(%Site{owner_commenter_id: owner_id}) do
    Repo.one(from c in Commenter, where: c.id == ^owner_id, limit: 1)
  end
end
