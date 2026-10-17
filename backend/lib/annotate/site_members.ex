defmodule Annotate.SiteMembers do
  @moduledoc """
  Site team management: the `site_members` table (owner / admin / member)
  that powers the owner dashboard and defines "team" for the embed.

  Two identity realms meet here:

  - **Dashboard realm**: scaffold `users` (Guardian sessions, GitHub
    sign-in). This context manages their membership rows directly.
  - **Embed realm**: `commenters` (15-minute access JWTs). They never get
    membership rows; `team_role_for_commenter/3` bridges an Authentik
    commenter by email: `commenter.email → users.email → site_members`.
    The bridge only runs when BOTH sides are verified (the IdP's
    `email_verified` on the commenter, `users.verified` on the dashboard
    user), so an unverified email can never inherit a team role.

  Roles rank `owner > admin > member`; `role_at_least?/2` expresses the
  dashboard ladder (member: view + inbox · admin: display settings +
  moderation · owner: security settings, members, key rotation). The last
  owner of a site can neither be demoted nor removed (`:last_owner`); the
  guard runs inside a transaction that locks the site's owner rows, so two
  concurrent demotions cannot both pass.
  """

  import Ecto.Query

  alias Annotate.Repo
  alias Annotate.Schema.Annotate.Site
  alias Annotate.Schema.Annotate.SiteMember
  alias Annotate.Schema.Users.User

  @roles ~w(owner admin member)a
  @role_rank %{owner: 3, admin: 2, member: 1}

  # ── Role helpers ───────────────────────────────────────────────

  def roles, do: @roles

  def role_rank(role) when role in @roles, do: @role_rank[role]
  def role_rank(_), do: 0

  @doc "True when `role` satisfies `min` (member < admin < owner)."
  def role_at_least?(role, min) when role in @roles and min in @roles,
    do: role_rank(role) >= role_rank(min)

  def role_at_least?(_, _), do: false

  def normalize_role("owner"), do: :owner
  def normalize_role("admin"), do: :admin
  def normalize_role("member"), do: :member
  def normalize_role(role) when role in @roles, do: role
  def normalize_role(_), do: nil

  @doc "Trimmed, downcased email (citext compares case-insensitively; whitespace it does not)."
  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(_), do: nil

  # ── Membership queries ─────────────────────────────────────────

  @doc "The membership row for `(site, user)`, or nil."
  def get_membership(%Site{id: site_id}, user_id) when is_binary(user_id),
    do: Repo.get_by(SiteMember, site_id: site_id, user_id: user_id)

  def get_membership(_, _), do: nil

  @doc "The member's role on `site` (`:owner | :admin | :member | nil`)."
  def member_role(%Site{} = site, user_id) do
    case get_membership(site, user_id) do
      %SiteMember{role: role} -> role
      nil -> nil
    end
  end

  @doc "Members with their scaffold user identity (email), oldest first."
  def list_members(%Site{id: site_id}) do
    from(m in SiteMember,
      join: u in assoc(m, :user),
      where: m.site_id == ^site_id,
      order_by: [asc: m.inserted_at],
      preload: [user: u]
    )
    |> Repo.all()
    |> Enum.map(fn m ->
      %{
        id: m.id,
        user_id: m.user_id,
        email: m.user.email,
        user_name: m.user.user_name,
        role: m.role,
        inserted_at: m.inserted_at
      }
    end)
  end

  def member_count(%Site{id: site_id}),
    do: Repo.one(from(m in SiteMember, where: m.site_id == ^site_id, select: count(m.id)))

  @doc "Number of sites `user_id` owns (the self-serve creation cap counts these)."
  def owned_site_count(user_id) when is_binary(user_id),
    do:
      Repo.one(
        from(m in SiteMember,
          where: m.user_id == ^user_id and m.role == :owner,
          select: count(m.id)
        )
      )

  @doc "Sites `user_id` belongs to, with the user's role and member count (dashboard list)."
  def list_sites_for_user(user_id) when is_binary(user_id) do
    member_counts =
      from(m in SiteMember,
        group_by: m.site_id,
        select: %{site_id: m.site_id, count: count(m.id)}
      )

    from(s in Site,
      join: m in SiteMember,
      on: m.site_id == s.id and m.user_id == ^user_id,
      left_join: mc in subquery(member_counts),
      on: mc.site_id == s.id,
      order_by: [asc: s.name],
      select: {s, m.role, mc.count}
    )
    |> Repo.all()
    |> Enum.map(fn {site, role, count} ->
      %{site: site, role: role, member_count: count || 0}
    end)
  end

  # ── Membership writes ──────────────────────────────────────────

  @doc """
  Adds a user to `site` with `role`. `who` is a `%User{}` or an email.

  Only **verified, non-deleted** users can be added by email: an account
  registered with someone else's address (unverified) must never inherit a
  membership meant for the address's real owner.

  Returns `{:ok, member}` · `{:error, :user_not_found}` ·
  `{:error, :user_not_verified}` · `{:error, :already_member}` ·
  `{:error, :invalid_role}` · `{:error, :plan_user_limit}` (billing on and the
  SITE OWNER's plan users limit is reached — distinct members across the
  owner's sites) · `{:error, changeset}`.
  """
  def add_member(site, who, role, inviter \\ nil)

  def add_member(
        %Site{} = site,
        %User{verified: true, status: :active, id: user_id},
        role,
        inviter
      ),
      do: insert_member(site, user_id, role, inviter)

  # Verified but still held by the invite gate (pending): not addable yet.
  def add_member(%Site{}, %User{verified: true}, _role, _inviter), do: {:error, :user_not_active}

  def add_member(%Site{}, %User{}, _role, _inviter), do: {:error, :user_not_verified}

  def add_member(%Site{} = site, email, role, inviter) when is_binary(email) do
    case find_user_by_email(email) do
      nil -> {:error, :user_not_found}
      %User{} = user -> add_member(site, user, role, inviter)
    end
  end

  @doc """
  Idempotent owner grant (dashboard site creation, ops seeding): inserts the
  membership or promotes an existing row to owner.
  """
  def grant_owner(%Site{} = site, %{id: user_id}) when is_binary(user_id) do
    case get_membership(site, user_id) do
      %SiteMember{role: :owner} = m ->
        {:ok, m}

      %SiteMember{} = m ->
        m |> Ecto.Changeset.change(role: :owner) |> Repo.update()

      nil ->
        %SiteMember{}
        |> SiteMember.changeset(%{site_id: site.id, user_id: user_id, role: :owner})
        |> Repo.insert()
    end
  end

  @doc """
  Ops seed (`mix annotate.site.grant`, `Annotate.Release.grant_site_owner/2`):
  owner grant by site slug + VERIFIED user email. Returns `:ok` ·
  `{:error, :site_not_found | :user_not_found | :user_not_verified}`.
  """
  def grant_owner_by_email(slug, email) do
    with {:site, %Site{} = site} <- {:site, Annotate.Sites.get_site_by_slug(slug)},
         {:user, %User{} = user} <- {:user, find_user_by_email(email)},
         {:verified, true} <- {:verified, user.verified == true},
         {:ok, _} <- grant_owner(site, user) do
      :ok
    else
      {:site, _} -> {:error, :site_not_found}
      {:user, _} -> {:error, :user_not_found}
      {:verified, _} -> {:error, :user_not_verified}
      {:error, _} = error -> error
    end
  end

  def grant_owner!(site, user) do
    {:ok, m} = grant_owner(site, user)
    m
  end

  defp insert_member(site, user_id, role, inviter) do
    with {:role, role} when role != nil <- {:role, normalize_role(role)},
         {:existing, nil} <- {:existing, get_membership(site, user_id)},
         :ok <- Annotate.Billing.check_member_addition(site.id) do
      %SiteMember{}
      |> SiteMember.changeset(%{
        site_id: site.id,
        user_id: user_id,
        role: role,
        invited_by: inviter && inviter.id
      })
      |> Repo.insert()
    else
      {:role, nil} -> {:error, :invalid_role}
      {:existing, %SiteMember{}} -> {:error, :already_member}
    end
  end

  @doc """
  Changes a member's role. Returns `{:ok, member}` · `{:error, :not_found}` ·
  `{:error, :invalid_role}` · `{:error, :last_owner}` (demoting the last owner).
  """
  def update_role(%Site{} = site, user_id, role) do
    case normalize_role(role) do
      nil ->
        {:error, :invalid_role}

      role ->
        locked(site, fn ->
          with {:ok, m} <- fetch_membership(site, user_id),
               :ok <- last_owner_guard(m, role) do
            m |> Ecto.Changeset.change(role: role) |> Repo.update()
          end
        end)
    end
  end

  @doc """
  Removes a member. Returns `{:ok, member}` · `{:error, :not_found}` ·
  `{:error, :last_owner}` (removing the last owner).
  """
  def remove_member(%Site{} = site, user_id) do
    locked(site, fn ->
      with {:ok, m} <- fetch_membership(site, user_id),
           :ok <- last_owner_guard(m, nil) do
        Repo.delete(m)
      end
    end)
  end

  defp fetch_membership(site, user_id) do
    case get_membership(site, user_id) do
      nil -> {:error, :not_found}
      m -> {:ok, m}
    end
  end

  # Runs `fun` in a transaction holding row locks on the site's owners, so
  # the owner count the guard reads cannot change underneath it.
  defp locked(%Site{id: site_id}, fun) do
    Repo.transaction(fn ->
      from(o in SiteMember,
        where: o.site_id == ^site_id and o.role == :owner,
        lock: "FOR UPDATE",
        select: o.id
      )
      |> Repo.all()

      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Demotion/removal of an owner is only allowed when another owner remains.
  defp last_owner_guard(%SiteMember{role: :owner}, :owner), do: :ok

  defp last_owner_guard(%SiteMember{role: :owner, site_id: site_id}, _new_role) do
    owners =
      Repo.one(
        from(o in SiteMember,
          where: o.site_id == ^site_id and o.role == :owner,
          select: count(o.id)
        )
      )

    if owners > 1, do: :ok, else: {:error, :last_owner}
  end

  defp last_owner_guard(_, _), do: :ok

  # ── Commenter → team bridge (embed realm) ──────────────────────

  @doc """
  Resolves the team role for an embed-realm `commenter` on `site` by email:
  `commenter.email → users.email → site_members`.

  Fails closed (nil) unless ALL hold:
  - the commenter is an **Authentik** identity (`authentik_sub` set); host-
    asserted and guest rows never bridge (their email is a claim from the
    wire, not something an IdP verified for us);
  - the commenter's `email_verified` is `true` (IdP-asserted at SSO upsert);
  - the matching dashboard user is `verified` and not deleted.
  """
  def team_role_for_commenter(site, commenter, opts \\ [])

  def team_role_for_commenter(
        %Site{} = site,
        %{authentik_sub: sub, email: email, email_verified: true},
        _opts
      )
      when is_binary(sub) and sub != "" and is_binary(email) and email != "" do
    case verified_user_id(email) do
      nil -> nil
      user_id -> member_role(site, user_id)
    end
  end

  def team_role_for_commenter(_, _, _), do: nil

  defp verified_user_id(email) do
    email = normalize_email(email)

    Repo.one(
      from(u in User,
        where:
          u.email == ^email and u.verified == true and u.status == :active and
            is_nil(u.deleted_at),
        select: u.id,
        limit: 1
      )
    )
  end

  defp find_user_by_email(email) do
    case normalize_email(email) do
      nil ->
        nil

      "" ->
        nil

      email ->
        Repo.one(from(u in User, where: u.email == ^email and is_nil(u.deleted_at), limit: 1))
    end
  end
end
