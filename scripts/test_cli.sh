#!/bin/bash
# test_cli.sh - Unit tests for helpers in cli.sh
#
# Example: ./scripts/test_cli.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

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

reset_env() {
    unset ALLOW_ROOT
    unset CF_AUTH_FILE CF_ACCOUNT_ID_CLI CF_API_TOKEN_CLI CF_API_EMAIL_CLI CF_API_KEY_CLI CF_CA_KEY_CLI
}

run_subshell() {
    local output
    output="$({ "$@"; } 2>&1)"
    local status=$?
    echo "$output"
    return $status
}

SAVED_SUDO_BIN="${SUDO_BIN-}"

echo "== cli_common_opt =="
reset_env
SUDO_BIN="$SAVED_SUDO_BIN"
cli_common_opt "allow-root"
assert_equal "true" "${ALLOW_ROOT:-}" "cli_common_opt sets ALLOW_ROOT"

reset_env
SUDO_BIN="$SAVED_SUDO_BIN"
cli_common_opt "no-sudo"
assert_equal "" "${SUDO_BIN:-}" "cli_common_opt clears SUDO_BIN"

echo "== cli_require_non_root =="
output=$(bash -lc '. /home/ubuntu/WP/multiwp/scripts/common.sh; . /home/ubuntu/WP/multiwp/scripts/cli.sh; USER=root; ALLOW_ROOT=false; cli_require_non_root' 2>&1)
assert_contains "$output" "Do not run as root" "cli_require_non_root blocks root by default"

output=$(bash -lc '. /home/ubuntu/WP/multiwp/scripts/common.sh; . /home/ubuntu/WP/multiwp/scripts/cli.sh; USER=root; ALLOW_ROOT=true; cli_require_non_root; echo ok' 2>&1)
assert_contains "$output" "ok" "cli_require_non_root allows root when priority option set"

echo "== cli_wp_root_opt =="
reset_env
OPTIND=1
WORDPRESS_ROOT_LOCAL=""
cli_wp_root_opt "wp-root=/srv/wp" WORDPRESS_ROOT_LOCAL
assert_equal "/srv/wp" "$WORDPRESS_ROOT_LOCAL" "cli_wp_root_opt parses --wp-root=VAL"
assert_equal "1" "$OPTIND" "cli_wp_root_opt does not advance OPTIND for --wp-root=VAL"

reset_env
OPTIND=1
WORDPRESS_ROOT_LOCAL=""
cli_wp_root_opt "wp-root" WORDPRESS_ROOT_LOCAL "/var/www"
assert_equal "/var/www" "$WORDPRESS_ROOT_LOCAL" "cli_wp_root_opt parses --wp-root VAL"
assert_equal "2" "$OPTIND" "cli_wp_root_opt advances OPTIND for --wp-root VAL"

output=$(bash -lc '. /home/ubuntu/WP/multiwp/scripts/common.sh; . /home/ubuntu/WP/multiwp/scripts/cli.sh; OPTIND=1; cli_wp_root_opt wp-root ROOT_VAR ""' 2>&1)
assert_contains "$output" "--wp-root requires a value" "cli_wp_root_opt errors on missing value"

echo "== cli_ssl_dir_opt =="
reset_env
OPTIND=1
SSL_DIR=""
SSL_CERT_DIR=""
SSL_KEY_DIR=""
cli_ssl_dir_opt "ssl-dir=/ssl" SSL_DIR SSL_CERT_DIR SSL_KEY_DIR
assert_equal "/ssl" "$SSL_DIR" "cli_ssl_dir_opt parses --ssl-dir=VAL"
assert_equal "/ssl/certs" "$SSL_CERT_DIR" "cli_ssl_dir_opt sets cert dir"
assert_equal "/ssl/keys" "$SSL_KEY_DIR" "cli_ssl_dir_opt sets key dir"
assert_equal "1" "$OPTIND" "cli_ssl_dir_opt does not advance OPTIND for --ssl-dir=VAL"

reset_env
OPTIND=1
SSL_DIR=""
SSL_CERT_DIR=""
SSL_KEY_DIR=""
cli_ssl_dir_opt "ssl-dir" SSL_DIR SSL_CERT_DIR SSL_KEY_DIR "/etc/ssl"
assert_equal "/etc/ssl" "$SSL_DIR" "cli_ssl_dir_opt parses --ssl-dir VAL"
assert_equal "2" "$OPTIND" "cli_ssl_dir_opt advances OPTIND for --ssl-dir VAL"

output=$(bash -lc '. /home/ubuntu/WP/multiwp/scripts/common.sh; . /home/ubuntu/WP/multiwp/scripts/cli.sh; OPTIND=1; cli_ssl_dir_opt ssl-dir SSL_DIR' 2>&1)
assert_contains "$output" "--ssl-dir requires a value" "cli_ssl_dir_opt errors on missing value"

echo "== cli_domain_opt =="
reset_env
OPTIND=1
DOMAINS=()
cli_domain_opt "domain=example.com" DOMAINS
assert_equal "example.com" "${DOMAINS[0]-}" "cli_domain_opt parses --domain=VAL"
assert_equal "1" "$OPTIND" "cli_domain_opt does not advance OPTIND for --domain=VAL"

reset_env
OPTIND=1
DOMAINS=()
cli_domain_opt "domain" DOMAINS "example.org"
assert_equal "example.org" "${DOMAINS[0]-}" "cli_domain_opt parses --domain VAL"
assert_equal "2" "$OPTIND" "cli_domain_opt advances OPTIND for --domain VAL"

output=$(bash -lc '. /home/ubuntu/WP/multiwp/scripts/common.sh; . /home/ubuntu/WP/multiwp/scripts/cli.sh; OPTIND=1; DOMAINS=(); cli_domain_opt domain DOMAINS ""' 2>&1)
assert_contains "$output" "--domain requires a value" "cli_domain_opt errors on missing value"

echo "== cli_cf_auth_opt =="
reset_env
OPTIND=1
cli_cf_auth_opt "token=tok123" ""
assert_equal "tok123" "$CF_API_TOKEN_CLI" "cli_cf_auth_opt parses --token=VAL"
assert_equal "1" "$OPTIND" "cli_cf_auth_opt does not advance OPTIND for --token=VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "token" "tok456"
assert_equal "tok456" "$CF_API_TOKEN_CLI" "cli_cf_auth_opt parses --token VAL"
assert_equal "2" "$OPTIND" "cli_cf_auth_opt advances OPTIND for --token VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "auth-file=/tmp/auth" ""
assert_equal "/tmp/auth" "$CF_AUTH_FILE" "cli_cf_auth_opt parses --auth-file=VAL"
assert_equal "1" "$OPTIND" "cli_cf_auth_opt does not advance OPTIND for --auth-file=VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "account" "acc123"
assert_equal "acc123" "$CF_ACCOUNT_ID_CLI" "cli_cf_auth_opt parses --account VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "email" "user@example.com"
assert_equal "user@example.com" "$CF_API_EMAIL_CLI" "cli_cf_auth_opt parses --email VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "key" "key123"
assert_equal "key123" "$CF_API_KEY_CLI" "cli_cf_auth_opt parses --key VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "ca-key" "cakey123"
assert_equal "cakey123" "$CF_CA_KEY_CLI" "cli_cf_auth_opt parses --ca-key VAL"

reset_env
OPTIND=1
cli_cf_auth_opt "unknown" "" >/dev/null 2>&1
assert_status 1 $? "cli_cf_auth_opt returns 1 for unknown option"

SUDO_BIN="$SAVED_SUDO_BIN"

if [ "$failures" -gt 0 ]; then
    echo "\n$failures test(s) failed." >&2
    exit 1
fi

echo "\nAll tests passed."
