defmodule Annotate.Embed.Visibility do
  @moduledoc """
  Read visibility for embed viewers (`comment_policy.read_visibility`).

  - `:public` (default): every reader sees every thread (subject to the
    existing `settings.public_read` gate).
  - `:staff_only`: **staff** see everything; everyone else sees only threads
    whose `created_by` is their own commenter, with every comment in them
    (staff replies included). Anonymous viewers (no token) see nothing: guest
    rows are shared by name and hold no credential, so "your own anonymous
    thread" cannot be identified safely.

  **Staff** = a live team role (`Annotate.Embed.Team.current_role/3`: bridge
  membership re-read from `site_members`, or a host-asserted `team_role`
  honoured only while `trust_host_roles` is on) of owner, admin **or member**,
  or the legacy `sites.owner_commenter_id`. Re-derived on every request and
  every realtime event — never read off the token claim alone.

  Every read path goes through here: thread listing (SQL filter via
  `scope_threads/2`), thread/comment by id (`can_read_thread?/2` → 404),
  realtime fan-out (`AnnotateWeb.PageChannel.handle_out/3`) and the
  permission endpoints (`permissions/3`).
  """

  import Ecto.Query

  alias Annotate.Embed.Team
  alias Annotate.Sites
  alias Annotate.Schema.Annotate.Commenter
  alias Annotate.Schema.Annotate.Site

  defstruct commenter_id: nil, role: nil, staff?: false, visibility: :public

  @type t :: %__MODULE__{
          commenter_id: binary() | nil,
          role: :owner | :admin | :member | nil,
          staff?: boolean(),
          visibility: :public | :staff_only
        }

  @doc "The viewer for this request/event, computed NOW from DB + site policy."
  def viewer(%Site{} = site, commenter, claims) do
    role = role(site, commenter, claims)

    %__MODULE__{
      commenter_id: commenter_id(commenter),
      role: role,
      staff?: role != nil,
      visibility: Sites.read_visibility(site)
    }
  end

  @doc "True when the viewer may read every thread on the site."
  def can_read_all?(%__MODULE__{visibility: :public}), do: true
  def can_read_all?(%__MODULE__{staff?: staff?}), do: staff?

  @doc "True when the viewer may read a thread created by `creator_id`."
  def can_read_creator?(%__MODULE__{} = v, creator_id) do
    can_read_all?(v) or (is_binary(v.commenter_id) and v.commenter_id == creator_id)
  end

  @doc "True when the viewer may read `thread` (and every comment in it)."
  def can_read_thread?(%__MODULE__{} = v, %{created_by: creator_id}),
    do: can_read_creator?(v, creator_id)

  def can_read_thread?(_, _), do: false

  @doc """
  Narrows a thread query (binding `t`) to what the viewer may read. Public or
  staff viewers are untouched; under staff_only a non-staff viewer gets only
  their own threads and an anonymous viewer gets none.
  """
  def scope_threads(query, %__MODULE__{} = v) do
    cond do
      can_read_all?(v) -> query
      is_binary(v.commenter_id) -> where(query, [t], t.created_by == ^v.commenter_id)
      true -> where(query, [t], false)
    end
  end

  @doc """
  The viewer's permission map (`GET /me`, merged into `GET /config`). No PII:
  only booleans, the role name and the site's visibility mode.
  """
  def permissions(%Site{} = site, commenter, claims) do
    v = viewer(site, commenter, claims)
    authenticated = commenter_id(commenter) != nil

    %{
      "authenticated" => authenticated,
      # The viewer's own commenter id lets widgets show Edit/Delete only on
      # comments they may change (additive; absent when anonymous).
      "commenter_id" => commenter_id(commenter),
      "role" => v.role && Atom.to_string(v.role),
      "staff" => v.staff?,
      "can_read_all" => can_read_all?(v),
      "can_moderate" => v.role in [:owner, :admin],
      "can_post" => authenticated or Sites.allow_anonymous?(site),
      "read_visibility" => Atom.to_string(v.visibility)
    }
  end

  # ── Internals ─────────────────────────────────────────────────

  defp role(_site, nil, _claims), do: nil

  defp role(%Site{} = site, %Commenter{} = commenter, claims) do
    case Team.current_role(site, commenter, claims || %{}) do
      nil -> if site.owner_commenter_id == commenter.id, do: :owner, else: nil
      role -> role
    end
  end

  defp commenter_id(%Commenter{id: id}), do: id
  defp commenter_id(_), do: nil
end
