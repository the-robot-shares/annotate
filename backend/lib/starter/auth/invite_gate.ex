defmodule Starter.Auth.InviteGate do
  @moduledoc """
  Server-side "invited users only" gate — register open, app gated.

  Registration never fails for a missing invite: every signup path (REST
  password register, the Hologram signup/join forms, SSO first login) creates
  the account (activation rule, user 2026-10-08):

    * valid invite at signup → redeemed inline, `:active` immediately;
    * SSO first login on a domain whose policy auto-approves the provider →
      `:active` (the IdP vouched for the email);
    * password signup on an auto-approve domain → `:unverified` until the
      email is confirmed (`confirm_email/1` flips it `:active`) — no invite is
      ever needed;
    * anything else → `:pending`, held until an invite is redeemed;
    * a supplied-but-invalid invite still fails the signup and writes nothing.

  This module is the single predicate deciding whether an authenticated
  principal may use the app. A user is `required?/1` (held at the invite
  interstitial, `/auth/invite-required`) when ALL of:

    * the gate is on — `enabled?/0`, i.e. the product is still invite-only
      (`FeatureFlags.general_release?/0` is false),
    * they are not a platform admin,
    * their status is `:pending`, `:waitlist` or `:unverified`.

  Redeeming an invite (`redeem/3`) or confirming the email of an
  `:unverified` account (`confirm_email/1`) flips it `:active`, which opens
  the gate. Every enforcement point calls `required?/1`:

    * `StarterWeb.Plugs.RequireInvite` — last plug of the authenticated REST
      pipeline (403 `invite_required`, small exempt list),
    * `StarterWeb.Hologram.Middleware.RequireAuth` — Hologram page renders and
      page commands (redirect to the interstitial),
    * `StarterWeb.UserSocket.connect/3`.

  `SSO_REQUIRE_INVITE` is not an access control and plays no part here.
  """

  import Ecto.Query, only: [from: 2]

  alias Starter.Repo
  alias Starter.Schema.Users.User, as: UserSchema

  @gated_statuses [:pending, :waitlist, :unverified]

  @message "Your account was created but needs an invite code. Redeem one to continue."
  @unverified_message "Your account was created. Confirm your email (or redeem an invite code) to continue."

  @doc """
  The single 403 body every gated REST surface answers with. One error code
  (`invite_required`) so every client routes to the one interstitial;
  `account_status` tells the page which copy to show.
  """
  def error_body(user \\ nil) do
    account_status = user |> status() |> to_string_or_nil()

    %{
      error: "invite_required",
      account_status: account_status,
      message: if(account_status == "unverified", do: @unverified_message, else: @message)
    }
  end

  @doc "True while the product is invite-only (general release flips it off)."
  def enabled?, do: not Starter.FeatureFlags.general_release?()

  @doc """
  Status for a brand-new account — the ONE rule every signup path uses:

    * a valid invite was supplied → `:active`,
    * the product is past invite-only (`enabled?/0` false) → `:active`,
    * SSO (`provider` given) on a domain auto-approving that provider →
      `:active`,
    * password signup (`provider` nil) on an auto-approve domain →
      `:unverified` (activated by `confirm_email/1`),
    * otherwise → `:pending` (held at the interstitial until an invite).
  """
  def signup_status(email, provider \\ nil, invite \\ nil) do
    cond do
      not is_nil(invite) -> :active
      not enabled?() -> :active
      provider -> if Starter.Auth.SSODomains.auto_approve?(email, provider), do: :active, else: :pending
      Starter.Auth.SSODomains.auto_approve_domain?(email) -> :unverified
      true -> :pending
    end
  end

  @doc """
  Post-signup side effect shared by every password signup path: an
  `:unverified` account is sent its confirmation link. Never fails the signup.
  """
  def after_signup(%{status: status, email: email}) when status in [:unverified, "unverified"] do
    frontend_url = Application.get_env(:starter, :frontend_url, "http://localhost:8080")

    with {:ok, %{encoded_key: key}} <- Starter.Auth.SmartTokenAuth.request_email_verification(email) do
      Starter.Auth.SmartTokenEmail.send_verification_email(email, "#{frontend_url}/auth/verify-email?token=#{key}")
    end

    :ok
  rescue
    _ -> :ok
  end

  def after_signup(_user), do: :ok

  @doc """
  Email confirmed: an `:unverified` account (password signup on an
  auto-approve domain) becomes `:active`. Other statuses are untouched — a
  confirmed email never substitutes for an invite on an invite-required
  domain.
  """
  def confirm_email(user_id) when is_binary(user_id) do
    from(u in UserSchema, where: u.id == ^user_id and u.status == :unverified)
    |> Repo.update_all(set: [status: :active, approved_at: DateTime.utc_now()])

    :ok
  end

  def confirm_email(_), do: :ok

  @doc "Statuses that are held at the invite interstitial."
  def gated_statuses, do: @gated_statuses

  @doc """
  True when this user must redeem an invite before using the app. Accepts a
  user schema row, a user id, or any map carrying the user's `:id` (versioned
  user entity, serialized Hologram user) — those are re-read so the decision
  always uses the stored status and admin flag. Anything else
  (service/anonymous principals) is not a user-invite concern.
  """
  def required?(%UserSchema{} = user) do
    enabled?() and user.admin != true and status(user) in @gated_statuses
  end

  def required?(%{id: id}) when is_binary(id), do: required?(id)

  def required?(user_id) when is_binary(user_id) do
    with {:ok, id} <- Ecto.UUID.cast(user_id),
         %UserSchema{} = user <- Repo.get(UserSchema, id) do
      required?(user)
    else
      _ -> false
    end
  end

  def required?(_), do: false

  defp status(%{status: status}) when is_atom(status), do: status

  defp status(%{status: status}) when is_binary(status) do
    Enum.find(@gated_statuses, &(Atom.to_string(&1) == status)) || :other
  end

  defp status(_), do: nil

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(atom), do: Atom.to_string(atom)

  @doc """
  Redeem a raw invite token for a signed-in user. Email-bound invites must
  match the user's email. On success the invite is consumed, membership is
  granted at the invite's role and a gated account flips `:active` (stamping
  `approved_at`) with `invite_token_id` recording which invite let them in —
  all in one transaction. Idempotent for members: an invite this user already
  redeemed consumes nothing.

  Returns `{:ok, invite}`, `{:error, :invalid_token}` (unknown, revoked,
  expired, or bound to another email) or `{:error, :invite_exhausted}`.
  """
  def redeem(user, raw_token, conn \\ nil)

  def redeem(%{id: user_id, email: email}, raw_token, conn) when is_binary(raw_token) do
    raw_token = String.trim(raw_token)

    # One bcrypt-verified lookup decides: a live-but-spent invite answers
    # "already used" off the found row (no second hash pass); the guarded
    # increment inside the transaction stays the atomic arbiter under races.
    case Starter.Organizations.find_live_invite_by_raw_token(raw_token, email) do
      {:ok, invite} ->
        if spent?(invite) do
          {:error, :invite_exhausted}
        else
          Repo.transaction(fn ->
            user = Repo.get!(UserSchema, user_id)

            with {:ok, _} <- Starter.Organizations.redeem_invite_for_user(invite, user, conn),
                 :ok <- grant_membership(invite, user.id),
                 {:ok, _} <- activate(user, invite) do
              invite
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)
        end

      {:error, :invalid_token} ->
        {:error, :invalid_token}
    end
  end

  def redeem(_, _, _), do: {:error, :invalid_token}

  defp spent?(%{max_uses: nil}), do: false
  defp spent?(%{uses: uses, max_uses: max_uses}), do: uses >= max_uses

  # Membership at the role the inviter chose; already being a member is
  # success, so a re-used link never downgrades anyone. `owner` is never
  # granted by an invite.
  defp grant_membership(%{organization_id: nil}, _user_id), do: :ok

  defp grant_membership(invite, user_id) do
    case Starter.Authz.authorize(user_id, "organization", invite.organization_id, "viewer") do
      {:ok, _} ->
        :ok

      {:error, _} ->
        case Starter.Authz.ScopedMemberships.add_member(
               "organization",
               invite.organization_id,
               user_id,
               invite_role(invite)
             ) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  defp invite_role(%{role: role}) when role in ~w(admin member viewer), do: role
  defp invite_role(_), do: "viewer"

  defp activate(%UserSchema{} = user, invite) do
    changes =
      if user.status in @gated_statuses do
        [
          status: :active,
          approved_at: user.approved_at || DateTime.utc_now(),
          invite_token_id: invite.id
        ]
      else
        [invite_token_id: user.invite_token_id || invite.id]
      end

    user |> Ecto.Changeset.change(changes) |> Repo.update()
  end

end
