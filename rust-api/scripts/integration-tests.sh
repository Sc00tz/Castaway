#!/usr/bin/env bash
# Run the rust-api integration suite (tests/integration) against a real PostgreSQL database.
#
#   scripts/integration-tests.sh                 # all tests
#   scripts/integration-tests.sh -- queue        # extra args go to `cargo test` (name filter, etc.)
#   scripts/integration-tests.sh --gpodder mock -- gpodder
#                                                # gpodder protocol tests against rust | mock
#                                                # (default rust)
#   scripts/integration-tests.sh down            # stop the throwaway containers
#
# Containers come from tests/docker-compose.yml (off-default ports, tmpfs data). The template
# database is built by the server's own migrations (rust-api/migrations).
set -euo pipefail

API_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$API_DIR/tests/docker-compose.yml")

if [[ "${1:-}" == "down" ]]; then
  "${COMPOSE[@]}" down -v
  exit 0
fi

CARGO_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpodder)
      case "${2:-}" in
        rust|mock) export CASTAWAY_TEST_GPODDER="$2" ;;
        *) echo "unknown --gpodder '${2:-}' (rust | mock)" >&2; exit 2 ;;
      esac
      shift 2 ;;
    --) shift; CARGO_ARGS+=("$@"); break ;;
    *) CARGO_ARGS+=("$1"); shift ;;
  esac
done

# Containers are only started if the caller hasn't pointed us at their own (CI uses services).
if [[ -z "${CASTAWAY_TEST_EXTERNAL_SERVICES:-}" ]]; then
  "${COMPOSE[@]}" up -d --wait
fi

# Backup tests run the real dump tools. Where they aren't installed, run the ones in the test
# containers instead, translating addresses and output files.
install_db_tool_shims() {
  local dir="$API_DIR/target/db-tools" compose_file="$API_DIR/tests/docker-compose.yml"
  mkdir -p "$dir"
  local tool service binary
  for tool in pg_dump psql; do
    command -v "$tool" >/dev/null && continue
    service=postgres binary=$tool
    cat > "$dir/$tool" <<SHIM
#!/usr/bin/env bash
args=(); out=""; prev=""
for a in "\$@"; do
  case "\$prev" in
    -h|--host) args+=("127.0.0.1"); prev=""; continue ;;
    -p|--port) args+=("5432"); prev=""; continue ;;
    -f) out="\$a"; args=("\${args[@]:0:\${#args[@]}-1}"); prev=""; continue ;;
  esac
  args+=("\$a"); prev="\$a"
done
run=(docker compose -f "$compose_file" exec -T -e "PGPASSWORD=\${PGPASSWORD:-}" "$service" "$binary" "\${args[@]}")
case "$tool" in
  pg_dump) exec </dev/null ;;
esac
if [[ -n "\$out" ]]; then "\${run[@]}" > "\$out"; else "\${run[@]}"; fi
SHIM
    chmod +x "$dir/$tool"
  done
  export PATH="$PATH:$dir"
}
if [[ -z "${CASTAWAY_TEST_EXTERNAL_SERVICES:-}" ]]; then
  install_db_tool_shims
fi

cd "$API_DIR"
exec cargo test --test integration ${CARGO_ARGS[@]+"${CARGO_ARGS[@]}"}
