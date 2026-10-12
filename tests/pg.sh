#!/usr/bin/env bash
# Canopy OS tests · local PostgreSQL helper.
#   source tests/pg.sh            -> exports PGHOST/PGPORT/PGUSER for a throwaway local cluster
#   tests/pg.sh start|stop|status
# In CI (or when PGHOST is already set) it does nothing: the provided server is used.
# The cluster lives outside the repository and holds only test data.
set -euo pipefail

CANOPY_PG_DIR="${CANOPY_PG_DIR:-/tmp/canopy-test-pg}"
CANOPY_PG_PORT="${CANOPY_PG_PORT:-55432}"

_pgbin() {
  if [ -n "${PG_BIN:-}" ]; then echo "$PG_BIN"; return; fi
  for v in 18 17 16 15; do
    if [ -x "/usr/lib/postgresql/$v/bin/pg_ctl" ]; then echo "/usr/lib/postgresql/$v/bin"; return; fi
  done
  dirname "$(command -v pg_ctl)"
}

_as_pg() {  # initdb/pg_ctl refuse to run as root
  if [ "$(id -u)" = "0" ]; then runuser -u postgres -- "$@"; else "$@"; fi
}

canopy_pg_start() {
  local bin; bin="$(_pgbin)"
  if [ ! -d "$CANOPY_PG_DIR/data" ]; then
    mkdir -p "$CANOPY_PG_DIR"
    [ "$(id -u)" = "0" ] && chown postgres "$CANOPY_PG_DIR"
    _as_pg "$bin/initdb" -D "$CANOPY_PG_DIR/data" -U postgres -A trust --locale=C.UTF-8 -E UTF8 >/dev/null
    cat >> "$CANOPY_PG_DIR/data/postgresql.conf" <<EOF
port = $CANOPY_PG_PORT
listen_addresses = '127.0.0.1'
unix_socket_directories = '$CANOPY_PG_DIR'
timezone = 'UTC'
fsync = off
synchronous_commit = off
full_page_writes = off
EOF
  fi
  if ! _as_pg "$bin/pg_ctl" -D "$CANOPY_PG_DIR/data" status >/dev/null 2>&1; then
    _as_pg "$bin/pg_ctl" -D "$CANOPY_PG_DIR/data" -l "$CANOPY_PG_DIR/server.log" -w start >/dev/null
  fi
}

canopy_pg_stop() {
  local bin; bin="$(_pgbin)"
  _as_pg "$bin/pg_ctl" -D "$CANOPY_PG_DIR/data" -m fast stop >/dev/null 2>&1 || true
}

if [ -z "${PGHOST:-}" ]; then
  export PGHOST="127.0.0.1" PGPORT="$CANOPY_PG_PORT" PGUSER="postgres"
  CANOPY_PG_LOCAL=1
fi
export PGOPTIONS="${PGOPTIONS:---client-min-messages=warning}"

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-status}" in
    start) canopy_pg_start; echo "PostgreSQL test cluster on $PGHOST:$PGPORT";;
    stop) canopy_pg_stop;;
    status) _as_pg "$(_pgbin)/pg_ctl" -D "$CANOPY_PG_DIR/data" status || true;;
  esac
elif [ -n "${CANOPY_PG_LOCAL:-}" ]; then
  canopy_pg_start
fi
