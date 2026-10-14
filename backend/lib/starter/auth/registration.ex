defmodule Starter.Auth.Registration do
  @moduledoc """
  Password registration as one transactional seam with invite consumption.

  The user row, the invite redemption, and the org membership grant commit
  together: a redemption that loses an exhaustion race rolls the whole
  registration back instead of stranding an approved account with no
  membership. Sessions and tokens are issued by callers only on
  `{:ok, user}`, so a rolled-back user never receives a valid session.
  """

  @doc """
  Registers a password user and consumes `invite` (may be nil on open
  deployments) in a single transaction. Returns `{:ok, user}` or
  `{:error, reason}`.
  """
  def register_user_with_invite(user_attrs, credential, opts, invite, conn \\ nil) do
    Starter.Repo.transaction(fn ->
      with {:ok, {user, _credential}} <-
             Starter.Users.register(user_attrs, credential, Noizu.Context.system(), opts),
           {:ok, _} <- maybe_redeem_invite(invite, user, conn),
           :ok <- maybe_grant_invite_membership(invite, user.id) do
        user
      else
        {:error, reason} -> Starter.Repo.rollback(reason)
      end
    end)
  end

  defp maybe_redeem_invite(nil, _user, _conn), do: {:ok, nil}

  defp maybe_redeem_invite(invite, user, conn) do
    case Starter.Organizations.redeem_invite_for_user(invite, user, conn) do
      {:ok, _} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  # Membership at the role the inviter chose; already-member is a no-op so a
  # re-used link cannot downgrade anyone.
  defp maybe_grant_invite_membership(nil, _user_id), do: :ok

  defp maybe_grant_invite_membership(invite, user_id) do
    if invite.organization_id do
      role = invite.role || "viewer"

      case Starter.Authz.authorize(user_id, "organization", invite.organization_id, "viewer") do
        {:ok, _} ->
          :ok

        {:error, _} ->
          case Starter.Authz.ScopedMemberships.add_member(
                 "organization",
                 invite.organization_id,
                 user_id,
                 role
               ) do
            {:ok, _} -> :ok
            error -> error
          end
      end
    else
      :ok
    end
  end
end
