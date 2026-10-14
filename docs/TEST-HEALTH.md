# Test Health — hologram-start-app (template)
_Last measured: 2026-10-07 · branch develop@79cd4f1 (+ chore/ci-test-speed)_

This repo is the **Hologram scaffold template**: every default below is
inherited by apps hydrated from it (`init-proj-scaffold … --from
components/hologram-start-app`). Keep this file accurate after hydration.

| Metric | Before | After |
|---|---|---|
| CI PR wall-clock — critical path (warm / cold) | n/a — no workflows existed | see PR run (first run is cold) |
| Main release build (warm / cold) | n/a — no release job; template never releases | hydrated apps only (`build-push` gated on `test`) |
| CI acceptance test job (warm / cold) | n/a — suite never ran in CI | see PR run |
| Local full-suite runtime (uptime load) | 18.6s suite / 33s `mix test` (load 9) | 2.7s suite / 17s `mix test` (load 13) |
| Docker build (warm / cold) | broken standalone: no `vendor/` copy, no tobor-kit context | smoke build on PR/develop, gha cache |
| Tests in acceptance / slow tier | 60 / 0 | 68 / 0 (+8 repo-override dispatch tests, 2026-10-07; 18.5% local coverage, green on two seeds, fresh DB); 2026-10-08 invite interstitial: +24 `invite_gate_test` + 3 SSO register-open tests (gate files 54/54 locally; full suite verified by PR CI) |
| Async modules / total | 1 / 12 | 1 / 12 (ConnCase modules stay sync — see debt) |
| Coverage — acceptance pass | not measured | 16.7% |
| Coverage — full pass | = acceptance | = acceptance |
| Coverage gate | — | 11% (`mix.exs` `test_coverage` threshold, `mix test --cover` in CI) |

Local "before" already includes the `ecto.migrate` alias fix — without it the
suite cannot start on a fresh DB (Oban/SmartToken tables missing).

## Template defaults (fleet lessons baked in)

| Default | Where | Why |
|---|---|---|
| Job-level `MIX_ENV: test` | `ci.yml` `test` job | one `_build/test`; no dev+test double compile |
| sha-suffixed mix cache, split restore/save | `ci.yml` | exact-hit keys never re-save (`_build` drifts); save survives a red test step |
| `push: [main, develop]`, PR-only `cancel-in-progress` | `ci.yml` | develop seeds caches PRs can read; never cancel a release push |
| PRs restore caches only (mix `cache/save` guarded `github.event_name != 'pull_request'`) | `ci.yml` `test` | per-commit PR saves are unreadable by other PRs and churn the 10 GB/repo cache, evicting develop/nightly caches |
| Toolchain = `.tool-versions` = Dockerfile `BASE_IMAGE` | `ci.yml` setup-beam `version-file` + `strict`; `backend/Dockerfile` | CI, local and the release image compile on the same Elixir 1.20.1 / OTP 29 |
| `test` alias runs `ecto.migrate` | `backend/mix.exs` | Liquibase owns app schema; Oban + SmartToken tables come from Ecto migrations |
| bcrypt `log_rounds: 4` in test | `config/test.exs` | 18.6s → 2.7s (bcrypt was ~85% of the suite) |
| Provider-key stripping | `config/test.exs` (runs before `runtime.exs`) | a developer's shell key can never reach a live provider |
| Fixed-id seed rows committed once | `test/test_helper.exs`, before `Sandbox.mode(:manual)` | per-test `on_conflict: :nothing` upserts of uuid5 auth providers block concurrent sandboxes |
| Library-default `:uid_provider` | `noizu_labs_entities` 0.3.4 (`Noizu.Entity.UID.Default`); regression test `test/annotate/entity_uid_concurrency_test.exs` (50 concurrent creates: unique ids, each fetched back by id, all listed) | ≤ 0.3.1 shipped only the `{ms, 0}` stub, which collides on same-millisecond `id(:uuid)` inserts; 0.3.2 minted an uppercase uuid tail that did not round-trip through Postgres (fixed in 0.3.4, which also downcases legacy ids on parse); no app-level provider needed |
| sref handler warm-up | `test/test_helper.exs` (before `ExUnit.start`: `Annotate.EntityRepo.warm_sref_handlers()` + hard assert the `"user-session"` handler exists); `Annotate.Application.start/2` after the supervision tree is up (guarded: failure logs a warning, never fails boot) | a cold build `Code.ensure_loaded?`s every app module; on ≤ 0.3.3 callers racing it got `%{}` → `handler_not_found` → Guardian 401 (`no_resource_found`) in whichever async ConnCase landed in the window (seed-dependent), and right after a deploy. Scaffold default for new apps |
| Entity repo overrides call `super` | `backend/lib/annotate/entities/` — `Auth.Providers`, `Media`, `Users.Media`, `Versioned.{Descriptions,Names,Strings}`; regression test `test/annotate/entities/repo_override_dispatch_test.exs` | fixed 2026-10-07 (aifighter `fed51d1` shape). The template shipped self-dispatching overrides that every hydrated app inherited: `create/3` piped a built entity into `change/2` (`Protocol.UndefinedError` — `Credentials.register/4` raised on its first `Versioned.Strings` create), `update/4`'s `options \\ []` defined an `update/3` that shadowed the `def_repo` one (`FunctionClauseError`), `delete/3` called itself forever. Now: `%Entity{}`/changeset/attrs `create` clauses → `super`, `update/4` without a default, `delete` → `super`. The test covers all six (calls time-bounded to 5s) plus `Credentials.register/4`; `entity_uid_concurrency_test` races `Versioned.Names.Name` creates again instead of the `Organization` workaround |
| Invite gate router walk | `test/annotate_web/controllers/invite_gate_test.exs` | walks every `:authenticated` route (>40) as a `:pending` user and expects `403 invite_required`, except `RequireInvite.exempt_routes/0`; mutation-checked 2026-10-08 (dropping the plug from `AuthPipeline` fails it). New authenticated routes are covered automatically — keep the exempt list small |
| `mix test --cover` + threshold | `mix.exs` `test_coverage`, `ci.yml` | ratchet gate; Hologram 0.10.1 does not crash under `--cover` here |
| Release gated on backend tests | `build-push: needs: [test]`, no `continue-on-error` | never ship an image whose suite is red |
| Docker gha cache, exported off-PR only | `docker-build` (PR/develop), `build-push`, `nightly.yml` | PR-ref caches are unreadable elsewhere |
| tobor-kit as a named build context | `backend/Dockerfile`, `Makefile` `KIT_CONTEXT`, CI `build-contexts` | the `tobor_kit_hologram` path dep is a separate private repo |
| `nightly.yml` docker cache warmer | `.github/workflows/nightly.yml` | releases > 7 days apart otherwise build cold |

## Caching status
- GitHub Actions: deps ✅ · build ✅ (`_build/test`, sha-keyed) · npm n.a. (no frontend) · .next/cache n.a. · PLT n.a. (no dialyzer) · develop-ref seeding ✅ · Liquibase CLI ✅
- Docker: buildx gha cache ✅ (scope `backend`; verify `CACHED` lines on the first warm develop run) · cache mounts ✅ (hex/rebar; local builders only) · .dockerignore ✅ · release-cache warmer ✅ (inert until on the default branch, `main`)

## Slow tests (tier: nightly)
None — the full suite runs in ~3s.

| Test | Time | Why slow | Fix idea |
|---|---|---|---|

## Test debt
| Item | Kind | Notes |
|---|---|---|
| ConnCase modules (`auth_controller_test`, `user_controller_test`, …) | sync-only | token auth goes through cache layers outside the sandbox — fleet rule: keep token-authenticated ConnCase sync |
| `sso_test`, `invites_test` | sync-only | `Application.put_env(:annotate, :sso_domain_policies, …)` global fixture |
| Hologram pages/components | coverage gap | no page tests; 16.7% total. If a page test crashes under `--cover` (`Hologram.Reflection.beam_defs/1`, seen on other 0.10.x apps), drop `--cover` in CI and record it here |
| `mix format --check-formatted` | not gated | ~25 lib/test files are unformatted on develop; CI has no format step until they're formatted in a dedicated PR |
| `Users.Media` `media_type` enum drift | resolved | Ecto enum aligned to the DB's `media_type_enum` (`image/video/audio/document/other`) — `:profile/:cover/:gallery` were never storable. Dispatch test now uses `:image` (fix/media-type-enum). |
| Compile-env change after restoring an old `_build` | ops note | the noizu_labs_entities 0.3.2/0.3.4 bumps (and dropping the app `:uid_provider`) change its compile env; if a stale `_build` fails "could not compile dependency", run `mix deps.compile noizu_labs_entities --force` once (the mix.lock hash in the CI key avoids it) |

## Nightly
`.github/workflows/nightly.yml` — `23 7 * * *` + `workflow_dispatch`, docker cache
warmer only (no slow tier to run). Inert in the template repo until it reaches
the default branch (`main`).

## CI secrets (inherited by hydrated apps)
- `TRR_GITHUB_APP_ID` / `TRR_GITHUB_APP_PRIVATE_KEY` — GitHub App token to check
  out the private `tobor-kit` repo (test, docker-build, build-push, nightly).
- `REGISTRY_USER` / `REGISTRY_PASSWORD` — `ops.noizu.com` push (release only).
