#!/bin/bash
# test_cmd.sh - Unit tests for helpers in cmd.sh
#
# Example: ./scripts/test_cmd.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cmd.sh"

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

run_subshell() {
    local output
    output="$({ "$@"; } 2>&1)"
    local status=$?
    echo "$output"
    return $status
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "== run_cmd inherit =="
output=$(run_subshell run_cmd "inherit" "inherit" -- echo "hello")
status=$?
assert_contains "$output" "hello" "run_cmd inherit writes to stdout"
assert_status 0 "$status" "run_cmd inherit returns status"

echo "== cmd_join =="
assert_equal "echo hello" "$(cmd_join echo hello)" "cmd_join joins args"

echo "== run_cmd out =="
out_file="$TMP_DIR/out.txt"
run_cmd "out" "out" "$out_file" -- printf "out"
assert_equal "out" "$(cat "$out_file")" "run_cmd out writes stdout to file"

echo "== run_cmd err =="
err_file="$TMP_DIR/err.txt"
run_cmd "err" "err" "$err_file" -- bash -c 'echo "err" >&2'
assert_equal "err" "$(cat "$err_file")" "run_cmd err writes stderr to file"

echo "== run_cmd both =="
out_file="$TMP_DIR/both.out"
err_file="$TMP_DIR/both.err"
run_cmd "both" "both" "$out_file" "$err_file" -- bash -c 'echo "o"; echo "e" >&2'
assert_equal "o" "$(cat "$out_file")" "run_cmd both writes stdout file"
assert_equal "e" "$(cat "$err_file")" "run_cmd both writes stderr file"

echo "== run_cmd merge =="
out_file="$TMP_DIR/merge.txt"
run_cmd "merge" "merge" "$out_file" -- bash -c 'echo "o"; echo "e" >&2'
assert_contains "$(cat "$out_file")" "o" "run_cmd merge includes stdout"
assert_contains "$(cat "$out_file")" "e" "run_cmd merge includes stderr"

echo "== run_cmd append =="
out_file="$TMP_DIR/append.txt"
run_cmd "append" "out" "$out_file" -- printf "one"
run_cmd "append" "out-append" "$out_file" -- printf "two"
assert_equal "onetwo" "$(cat "$out_file")" "run_cmd out-append appends"

echo "== start_cmd out =="
out_file="$TMP_DIR/bg.txt"
pid=$(start_cmd "bg" "out" "$out_file" -- bash -c 'echo "bg"; sleep 0.1')
wait "$pid" >/dev/null 2>&1
assert_equal "bg" "$(cat "$out_file")" "start_cmd out writes file"

echo "== invalid mode =="
output=$(run_subshell run_cmd "bad" "nope" -- echo "nope")
status=$?
assert_status 1 "$status" "run_cmd invalid mode fails"

echo "== missing separator =="
output=$(run_subshell run_cmd "bad" "inherit" echo "nope")
status=$?
assert_status 1 "$status" "run_cmd missing separator fails"

if [ "$failures" -gt 0 ]; then
    echo "FAILURES: $failures" >&2
    exit 1
fi

echo "All cmd.sh tests passed."
