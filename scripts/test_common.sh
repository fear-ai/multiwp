#!/bin/bash
# test_common.sh - Unit tests for helpers in common.sh
#
# Example: ./scripts/test_common.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/common.sh"

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

echo "== tolower =="
assert_equal "abc.def" "$(tolower "ABC.DEF")" "tolower lowercases input"

echo "== safe_name =="
assert_equal "examplecom" "$(safe_name "example.com")" "safe_name strips dots"
assert_equal "abcexamplecom" "$(safe_name "a-b.c-example.com")" "safe_name strips dots and hyphens"

echo "== normalize_domain =="
assert_equal "example.com" "$(normalize_domain " Example.COM ")" "normalize_domain trims and lowercases"

echo "== validate_domain =="
validate_domain "example.com"
assert_status 0 $? "validate_domain accepts valid domain"
validate_domain ".example.com" >/dev/null 2>&1
assert_status 1 $? "validate_domain rejects leading dot"
validate_domain "example..com" >/dev/null 2>&1
assert_status 1 $? "validate_domain rejects empty label"
long_label="$(printf 'a%.0s' {1..64}).com"
validate_domain "$long_label" >/dev/null 2>&1
assert_status 1 $? "validate_domain rejects label > 63 chars"

echo "== finalize_domains =="
DOMAINS=("Example.com" "example.com" "www.example.com")
finalize_domains DOMAINS
assert_equal "2" "${#DOMAINS[@]}" "finalize_domains de-dupes domains"
assert_equal "example.com" "${DOMAINS[0]}" "finalize_domains normalizes case"
DOMAINS=("example..com")
finalize_domains DOMAINS >/dev/null 2>&1
assert_status 1 $? "finalize_domains fails on invalid domain"

echo "== validate_ipv4 =="
validate_ipv4 "192.0.2.10"
assert_status 0 $? "validate_ipv4 accepts valid IPv4"
validate_ipv4 "1.1.1.1"
assert_status 0 $? "validate_ipv4 accepts public IPv4"
validate_ipv4 "8.8.8.8"
assert_status 0 $? "validate_ipv4 accepts public resolver IPv4"
validate_ipv4 "93.184.216.34"
assert_status 0 $? "validate_ipv4 accepts public example.com IPv4"
validate_ipv4 "172.15.255.255"
assert_status 0 $? "validate_ipv4 accepts 172.15.255.255 (outside RFC1918)"
validate_ipv4 "172.32.0.0"
assert_status 0 $? "validate_ipv4 accepts 172.32.0.0 (outside RFC1918)"
validate_ipv4 "192.167.255.255"
assert_status 0 $? "validate_ipv4 accepts 192.167.255.255 (outside RFC1918)"
validate_ipv4 "192.169.0.0"
assert_status 0 $? "validate_ipv4 accepts 192.169.0.0 (outside RFC1918)"
validate_ipv4 "999.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects out of range"
validate_ipv4 "192.0.2" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects invalid format"
validate_ipv4 "224.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects multicast range"
validate_ipv4 "255.255.255.255" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects broadcast"
validate_ipv4 "10.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects RFC1918 10.0.0.0/8"
validate_ipv4 "172.16.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects RFC1918 172.16.0.0/12"
validate_ipv4 "192.168.1.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects RFC1918 192.168.0.0/16"
validate_ipv4 "169.254.1.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects link-local 169.254.0.0/16"
validate_ipv4 "127.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ipv4 rejects loopback 127.0.0.0/8"

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
