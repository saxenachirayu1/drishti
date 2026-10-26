#!/usr/bin/env bash
# Drishti - run the whole thing locally, with no credentials.
#
#   ./run-demo.sh
#
# Starts Member C's API, and the Flutter web dashboard if Flutter is installed,
# with the app pointed at the local API. Everything runs offline: an in-memory
# database, template complaint drafting and console "email", so a reviewer can
# clone the repo and see it work without a single key.
#
# With credentials in api/.env it uses them instead - Supabase for data,
# watsonx for Granite drafting, Resend for real email - with no code change.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_PORT="${API_PORT:-8000}"
WEB_PORT="${WEB_PORT:-5173}"
PYTHON="${PYTHON:-python3}"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  [[ -n "${API_PID:-}" ]] && kill "$API_PID" 2>/dev/null || true
  [[ -n "${WEB_PID:-}" ]] && kill "$WEB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- API ---------------------------------------------------------------
say "Setting up the API"
cd "$ROOT/api"
[[ -d .venv ]] || "$PYTHON" -m venv .venv
./.venv/bin/pip install -q -r requirements.txt

say "Running the test suite"
RUN_SCHEDULER=0 ./.venv/bin/python -m pytest -q

say "Starting the API on :$API_PORT"
./.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "$API_PORT" &
API_PID=$!

for _ in $(seq 1 60); do
  curl -sf "http://127.0.0.1:$API_PORT/health" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:$API_PORT/health" >/dev/null 2>&1 \
  || die "the API did not come up on :$API_PORT"

curl -s "http://127.0.0.1:$API_PORT/health" \
  | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print("  db:", d["db"], "| granite:", d["granite"], "| auth:", d["auth"])'

# --- web dashboard (optional) -----------------------------------------
if command -v flutter >/dev/null 2>&1; then
  say "Building the web dashboard, pointed at the local API"
  cd "$ROOT/app"
  flutter pub get >/dev/null
  flutter build web --release \
    --dart-define=API_BASE_URL="http://127.0.0.1:$API_PORT" >/dev/null
  say "Serving the dashboard on :$WEB_PORT"
  (cd build/web && "$ROOT/api/.venv/bin/python" -m http.server "$WEB_PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
  WEB_PID=$!
  WEB_LINE="  dashboard: http://127.0.0.1:$WEB_PORT"
else
  WEB_LINE="  dashboard: install Flutter and re-run to build it (the API runs without it)"
fi

cat <<EOF

$(printf '\033[1mDrishti is running\033[0m')

  API docs:  http://127.0.0.1:$API_PORT/docs
$WEB_LINE

Try the flow on /docs:
  GET  /sites                        3 seeded sites, each mapped to its ward
  POST /complaints {"site_id":"site-1"}
                                     drafts a complaint citing the SWM Rules
  POST /complaints/{id}/approve      locks it and writes a PDF to api/out/
  POST /complaints/{id}/send         emails the ward officer (console here)
  POST /assistant/chat {"message":"which wards have dumps near the river?"}
  GET  /cities/indore/score          the 0-100 score with its parts

  Add "language":"Hindi" to a complaint for a Hindi letter and PDF.
  Admin-only routes need DEV_ROLE=admin ./run-demo.sh

Press Ctrl+C to stop.
EOF

wait "$API_PID"
