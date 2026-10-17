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
    "max_upload_mb" => 20,
    "default_visibility" => "public"
  }

  # Self-serve abuse bound: sites a single dashboard user may own.
  @max_owned_sites 25

  # Dashboard-editable keys, split by required role (see `update_site_display/2`
  # vs `update_site_security/2`). Anything else in the input is ignored.
  @display_settings_keys ~w(public_read page_key_strategy max_upload_mb default_visibility)
  @security_policy_keys ~w(required_groups allowed_email_domains allow_anonymous trust_host_roles read_visibility)
  @read_visibilities ~w(public staff_only)
  @page_key_strategies ~w(strip_query_hash)
  @max_origins 20

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

  def max_owned_sites, do: @max_owned_sites

  @doc """
  Dashboard site creation: validates origins, creates the site + service key
  AND the creator's owner membership in ONE transaction (a crash can never
  leave an ownerless, unmanageable site). Enforces the per-user ownership cap.

  Returns `{:ok, site, service_key}` (key shown ONCE) · `{:error, :invalid_origin}`
  · `{:error, :site_limit}` · `{:error, changeset}`.
  """
  def create_site_with_owner(attrs, %{id: user_id} = user) when is_binary(user_id) do
    origins = attrs["allowed_origins"] || []

    with {:ok, origins} <- normalize_origins(origins),
         :ok <- check_site_limit(user_id) do
      Repo.transaction(fn ->
        case create_site(%{
               "slug" => attrs["slug"],
               "name" => attrs["name"],
               "allowed_origins" => origins
             }) do
          {:ok, site, key} ->
            case Annotate.SiteMembers.grant_owner(site, user) do
              {:ok, _} -> {site, key}
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {site, key}} -> {:ok, site, key}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp check_site_limit(user_id) do
    if Annotate.SiteMembers.owned_site_count(user_id) >= @max_owned_sites,
      do: {:error, :site_limit},
      else: :ok
  end

  @doc """
  Display settings (admin+): `name` and the `settings` keys
  #{inspect(@display_settings_keys)}. Never touches origins, policy, slug or keys.
  """
  def update_site_display(%Site{} = site, attrs) do
    settings =
      attrs
      |> Map.get("settings", %{})
      |> Map.take(@display_settings_keys)

    with :ok <- validate_display_settings(settings) do
      changes = %{"settings" => Map.merge(site.settings || %{}, settings)}

      changes =
        if is_binary(attrs["name"]), do: Map.put(changes, "name", attrs["name"]), else: changes

      site
      |> Ecto.Changeset.cast(changes, [:name, :settings])
      |> Ecto.Changeset.validate_required([:name])
      |> Ecto.Changeset.validate_length(:name, min: 1, max: 120)
      |> Repo.update()
    end
  end

  defp validate_display_settings(settings) do
    ok? =
      Enum.all?(settings, fn
        {"public_read", v} -> is_boolean(v)
        {"page_key_strategy", v} -> v in @page_key_strategies
        {"max_upload_mb", v} -> is_integer(v) and v >= 1 and v <= 100
        {"default_visibility", v} -> v in ["public", "internal"]
      end)

    if ok?, do: :ok, else: {:error, :invalid_settings}
  end

  @doc """
  Security settings (OWNER only at the caller): `allowed_origins` (validated,
  exact-match contract) and the `comment_policy` keys
  #{inspect(@security_policy_keys)}.
  """
  def update_site_security(%Site{} = site, attrs) do
    policy_in = attrs |> Map.get("comment_policy", %{}) |> Map.take(@security_policy_keys)

    with {:ok, origins} <- normalize_origins(attrs["allowed_origins"] || site.allowed_origins),
         {:ok, policy_in} <- validate_policy(policy_in) do
      site
      |> Ecto.Changeset.cast(
        %{
          "allowed_origins" => origins,
          "comment_policy" => Map.merge(site.comment_policy || %{}, policy_in)
        },
        [:allowed_origins, :comment_policy]
      )
      |> Repo.update()
    end
  end

  defp validate_policy(policy) do
    Enum.reduce_while(policy, {:ok, %{}}, fn
      {k, v}, {:ok, acc} when k in ["allow_anonymous", "trust_host_roles"] and is_boolean(v) ->
        {:cont, {:ok, Map.put(acc, k, v)}}

      {"read_visibility", v}, {:ok, acc} when v in @read_visibilities ->
        {:cont, {:ok, Map.put(acc, "read_visibility", v)}}

      {k, v}, {:ok, acc} when k in ["required_groups", "allowed_email_domains"] and is_list(v) ->
        list =
          v |> Enum.filter(&is_binary/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

        if length(list) == length(v) and length(list) <= 50,
          do: {:cont, {:ok, Map.put(acc, k, Enum.uniq(list))}},
          else: {:halt, {:error, :invalid_policy}}

      _, _ ->
        {:halt, {:error, :invalid_policy}}
    end)
  end

  @doc """
  Rotates the site's service key. Returns `{:ok, site, new_key}`: the new key
  is shown ONCE; the old hash + seal are replaced, so the previous key stops
  verifying host-asserts immediately.
  """
  def rotate_service_key(%Site{} = site) do
    service_key = ServiceKey.generate()

    site
    |> Ecto.Changeset.change(
      service_key_hash: ServiceKey.hash(service_key),
      service_key_encrypted: ServiceKey.encrypt(service_key)
    )
    |> Repo.update()
    |> case do
      {:ok, site} -> {:ok, site, service_key}
      error -> error
    end
  end

  @doc """
  Normalizes and validates an origin list for the exact-match contract
  `allowed_origin?/2` depends on: `scheme://host[:port]`, lowercase host, no
  path/query/fragment/userinfo/trailing slash, no wildcards. `http://` is
  accepted only for `localhost` / `127.0.0.1`. Dedupes; max #{@max_origins}.
  Any invalid entry rejects the whole list (`{:error, :invalid_origin}`).
  """
  def normalize_origins(origins) when is_list(origins) and length(origins) <= @max_origins do
    origins
    |> Enum.reduce_while({:ok, []}, fn origin, {:ok, acc} ->
      case normalize_origin(origin) do
        {:ok, o} -> {:cont, {:ok, [o | acc]}}
        :error -> {:halt, {:error, :invalid_origin}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, list |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  def normalize_origins(_), do: {:error, :invalid_origin}

  @origin_re ~r/^(https?):\/\/([a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*)(?::(\d{1,5}))?$/

  def normalize_origin(origin) when is_binary(origin) do
    o = origin |> String.trim() |> String.downcase()

    case Regex.run(@origin_re, o) do
      [_, scheme, host | rest] ->
        port = List.first(rest)

        cond do
          port && (String.to_integer(port) < 1 or String.to_integer(port) > 65_535) -> :error
          scheme == "http" and host not in ["localhost", "127.0.0.1"] -> :error
          true -> {:ok, o}
        end

      _ ->
        :error
    end
  end

  def normalize_origin(_), do: :error

  @doc """
  Default visibility for new threads (`settings["default_visibility"]`,
  `"public"` when absent): `:public | :internal`.
  """
  def default_visibility(%Site{} = site) do
    case get_in_settings(site, ["default_visibility"], "public") do
      "internal" -> :internal
      _ -> :public
    end
  end

  @doc """
  Who may read comments (`comment_policy["read_visibility"]`, OWNER-only
  security setting): `:public` (default — every reader sees every thread) or
  `:staff_only` (team members see everything; everyone else sees only the
  threads they started, with all replies). Enforced server-side by
  `Annotate.Embed.Visibility`.
  """
  def read_visibility(%Site{comment_policy: %{"read_visibility" => "staff_only"}}),
    do: :staff_only

  def read_visibility(_), do: :public

  @doc "True when the site restricts reading to staff (+ own threads)."
  def staff_only?(site), do: read_visibility(site) == :staff_only

  @doc """
  Per-site opt-in for trusting a host-asserted `team_role` claim
  (`comment_policy["trust_host_roles"]`, default **false**).
  """
  def trust_host_roles?(%Site{comment_policy: policy}) when is_map(policy),
    do: policy["trust_host_roles"] == true

  def trust_host_roles?(_), do: false

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
        {:ok, update_commenter_profile(commenter, claims, :sso)}

      nil ->
        %Commenter{}
        |> Commenter.changeset(%{
          authentik_sub: sub,
          display_name: display_name(claims),
          email: claims["email"],
          email_verified: idp_email_verified(claims),
          avatar_url: claims["picture"],
          site_id: site && site.id
        })
        |> Repo.insert()
    end
  end

  @doc """
  The site-scoped **team** commenter row for dashboard user `user_id` (inbox
  replies). Keyed by `(site_id, user_id)` with NO `external_id`, so a host
  assertion can never claim it, and NO email, so it never feeds the bridge.
  Display name/avatar come from the user's GitHub identity.
  """
  def team_commenter_for_user(%Site{} = site, user_id) when is_binary(user_id) do
    gh = Repo.get_by(Annotate.Schema.Annotate.GithubIdentity, user_id: user_id)
    display = (gh && (gh.name || gh.login)) || "Site team"
    avatar = gh && gh.avatar_url

    case Repo.get_by(Commenter, site_id: site.id, user_id: user_id) do
      %Commenter{} = c ->
        c
        |> Ecto.Changeset.change(display_name: display, avatar_url: avatar)
        |> Repo.update()

      nil ->
        %Commenter{site_id: site.id, user_id: user_id, display_name: display, avatar_url: avatar}
        |> Repo.insert()
    end
  end

  @doc "Upserts a host-asserted commenter by `(site_id, external_id)`."
  def upsert_commenter_by_external(site, external_id, claims) do
    case Repo.get_by(Commenter, site_id: site.id, external_id: external_id) do
      %Commenter{} = commenter ->
        {:ok, update_commenter_profile(commenter, claims, :external)}

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

  # `email_verified` is written ONLY from the Authentik id_token (:sso). A
  # host-asserted JWT's `email_verified` is a claim from the wire, never
  # trusted (S1): external rows keep email_verified nil and never bridge into
  # a team role (Annotate.SiteMembers.team_role_for_commenter/3).
  defp update_commenter_profile(commenter, claims, source) do
    attrs =
      %{}
      |> maybe_put(:display_name, display_name(claims))
      |> maybe_put(:email, claims["email"] || claims["avatar_email"])
      |> maybe_put(:avatar_url, claims["picture"] || claims["avatar"])

    # Refreshed on every SSO login, so a later IdP verification lights the
    # bridge up (and a retraction turns it off) at the next issuance/refresh.
    attrs =
      if source == :sso,
        do: Map.put(attrs, :email_verified, idp_email_verified(claims)),
        else: attrs

    commenter
    |> Commenter.changeset(attrs)
    |> Repo.update!()
  end

  defp idp_email_verified(claims), do: claims["email_verified"] == true

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
