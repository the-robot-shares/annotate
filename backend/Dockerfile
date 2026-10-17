# syntax=docker/dockerfile:1.7
# Keep in lockstep with .tool-versions (CI reads it via setup-beam version-file).
ARG BASE_IMAGE="elixir:1.20.1-otp-29-slim"

FROM ${BASE_IMAGE} AS build

# Node 20+ required by the Hologram compiler (Elixir → JS bundles)
RUN apt-get update -y && \
    apt-get install -y build-essential git curl ca-certificates && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cross-arch emulation (QEMU / Rosetta) breaks BEAM's double-mapped RWX JIT
# pages and can corrupt compiler state during mix deps.compile.
ENV ERL_AFLAGS="+JMsingle true"

# Keep emulated builds below the scheduler/RSS cliff.
ENV ERL_FLAGS="+S 2:2"
ENV ELIXIR_ERL_OPTIONS="+S 2:2"

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Path deps must exist before `mix deps.get`:
#   * vendor/uuid_shim — the :uuid override (see mix.exs)
#   * tobor_kit_hologram — lives in a separate repo (tobor-kit/hologram), so it
#     arrives as a NAMED build context. mix.exs walks up from /app and finds it
#     at /Portfolio/Libs/tobor-kit/hologram:
#       docker build --build-context tobor_kit_hologram=<tobor-kit>/hologram .
COPY vendor vendor
COPY --from=tobor_kit_hologram mix.exs mix.lock /Portfolio/Libs/tobor-kit/hologram/
COPY --from=tobor_kit_hologram lib /Portfolio/Libs/tobor-kit/hologram/lib
COPY --from=tobor_kit_hologram priv /Portfolio/Libs/tobor-kit/hologram/priv
# The dep's own :hologram compiler looks for hologram's JS assets under ITS
# deps path; point that at ours. Fail fast if the context is missing.
RUN test -f /Portfolio/Libs/tobor-kit/hologram/mix.exs || { \
      echo "tobor_kit_hologram build context missing: pass --build-context tobor_kit_hologram=<tobor-kit>/hologram" >&2; exit 1; } && \
    ln -s /app/deps /Portfolio/Libs/tobor-kit/hologram/deps
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.cache/rebar3 \
    mix deps.get --only $MIX_ENV && \
    mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.cache/rebar3 \
    MIX_OS_DEPS_COMPILE_PARTITION_COUNT=1 mix deps.compile

COPY lib lib
COPY priv priv

RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.cache/rebar3 \
    mix compile

COPY config/runtime.exs config/

RUN mix release

# Hologram's bundler hardcodes --sourcemap --sources-content=true: every
# build emits .js.map files whose sourcesContent embed builder-absolute
# paths (macOS /Users/..., CI /home/runner/..., this container /app/...).
# Strip them from the release tree; the image ships bundled JS only.
RUN find _build/${MIX_ENV}/rel -name '*.js.map' -delete

FROM ${BASE_IMAGE} AS production

# CA bundle for outbound TLS. Without it, OTP's :pubkey_os_cacerts finds no
# system roots and :httpc (Tesla's default adapter, used by oauth2/ueberauth
# for the GitHub code→token exchange) crashes with FunctionClauseError
# conv_error_reason(:no_cacerts_found) → /auth/github/callback 500
# (prod incident 2026-10-17). Deps that bundle certs (hackney/certifi,
# Req/castore) never noticed the gap.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod

# Hologram.env/0 reads HOLOGRAM_ENV || MIX_ENV at RUNTIME and falls back to
# :dev when neither is set (true in a mix release) — which disables the
# Hologram router and 404s every page. Pin the env explicitly.
ENV HOLOGRAM_ENV=prod

COPY --from=build --chown=nobody:root /app/_build/${MIX_ENV}/rel/annotate ./

USER nobody

EXPOSE 4000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:4000/health || exit 1

CMD ["bin/annotate", "start"]
