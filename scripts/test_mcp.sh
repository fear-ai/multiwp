#!/bin/bash
# test_mcp.sh - Unit tests for helpers in mcp.sh
#
# Example: ./scripts/test_mcp.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/mcp.sh"

set +e

failures=0

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

assert_status() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" -eq "$actual" ]; then
        pass "$label"
    else
        fail "$label (expected status $expected, got $actual)"
    fi
}

echo "== mcp_normalize_portal_url =="
assert_equal "https://example.com/mcp" "$(mcp_normalize_portal_url "example.com")" "adds scheme and /mcp"
assert_equal "https://example.com/mcp" "$(mcp_normalize_portal_url "https://example.com")" "adds /mcp to bare origin"
assert_equal "https://example.com/mcp" "$(mcp_normalize_portal_url "https://example.com/")" "adds /mcp to trailing slash"
assert_equal "https://example.com/mcp" "$(mcp_normalize_portal_url " https://example.com/mcp ")" "trims whitespace"
assert_equal "http://example.com/foo" "$(mcp_normalize_portal_url "http://example.com/foo")" "preserves explicit path"
mcp_normalize_portal_url "" >/dev/null 2>&1
assert_status 1 $? "rejects empty portal URL"

mcp_normalize_portal_url "   " >/dev/null 2>&1
assert_status 1 $? "rejects whitespace portal URL"


echo "== mcp_portal_status_class =="
assert_equal "pass" "$(mcp_portal_status_class 200)" "200 returns pass"
assert_equal "warn" "$(mcp_portal_status_class 401)" "401 returns warn"
assert_equal "warn" "$(mcp_portal_status_class 403)" "403 returns warn"
assert_equal "warn" "$(mcp_portal_status_class 302)" "302 returns warn"
assert_equal "fail" "$(mcp_portal_status_class 404)" "404 returns fail"
assert_equal "fail" "$(mcp_portal_status_class 500)" "500 returns fail"
mcp_portal_status_class "abc" >/dev/null 2>&1
assert_status 1 $? "non-numeric status returns error"


echo "== mcp_portal_status_message =="
assert_equal "Portal reachable (authorized)" "$(mcp_portal_status_message 200)" "200 message"
assert_equal "Portal reachable; authorization required" "$(mcp_portal_status_message 401)" "401 message"
assert_equal "Portal returned redirect (status 302)" "$(mcp_portal_status_message 302)" "302 message"
assert_equal "Portal returned client error (status 404)" "$(mcp_portal_status_message 404)" "404 message"
assert_equal "Portal returned server error (status 500)" "$(mcp_portal_status_message 500)" "500 message"
assert_equal "Portal probe failed" "$(mcp_portal_status_message 000)" "000 message"
assert_equal "Portal probe failed" "$(mcp_portal_status_message abc)" "non-numeric message"

if [ "$failures" -gt 0 ]; then
    echo "\n$failures test(s) failed." >&2
    exit 1
fi

echo "\nAll tests passed."
