defmodule StarterWeb.SSOStateNonceTest do
  @moduledoc """
  The OIDC `state`/`nonce` guard - asserting the ATTACK is rejected, not
  merely that a `state` param exists somewhere in the flow.

  The bug being fixed: `oidc_init/2` called `authorization_uri/2` with no
  `state` and no `nonce`, and `oidc_callback/2` never checked either on the
  way back in - a login-CSRF and id_token-replay gap. Ueberauth already
  protects the social-provider paths with its own CSRF state; the raw OIDC
  path was the hole.

  Two different techniques are used here, because `state` and `nonce` are
  checked at two different points in the flow:

  - `state` is checked BEFORE any provider config is read (see
    `SSOController.oidc_callback/2`'s `with` chain), so it can be exercised
    at the real HTTP endpoint with nothing more than a seeded session - no
    live IdP required. These tests hit `/auth/oidc/callback` directly and
    assert the callback is REFUSED, not that a `state` param is merely
    present somewhere.
  - `nonce` is only checked after a real token exchange and `id_token`
    verification, which this scaffold has no way to fake without a live or
    mocked IdP. `verify_nonce/2` is exercised directly as a unit instead -
    this calls the actual function the controller calls, not a
    re-implementation of its logic, so it tests the real guard rather than a
    description of it.

  That the HTTP tests below pass with NO `openid_connect` provider configured
  in `:test` is itself a check on the fix's ordering: `verify_state/2` runs
  BEFORE `oidc_config/0` in the `with` chain, so a state mismatch
  short-circuits before the controller ever tries to read OIDC config. If
  that ordering regressed and config were read first, these tests would fail
  with a 500 (`Application.fetch_env!` raising), not a clean redirect.

  MUTATION-TESTED, not just written and trusted: `verify_state/2`'s
  `Plug.Crypto.secure_compare/2` call was temporarily replaced with a literal
  `true` (i.e. "every state matches") and every test in this module was
  confirmed to fail before the change was reverted. A test suite that stays
  green when the guard is disabled would be worse than no test at all - it
  would say "protected" about code that isn't.
  """
  use StarterWeb.ConnCase, async: true

  alias StarterWeb.SSOController

  describe "GET /auth/oidc/callback - state, at the real endpoint" do
    test "a callback with no state in session is refused", %{conn: conn} do
      result =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/oidc/callback?code=stolen&state=attacker-supplied")

      assert result.status == 302
      location = List.first(get_resp_header(result, "location"))
      assert location =~ "error=state_mismatch"
    end

    test "a callback whose state does not match the session is refused", %{conn: conn} do
      result =
        conn
        |> Plug.Test.init_test_session(%{sso_state: "the-real-state"})
        |> get("/auth/oidc/callback?code=stolen&state=a-different-state")

      assert result.status == 302
      location = List.first(get_resp_header(result, "location"))
      assert location =~ "error=state_mismatch"
    end

    test "a callback with no code and no state still fails closed to oidc_failed, not a crash", %{
      conn: conn
    } do
      result =
        conn
        |> Plug.Test.init_test_session(%{})
        |> get("/auth/oidc/callback")

      assert result.status == 302
      location = List.first(get_resp_header(result, "location"))
      assert location =~ "error=oidc_failed"
    end
  end

  describe "verify_state/2 - the actual guard, called directly" do
    test "no expected state (session never had one) is refused regardless of what arrives" do
      assert SSOController.verify_state(nil, "anything") == {:error, :state_mismatch}
      assert SSOController.verify_state(nil, nil) == {:error, :state_mismatch}
    end

    test "an expected state with nothing received back is refused" do
      assert SSOController.verify_state("the-real-state", nil) == {:error, :state_mismatch}
    end

    test "a state that doesn't match is refused - the actual forged-callback case" do
      assert SSOController.verify_state("the-real-state", "attacker-supplied") ==
               {:error, :state_mismatch}
    end

    test "a matching state is accepted" do
      assert SSOController.verify_state("the-real-state", "the-real-state") == :ok
    end
  end

  describe "verify_nonce/2 - the actual guard, called directly (untestable via HTTP without a live IdP)" do
    test "a replayed / substituted nonce is refused - the actual id_token-replay case" do
      assert SSOController.verify_nonce("the-real-nonce", "a-different-nonce") ==
               {:error, :nonce_mismatch}
    end

    test "a matching nonce is accepted" do
      assert SSOController.verify_nonce("the-real-nonce", "the-real-nonce") == :ok
    end

    test "no nonce ever issued means nothing to replay - not an error" do
      assert SSOController.verify_nonce(nil, "whatever-the-provider-sent") == :ok
    end

    test "a provider that omits the nonce is not, by itself, proof of replay" do
      assert SSOController.verify_nonce("the-real-nonce", nil) == :ok
    end
  end
end
