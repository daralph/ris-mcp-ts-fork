#!/usr/bin/env bash
#
# Smoke test for the fork container image.
#
# Usage: smoke-test.sh <image>
#
# Verifies against a locally started container:
#   1. GET /health answers 200 within 30s (stateless mode, hardened flags).
#   2. POST /mcp answers initialize and tools/list with exactly 13 tools
#      (SSE "data: {...}" lines and plain JSON responses are both accepted).
#   3. With MCP_AUTH_TOKEN set, /mcp rejects a missing token with 401 and
#      accepts "Authorization: Bearer <token>" with 200.
#
# Exits 0 only if every step passes; on failure the last 30 container log
# lines are printed. The container is always removed (trap on EXIT).

set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image>}"
PORT="${SMOKE_PORT:-13000}"
NAME="ris-mcp-smoke-$$"
BASE="http://127.0.0.1:${PORT}"
HEADERS=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
INIT_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}'
LIST_BODY='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  echo '--- last 30 container log lines ---' >&2
  docker logs "$NAME" 2>&1 | tail -n 30 >&2 || true
  exit 1
}

start_container() {
  docker run -d --name "$NAME" \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    -e MCP_STATELESS=true "$@" \
    -p "127.0.0.1:${PORT}:3000" \
    "$IMAGE" >/dev/null
}

wait_healthy() {
  local code=''
  for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health" || true)
    [ "$code" = '200' ] && return 0
    sleep 1
  done
  fail "GET /health did not return 200 within 30s (last status: ${code:-none})"
}

# Count result.tools in an MCP response body, whether it arrives as a plain
# JSON document or as an SSE stream of "data: {...}" lines (last one wins).
count_tools() {
  node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => (raw += chunk)).on("end", () => {
      const sse = raw.split("\n").filter((line) => line.startsWith("data: ")).pop();
      const payload = JSON.parse(sse ? sse.slice(6) : raw);
      const tools = payload.result && payload.result.tools;
      if (!Array.isArray(tools)) {
        console.error("response carries no result.tools array");
        process.exit(1);
      }
      console.log(tools.length);
    });
  '
}

echo "==> Starting $IMAGE (stateless, read-only)"
start_container

echo '==> Waiting for /health'
wait_healthy
echo '    /health is 200'

echo '==> initialize'
code=$(curl -s -o /dev/null -w '%{http_code}' "${HEADERS[@]}" -d "$INIT_BODY" "$BASE/mcp")
[ "$code" = '200' ] || fail "initialize returned HTTP $code"

echo '==> tools/list (expect 13 tools)'
body=$(curl -s "${HEADERS[@]}" -d "$LIST_BODY" "$BASE/mcp")
tools=$(printf '%s' "$body" | count_tools) || fail 'tools/list response not parseable'
[ "$tools" = '13' ] || fail "expected 13 tools, got $tools"
echo '    13 tools registered'

echo '==> Restarting with MCP_AUTH_TOKEN'
cleanup
token=$(openssl rand -hex 16)
start_container -e "MCP_AUTH_TOKEN=$token"
wait_healthy

echo '==> /mcp without token must be 401'
code=$(curl -s -o /dev/null -w '%{http_code}' "${HEADERS[@]}" -d "$INIT_BODY" "$BASE/mcp")
[ "$code" = '401' ] || fail "expected 401 without token, got $code"

echo '==> /mcp with bearer token must be 200'
code=$(curl -s -o /dev/null -w '%{http_code}' "${HEADERS[@]}" \
  -H "Authorization: Bearer $token" -d "$INIT_BODY" "$BASE/mcp")
[ "$code" = '200' ] || fail "expected 200 with token, got $code"

echo 'SMOKE TEST PASSED'
