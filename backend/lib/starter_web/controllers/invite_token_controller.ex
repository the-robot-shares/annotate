defmodule StarterWeb.InviteTokenController do
  @moduledoc """
  Invite links for an organization.

  Token handling rules this controller exists to enforce:

    * the raw token is returned **exactly once**, from `create/2` — it is
      bcrypt-hashed at rest and cannot be recovered afterwards;
    * `token_hash` never appears in any response (`list_invites/1` does not
      even select it);
    * `lookup/2` is the only public action. It is a token-validity oracle by
      nature, so it is rate-limited at the router, returns 404 with no detail
      for anything invalid, and echoes neither the token nor its hash.
  """

  use StarterWeb, :controller

  alias Starter.Organizations

  @default_ttl_days 14

  @doc """
  Org-scoped admin listing: invites plus a compact view of who redeemed them.
  """
  def index(conn, %{"org_id" => org_id}) do
    counts = Organizations.invite_redemption_counts(org_id)

    invites =
      Organizations.list_invites(org_id)
      |> Enum.map(fn invite ->
        Map.put(invite, :redemptions, Map.get(counts, invite.id, 0))
      end)

    conn |> put_status(:ok) |> json(%{invites: invites})
  end

  def create(conn, %{"org_id" => org_id} = params) do
    with {:ok, role} <- Organizations.validate_invite_role(params["role"]),
         {:ok, expires_at} <- expires_at(params["expires_in_days"]),
         {:ok, max_uses} <- max_uses(params["max_uses"]),
         {:ok, invite, raw_token} <-
           Organizations.create_invite_token(%{
             organization_id: org_id,
             created_by_user_id: get_user_id(conn),
             email: optional_string(params["email"]),
             role: role,
             max_uses: max_uses,
             expires_at: expires_at
           }) do
      conn
      |> put_status(:created)
      |> json(%{
        invite: serialize_invite(invite),
        # First and last time the caller sees this value.
        token: raw_token,
        link: "/join/#{raw_token}"
      })
    else
      {:error, :invalid_role} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid role", roles: Organizations.invite_roles()})

      {:error, :invalid_expiry} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "expires_in_days must be a positive integer"})

      {:error, :invalid_max_uses} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "max_uses must be a positive integer"})

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def delete(conn, %{"org_id" => org_id, "id" => invite_id}) do
    case Organizations.revoke_invite(org_id, invite_id) do
      :ok ->
        conn |> put_status(:ok) |> json(%{message: "Invite revoked"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Invite not found"})
    end
  end

  @doc """
  Redemptions recorded against one invite (org-scoped).
  """
  def redemptions(conn, %{"org_id" => org_id, "id" => invite_id}) do
    case owned_invite(org_id, invite_id) do
      {:ok, _invite} ->
        conn
        |> put_status(:ok)
        |> json(%{redemptions: redemptions_for(invite_id)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Invite not found"})
    end
  end

  @doc """
  Public pre-signup lookup for `/join/<token>`: tells an anonymous visitor which
  org they were invited to and at what role, so the join page can say something
  meaningful before they have an account.

  Returns 404 for revoked / expired / exhausted / unknown tokens — the same
  response for all of them, so this leaks only "valid or not".
  """
  def lookup(conn, %{"token" => raw_token}) when is_binary(raw_token) do
    case Organizations.find_active_invite_by_raw_token(raw_token) do
      {:ok, invite} ->
        conn
        |> put_status(:ok)
        |> json(%{
          organization_name: Organizations.organization_name(invite.organization_id),
          role: invite.role || "viewer",
          email_required: not is_nil(invite.email)
        })

      {:error, _} ->
        not_found(conn)
    end
  end

  def lookup(conn, _params), do: not_found(conn)

  @doc """
  Redeem an invite as an already-registered, logged-in user.

  This is the "I already have an account" half of the join flow — the
  registration paths redeem inline, but an existing user clicking an invite link
  had no way to actually join the inviting org. Idempotent per user: a
  (invite, user) pair that already has a redemption row succeeds again without
  consuming another use (`{:ok, :already_redeemed}` short-circuits the
  increment), and the membership grant skips already-members.
  """
  def redeem(conn, %{"token" => raw_token}) when is_binary(raw_token) do
    user_id = get_user_id(conn)

    # Starter.Auth.InviteGate.redeem/3: email-bound check, consume, membership
    # at the invite's role, and a gated (:pending/:waitlist/:unverified)
    # account flips :active — one transaction.
    with {:ok, user} <- fetch_user(user_id),
         {:ok, invite} <- Starter.Auth.InviteGate.redeem(user, raw_token, conn) do
      conn
      |> put_status(:ok)
      |> json(%{
        organization_id: invite.organization_id,
        organization_name:
          invite.organization_id && Organizations.organization_name(invite.organization_id),
        role: invite.role || "viewer",
        invite_required: false,
        organizations: Organizations.list_user_organizations(user_id)
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired invite token"})

      {:error, :invite_exhausted} ->
        conn |> put_status(:conflict) |> json(%{error: "This invite has already been used"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def redeem(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "token required"})
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp not_found(conn),
    do: conn |> put_status(:not_found) |> json(%{error: "Invalid or expired invite token"})

  defp owned_invite(org_id, invite_id) do
    invite = Starter.Repo.get(Starter.Schema.Organizations.InviteToken, invite_id)

    if invite && invite.organization_id == org_id do
      {:ok, invite}
    else
      {:error, :not_found}
    end
  end

  # The redemption rows carry the inviter's chosen context; remote_ip is kept
  # server-side (audit trail), not surfaced in the admin listing.
  defp redemptions_for(invite_id),
    do: Organizations.list_invite_redemptions(invite_id)

  defp serialize_invite(invite) do
    %{
      id: invite.id,
      email: invite.email,
      role: invite.role,
      key_prefix: invite.key_prefix,
      status: invite.status,
      revoked: invite.revoked,
      uses: invite.uses,
      max_uses: invite.max_uses,
      expires_at: invite.expires_at,
      inserted_at: invite.inserted_at
    }
  end

  defp fetch_user(nil), do: {:error, :invalid_user}

  defp fetch_user(user_id) do
    case Starter.Users.get_user(user_id, Noizu.Context.system()) do
      {:ok, user} when is_map(user) -> {:ok, user}
      _ -> {:error, :invalid_user}
    end
  end

  # Malformed numeric input is rejected, not silently coerced — an admin who
  # asks for "0" or "-1" uses (or "forever" days) should hear about it.
  defp expires_at(nil), do: {:ok, default_expiry()}
  defp expires_at(""), do: {:ok, default_expiry()}

  defp expires_at(days) when is_integer(days) and days > 0,
    do: {:ok, DateTime.utc_now() |> DateTime.add(days * 86_400, :second)}

  defp expires_at(days) when is_integer(days), do: {:error, :invalid_expiry}

  defp expires_at(days) when is_binary(days) do
    case Integer.parse(days) do
      {n, ""} -> expires_at(n)
      _ -> {:error, :invalid_expiry}
    end
  end

  defp expires_at(_), do: {:error, :invalid_expiry}

  defp default_expiry,
    do: DateTime.utc_now() |> DateTime.add(@default_ttl_days * 86_400, :second)

  defp max_uses(nil), do: {:ok, nil}
  defp max_uses(""), do: {:ok, nil}
  defp max_uses(n) when is_integer(n) and n > 0, do: {:ok, n}
  defp max_uses(n) when is_integer(n), do: {:error, :invalid_max_uses}

  defp max_uses(n) when is_binary(n) do
    case Integer.parse(n) do
      {parsed, ""} -> max_uses(parsed)
      _ -> {:error, :invalid_max_uses}
    end
  end

  defp max_uses(_), do: {:error, :invalid_max_uses}

  defp optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_string(_), do: nil

  defp get_user_id(conn) do
    case Starter.Guardian.Plug.current_resource(conn) do
      %Starter.Users.Sessions.UserSession{user: {:ref, _, id}} -> id
      %Starter.Users.Sessions.UserSession{user: %{id: id}} -> id
      _ -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
