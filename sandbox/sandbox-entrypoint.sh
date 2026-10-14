#!/usr/bin/env bash
set -uo pipefail

# When called without arguments, seed workspace + launch supervisor.
# When called with "backend", run mix holo (used by supervisor).

case "${1:-}" in
  backend)
    export HOME=/home/dev
    export MIX_HOME=/home/dev/.mix
    export HEX_HOME=/home/dev/.hex
    cd /workspace/backend
    if [ ! -f mix.exs ]; then
      echo "[sandbox:backend] No mix.exs — waiting for source files..."
      while [ ! -f mix.exs ]; do sleep 2; done
    fi
    export MIX_ENV=dev
    export HOLOGRAM_START=1
    export PHX_SERVER=true
    export PHX_IP=0.0.0.0
    mix local.hex --force --if-missing
    mix local.rebar --force --if-missing
    mix deps.get
    mix ecto.create 2>/dev/null || true
    mix ecto.migrate 2>/dev/null || true
    exec mix holo
    ;;

  *)
    mkdir -p /workspace/backend /workspace/assets

    if [ -d /seed/backend ] && [ ! -f /workspace/backend/mix.exs ]; then
      echo "[sandbox] Seeding backend source..."
      cp -a /seed/backend/. /workspace/backend/
    fi
    if [ -d /seed/assets ] && [ ! -d /workspace/assets/theme-style-guide ]; then
      echo "[sandbox] Seeding theme assets..."
      cp -a /seed/assets/. /workspace/assets/
    fi
    chown -R dev:dev /workspace

    mkdir -p /var/log/samba /var/log/supervisor

    /usr/bin/supervisord -c /etc/supervisor/conf.d/sandbox.conf &
    SUPERVISOR_PID=$!
    sleep 2

    if [ -f /workspace/backend/mix.exs ]; then
      supervisorctl -c /etc/supervisor/conf.d/sandbox.conf start backend
    else
      echo "[sandbox] No backend source found — mount files via Samba, then run: supervisorctl start backend"
    fi

    echo "[sandbox] Ready. Samba share at //container:445/workspace (user: dev / pass: dev)"
    echo "[sandbox] Hologram app: http://localhost:4000"
    wait $SUPERVISOR_PID
    ;;
esac
