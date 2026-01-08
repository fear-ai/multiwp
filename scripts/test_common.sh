#!/bin/bash
# test_common.sh - Unit tests for helpers in common.sh
#
# Example: ./scripts/test_common.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$ROOT_DIR/scripts/common.sh"

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

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if echo "$haystack" | grep -Fq -- "$needle"; then
        pass "$label"
    else
        fail "$label (missing '$needle')"
    fi
}

run_subshell() {
    local output
    output="$({ "$@"; } 2>&1)"
    local status=$?
    echo "$output"
    return $status
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "== tolower =="
assert_equal "abc.def" "$(tolower "ABC.DEF")" "tolower lowercases input"

echo "== safe_name =="
assert_equal "examplecom" "$(safe_name "example.com")" "safe_name strips dots"
assert_equal "abcexamplecom" "$(safe_name "a-b.c-example.com")" "safe_name strips dots and hyphens"

echo "== priv with sudo enabled =="
SUDO_STUB="$TMP_DIR/sudo"
cat <<'STUB' > "$SUDO_STUB"
#!/bin/bash
printf '%s\n' "$@"
STUB
chmod +x "$SUDO_STUB"

SAVED_SUDO_BIN="${SUDO_BIN-}"
SUDO_BIN="$SUDO_STUB"
output=$(priv -u www-data echo "hi")
assert_contains "$output" "-u" "priv passes -u when sudo enabled"
assert_contains "$output" "www-data" "priv passes user when sudo enabled"
assert_contains "$output" "echo" "priv passes command when sudo enabled"
assert_contains "$output" "hi" "priv passes args when sudo enabled"
SUDO_BIN="$SAVED_SUDO_BIN"

echo "== priv with sudo disabled =="
SUDO_BIN=""
output=$(priv -u www-data echo "hi")
assert_equal "hi" "$output" "priv drops -u when sudo disabled"
output=$(priv echo "hello")
assert_equal "hello" "$output" "priv runs command directly when sudo disabled"
SUDO_BIN="$SAVED_SUDO_BIN"

if [ "$failures" -gt 0 ]; then
    echo "\n$failures test(s) failed." >&2
    exit 1
fi

echo "\nAll tests passed."
