# Test Health — annotate.therobotlives.com
_Written 2026-10-17 from a read of `develop` @ `2b5819d`. Suite was **not re-run** for this document; timing and coverage figures are the last values recorded elsewhere in the repo and are marked as such._

## Snapshot

| Metric | Value | Source |
|---|---|---|
| Full backend suite | 261 tests green at PR #33 (2026-10-17) | `CHANGELOG.md` 2026-10-17 |
| Annotate-specific tests | 119 `test` blocks (90 in `test/annotate_web/controllers/annotate_api/`, 29 in `test/annotate_web/channels/`) | counted with grep, 2026-10-17 |
| Coverage | **unknown / unmeasured here**; the last recorded figure (16.7%, 2026-10-07) predates all annotate code | previous TEST-HEALTH |
| Coverage gate | 11% (`mix.exs` `test_coverage: [summary: [threshold: 11]]`) | `backend/mix.exs` |
| Local suite runtime | ~3 s reported for the scaffold-era suite; not re-measured with the annotate tests | previous TEST-HEALTH |
| CI | `.github/workflows/ci.yml` (PR + `develop`/`main` push) and `nightly.yml` (`23 7 * * *`, docker cache warmer only) | repo |

## What is covered (annotate product path)

| Area | Test files | Notes |
|---|---|---|
| Comments / threads | `comments_test.exs` (13), `site_threads_test.exs` (14) | tenancy scoping, anonymous opt-in, attachment binding |
| Attachments | `attachment_test.exs` (9) | presign validation, uploader-only complete |
| Token binding | `token_binding_test.exs` (9) | site/origin claim enforcement, missing-Origin writes |
| CORS | `cors_test.exs` (8) | per-site exact-match, preflight, foreign origin 403 |
| Embed auth broker | `embed_auth_test.exs` (19) | state/nonce, IdP error legs, crash -> `auth_failed`, cookie attributes, `fetch_tokens` map contract (regression for the 2026-10-16 prod 500) |
| Host-assert | `host_assert_test.exs` (12) | signature, `exp` window, policy |
| Rate limiting | `rate_limit_test.exs` (6) | per ip+site buckets |
| Websocket | `annotate_socket_test.exs` (19), `page_channel_test.exs` (10) | origin gate, token handling, read-only channel, join auth |
| Realtime broadcast | `test/annotate/realtime_test.exs` | payload parity with REST renderer |
| Landing | `marketing_landing_test.exs` | host split + CSP |

Inherited scaffold tests (auth, invites, SSO, orgs, entities, observability) also run; the invite gate router walk (`invite_gate_test.exs`) covers every `:authenticated` route automatically.

## Gaps (ordered by risk)

| Gap | Why it matters | Related threat |
|---|---|---|
| No test for refresh-token reuse, concurrent rotation or origin handling on refresh | rotation is non-atomic; origin comes from the request header | THREAT-MODEL T-01, T-02 |
| No test of `Annotate.Auth.RefreshTokens` / `ServiceKey` / `Policy` as units (only via controllers) | crypto and policy regressions surface late | T-05, T-10 |
| No test that resolve/reopen/re-anchor reject non-authors (current behaviour allows) | undecided product rule | T-06 |
| No test for `</script>` / hostile `display_name` in `/embed/callback` | inline-script injection | T-07 |
| No upload content tests (size mismatch, sniffing, orphan sweep deleting objects) | declared `bytes`/type unverified | T-04, T-08 |
| No socket test for token expiry mid-connection | socket outlives token | T-09 |
| Widget-side rendering (markdown escape, `avatar_url`) is untested here - the code lives in tobor-kit | stored XSS | T-13 |
| Hologram pages/components have no page tests beyond the landing | low coverage | - |
| End-to-end through a real browser + Authentik popup | only `Annotate.Embed.OIDC` fakes exercise the broker; the real `OpenIDConnect` contract broke in prod once. A live round trip belongs in the e2e lane | - |

## Test debt

| Item | Kind | Notes |
|---|---|---|
| ConnCase modules with token auth | sync-only | token auth goes through cache layers outside the sandbox |
| `sso_test`, `invites_test` | sync-only | global `Application.put_env(:annotate, :sso_domain_policies, ...)` |
| `mix format --check-formatted` | not gated | ~25 files unformatted on develop as of 2026-10-07 (not re-counted) |
| Hammer ETS limiter state | isolation | `rate_limit_test.exs` relies on per-test unique keys/IPs; global ETS state is shared across tests (**unverified** - check before making the module async) |
| Stale `_build` after compile-env change | ops note | if a restored `_build` fails "could not compile dependency", run `mix deps.compile noizu_labs_entities --force` once |

## CI / build facts (verified in repo)

- Test alias runs `ecto.create -> liquibase.update -> ecto.migrate -> test`: Liquibase owns the schema, Ecto migrations add Oban/SmartToken tables (`mix.exs` aliases, `lib/mix/tasks/liquibase.update.ex`, `ci.yml` Liquibase steps).
- `config/test.exs` enables the Hologram runtime (`HOLOGRAM_START=1`) and the test alias runs `mix holo.sync_assets` first, otherwise the landing 404s/500s (PR #27).
- Toolchain pinned by `.tool-versions` (Elixir 1.20.1 / OTP 29) shared by CI and the Dockerfile.
- Release job (`build-push`) is gated on the `test` job; CI commits the Helm tag bump.
- Branch CI split (what `stage` runs beyond `develop`) was not verified in this pass.

## CI secrets
- `TRR_GITHUB_APP_ID` / `TRR_GITHUB_APP_PRIVATE_KEY` - GitHub App token to check out the private `tobor-kit` repo.
- `REGISTRY_USER` / `REGISTRY_PASSWORD` - image registry push (release only).
