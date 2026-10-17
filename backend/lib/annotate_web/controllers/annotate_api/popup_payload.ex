defmodule AnnotateWeb.AnnotateAPI.PopupPayload do
  @moduledoc """
  The popup broker's postMessage contract (docs/EMBED-AUTH.md "Popup
  postMessage contract"), shared by `/embed/callback` and the dev-only
  `/embed/dev-login`.

  Success: `{type: "annotate-auth", access_token, refresh_token, expires_at,
  commenter, display_name}` plus the legacy aliases `access` / `refresh`
  (Phase 1a names, kept for old embedders). `expires_at` is the access
  token's expiry in **milliseconds** since the epoch.

  Error: `{type: "annotate-auth-error", error, reason}` (`reason` = legacy
  alias of `error`).

  The tobor-kit widget (`AnnotateAuth.onMessage`) reads `access_token` /
  `refresh_token` / `expires_at` / `error`; the server shipped only the
  legacy names until 2026-10-17, so widget popup sign-in never completed.
  `popup_payload_test.exs` pins the key set.
  """

  alias Annotate.Auth.ApiToken

  def success(access, refresh, commenter) do
    %{
      "type" => "annotate-auth",
      "access_token" => access,
      "refresh_token" => refresh,
      "expires_at" => expires_at_ms(access),
      "access" => access,
      "refresh" => refresh,
      "commenter" => commenter.id,
      "display_name" => commenter.display_name
    }
  end

  def error(reason) when is_binary(reason),
    do: %{"type" => "annotate-auth-error", "error" => reason, "reason" => reason}

  defp expires_at_ms(access) do
    case ApiToken.verify(access) do
      {:ok, %{"exp" => exp}} when is_integer(exp) -> exp * 1000
      _ -> nil
    end
  end
end
