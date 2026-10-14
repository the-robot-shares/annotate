defmodule StarterWeb.SSOInviteStashTest do
  @moduledoc """
  Regression test for the Ueberauth invite-stash plug ordering.

  The bug: `stash_invite_token/2` was called in the `oauth_request/2` ACTION
  body, but `plug Ueberauth` HALTS on the request phase — its strategies
  call `redirect!/2` (Ueberauth.Strategies.Helpers), which `send_resp`s a 302
  and `halt`s the plug pipeline BEFORE Phoenix dispatches the action. The
  action body never executed on the request phase, so `?invite=` on
  /auth/github (or /auth/google, ...) was silently dropped: the invite never
  reached the IdP round-trip and invited SSO registrations bounced off the
  fail-closed gate as if uninvited.

  The fix: the stash runs in `plug :prepare_oauth`, declared BEFORE
  `plug Ueberauth`. This module exercises the REAL request phase — provider
  config is pushed in (config/test.exs compiles `providers: []`, and
  `plug_init_mode: :runtime` means the plug reads it per-dispatch), the
  request is dispatched at the real route, and the assertions check BOTH the
  302 to GitHub's authorize URL (proving the halting path ran) AND the invite
  sitting in the session (proving the stash ran before it).

  A stash placed after the halt — the original shape — fails BOTH invites
  assertions here: with the action body unreachable, nothing stashed the
  token. (Verified by mutation: reverting the stash to the action body makes
  `invite survives the redirecting request phase` fail.)
  """

  use StarterWeb.ConnCase, async: false

  @invite "regression_invite_raw_token_123"

  setup do
    original_providers = Application.get_env(:ueberauth, Ueberauth)
    original_oauth = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth)

    Application.put_env(:ueberauth, Ueberauth,
      providers: [github: {Ueberauth.Strategy.Github, []}]
    )

    Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth,
      client_id: "test-client-id",
      client_secret: "test-client-secret"
    )

    on_exit(fn ->
      original_providers ||
        Application.delete_env(:ueberauth, Ueberauth)
      Application.put_env(:ueberauth, Ueberauth, original_providers)

      if original_oauth do
        Application.put_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, original_oauth)
      else
        Application.delete_env(:ueberauth, Ueberauth.Strategy.Github.OAuth)
      end
    end)

    :ok
  end

  test "invite survives the redirecting request phase" do
    conn = build_conn() |> get("/auth/github?invite=" <> URI.encode_www_form(@invite))

    # The halting request phase ran: a 302 to GitHub's authorize URL.
    assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
    # And the invite was stashed BEFORE the halt — the bug dropped it here.
    assert get_session(conn, :sso_invite_token) == @invite
  end

  test "request phase without an invite stashes nothing" do
    conn = build_conn() |> get("/auth/github")

    assert redirected_to(conn) =~ "github.com/login/oauth/authorize"
    refute get_session(conn, :sso_invite_token)
  end
end
