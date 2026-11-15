#!/usr/bin/env bash
# The real-flow test: the real server image, recorded real Apple answers, the phone's own code
# and the web app in a real browser, end to end.
#
#   1. Start the image (IMAGE) and a fixture server that replays the recorded answers.
#   2. Web app: create the first admin through its first-run form.
#   3. Phone code: sign in, search Apple, subscribe, save a position through the outbox.
#   4. Web app: sign in and open that episode; it must show the phone's position.
#
#   IMAGE=ghcr.io/sc00tz/castaway:sha-abc1234 tests/real-flow/run.sh
#
# Needs Docker, Flutter (mobile/ dependencies fetched) and Node with Playwright's Chromium
# (cd tests/real-flow && npm ci && npx playwright install chromium).
set -euo pipefail

IMAGE=${IMAGE:?set IMAGE to the server image to test}
PORT=${PORT:-18090}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
NAME=castaway-real-flow-$$
NET=$NAME
SERVER=http://127.0.0.1:$PORT
USERNAME=realflow
PASSWORD=RealFlow-$RANDOM-Pass1
RESULT=$(mktemp)

cleanup() {
  status=$?
  if [ $status -ne 0 ]; then
    echo "--- server log"; docker logs "$NAME-server" 2>&1 | tail -80 || true
    echo "--- fixture log"; docker logs "$NAME-fixtures" 2>&1 | tail -40 || true
  fi
  docker rm -f "$NAME-server" "$NAME-fixtures" >/dev/null 2>&1 || true
  docker volume rm "$NAME-data" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -f "$RESULT"
  exit $status
}
trap cleanup EXIT

step() { echo; echo "=== $*"; }

step "Start the fixture server and the server image ($IMAGE)"
docker network create "$NET" >/dev/null
docker run -d --name "$NAME-fixtures" --network "$NET" --network-alias fixtures \
  -v "$HERE:/real-flow:ro" -e FIXTURE_BASE=http://fixtures:8000 \
  python:3.13-alpine python /real-flow/fixture_server.py >/dev/null
FIXTURE_IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$NAME-fixtures")
docker run -d --name "$NAME-server" --network "$NET" -p "127.0.0.1:$PORT:8040" \
  -v "$NAME-data:/data" \
  -e CASTAWAY_APPLE_URL=http://fixtures:8000 \
  -e ALLOWED_PRIVATE_NETWORKS="$FIXTURE_IP" \
  "$IMAGE" >/dev/null
for i in $(seq 1 120); do
  curl -sf "$SERVER/api/health" >/dev/null 2>&1 && break
  [ "$i" = 120 ] && { echo "the server never became healthy"; exit 1; }
  sleep 2
done
echo "server healthy at $SERVER"

step "Web app: create the first admin"
(cd "$HERE" && node web.mjs setup "$SERVER" "$USERNAME" "$PASSWORD")

step "Phone code: sign in, search Apple, subscribe, save a position"
(cd "$REPO/mobile" && \
  CASTAWAY_REAL_FLOW_SERVER=$SERVER CASTAWAY_REAL_FLOW_USERNAME=$USERNAME \
  CASTAWAY_REAL_FLOW_PASSWORD=$PASSWORD CASTAWAY_REAL_FLOW_OUT=$RESULT \
  flutter test test/real_flow/real_flow_test.dart --reporter expanded)
[ -s "$RESULT" ] || { echo "the phone step didn't run"; exit 1; }
cat "$RESULT"; echo

step "Web app: sign in and see the phone's position"
(cd "$HERE" && node web.mjs check "$SERVER" "$USERNAME" "$PASSWORD" "$RESULT")

step "Real flow passed"
