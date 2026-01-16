#!/bin/bash
# test_cf.sh - Unit tests for Cloudflare helpers in auth.sh
#
# Example: ./scripts/test_cf.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"

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

reset_auth_env() {
    unset CF_API_TOKEN CF_API_KEY CF_API_EMAIL CF_CA_KEY
    unset CF_ACCOUNT_ID CF_ZONE_ID CF_ZONE CF_ZONE_MAIN CF_ZONE_IDS CF_AUTH_MODE CF_AUTH
    unset CF_API_TOKEN_CLI CF_API_KEY_CLI CF_API_EMAIL_CLI CF_ACCOUNT_ID_CLI CF_CA_KEY_CLI CF_AUTH_CLI
    unset CF_AUTH_FILE
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


echo "== cf_auth_mode =="
reset_auth_env
CF_API_TOKEN="token123"
cf_auth_mode
assert_equal "token" "$CF_AUTH_MODE" "cf_auth_mode prefers token"

reset_auth_env
CF_API_KEY="key123"
CF_API_EMAIL="user@example.com"
cf_auth_mode
assert_equal "key" "$CF_AUTH_MODE" "cf_auth_mode uses key when token missing"

reset_auth_env
CF_AUTH="token"
CF_API_TOKEN="token123"
cf_auth_mode
assert_equal "token" "$CF_AUTH_MODE" "cf_auth_mode honors CF_AUTH=token"

reset_auth_env
CF_AUTH="key"
CF_API_TOKEN="token123"
CF_API_KEY="key123"
CF_API_EMAIL="user@example.com"
cf_auth_mode
assert_equal "key" "$CF_AUTH_MODE" "cf_auth_mode honors CF_AUTH=key"

reset_auth_env
CF_AUTH="token"
run_subshell cf_auth_mode >/dev/null
assert_status 1 $? "cf_auth_mode fails when CF_AUTH=token and token missing"

reset_auth_env
CF_AUTH="key"
run_subshell cf_auth_mode >/dev/null
assert_status 1 $? "cf_auth_mode fails when CF_AUTH=key and key/email missing"

reset_auth_env
run_subshell cf_auth_mode >/dev/null
assert_status 1 $? "cf_auth_mode fails when no credentials"

echo "== cf_has/cf_require helpers =="
reset_auth_env
run_subshell cf_has_token >/dev/null
assert_status 1 $? "cf_has_token false when missing"
CF_API_TOKEN="token123"
run_subshell cf_has_token >/dev/null
assert_status 0 $? "cf_has_token true when set"

reset_auth_env
CF_API_KEY="key123"
CF_API_EMAIL="user@example.com"
run_subshell cf_has_key >/dev/null
assert_status 0 $? "cf_has_key true when key+email set"

reset_auth_env
CF_CA_KEY="v1.0-abc"
run_subshell cf_has_ca_key >/dev/null
assert_status 0 $? "cf_has_ca_key true when set"

reset_auth_env
output=$(run_subshell cf_require_token)
status=$?
assert_status 1 "$status" "cf_require_token fails when missing"
assert_contains "$output" "CF_API_TOKEN required" "cf_require_token message"

reset_auth_env
output=$(run_subshell cf_require_key)
status=$?
assert_status 1 "$status" "cf_require_key fails when missing"
assert_contains "$output" "CF_API_KEY+CF_API_EMAIL required" "cf_require_key message"

reset_auth_env
output=$(run_subshell cf_require_ca_key)
status=$?
assert_status 1 "$status" "cf_require_ca_key fails when missing"
assert_contains "$output" "CF_CA_KEY required" "cf_require_ca_key message"

reset_auth_env
CF_ACCOUNT_ID="acct123"
run_subshell cf_require_account_id >/dev/null
assert_status 0 $? "cf_require_account_id succeeds when ID set"

reset_auth_env
CF_ACCOUNT_ID="acct123"
run_subshell cf_has_account_id >/dev/null
assert_status 0 $? "cf_has_account_id true when set"

reset_auth_env
CF_ZONE_ID="zone123"
run_subshell cf_has_zone_id >/dev/null
assert_status 0 $? "cf_has_zone_id true when set"


echo "== load_cloudflare_auth =="
auth_file="$TMP_DIR/auth"
cat <<'AUTH' > "$auth_file"
CF_API_TOKEN="filetoken"
CF_ACCOUNT_ID="fileaccount"
CF_ZONE_ID="filezone"
AUTH

reset_auth_env
load_cloudflare_auth "$auth_file"
assert_equal "filetoken" "$CF_API_TOKEN" "load_cloudflare_auth sets token from file"
assert_equal "fileaccount" "$CF_ACCOUNT_ID" "load_cloudflare_auth sets account id from file"
assert_equal "filezone" "$CF_ZONE_ID" "load_cloudflare_auth sets zone id from file"
assert_equal "filezone" "$CF_ZONE_IDS" "load_cloudflare_auth collects zone ids from file"

reset_auth_env
CF_API_TOKEN="envtoken"
CF_ACCOUNT_ID="envaccount"
load_cloudflare_auth "$auth_file"
assert_equal "envtoken" "$CF_API_TOKEN" "load_cloudflare_auth preserves env token priority"
assert_equal "envaccount" "$CF_ACCOUNT_ID" "load_cloudflare_auth preserves env account priority"
assert_equal "filezone" "$CF_ZONE_ID" "load_cloudflare_auth still loads unset vars"

auth_file_multi="$TMP_DIR/auth-multi"
cat <<'AUTH' > "$auth_file_multi"
CF_ZONE_MAIN="alpha.example"
CF_ZONE="alpha.example"
CF_ZONE_ID="zone-alpha"
CF_ZONE="beta.example"
CF_ZONE_ID="zone-beta"
AUTH

reset_auth_env
load_cloudflare_auth "$auth_file_multi"
assert_equal "zone-alpha" "$CF_ZONE_ID" "load_cloudflare_auth uses first CF_ZONE_ID by default"
assert_equal "alpha.example" "$CF_ZONE" "load_cloudflare_auth prefers CF_ZONE_MAIN for zone name"
assert_equal "zone-alpha,zone-beta" "$CF_ZONE_IDS" "load_cloudflare_auth collects multiple zone ids"

auth_file_first="$TMP_DIR/auth-first"
cat <<'AUTH' > "$auth_file_first"
CF_ZONE="first.example"
CF_ZONE_ID="zone-first"
CF_ZONE="second.example"
CF_ZONE_ID="zone-second"
AUTH

reset_auth_env
load_cloudflare_auth "$auth_file_first"
assert_equal "zone-first" "$CF_ZONE_ID" "load_cloudflare_auth uses first CF_ZONE_ID when no CF_ZONE_MAIN"
assert_equal "first.example" "$CF_ZONE" "load_cloudflare_auth uses first CF_ZONE when no CF_ZONE_MAIN"
assert_equal "zone-first,zone-second" "$CF_ZONE_IDS" "load_cloudflare_auth keeps zone id list"

reset_auth_env
CF_ZONE_ID="env-zone"
CF_ZONE="env.example"
CF_ZONE_IDS="env-one env-two"
load_cloudflare_auth "$auth_file_first"
assert_equal "env-zone" "$CF_ZONE_ID" "load_cloudflare_auth preserves CF_ZONE_ID priority"
assert_equal "env.example" "$CF_ZONE" "load_cloudflare_auth preserves CF_ZONE priority"
assert_equal "env-one env-two" "$CF_ZONE_IDS" "load_cloudflare_auth preserves CF_ZONE_IDS priority"

auth_file_quotes="$TMP_DIR/auth-quotes"
cat <<'AUTH' > "$auth_file_quotes"
CF_ZONE_MAIN="quoted-main.example"
CF_ZONE="quoted-one.example"
CF_ZONE_ID="zone-quoted-one"
CF_ZONE="quoted-two.example"
CF_ZONE_ID="zone-quoted-two"
AUTH

reset_auth_env
load_cloudflare_auth "$auth_file_quotes"
assert_equal "zone-quoted-one" "$CF_ZONE_ID" "load_cloudflare_auth strips quotes and uses first CF_ZONE_ID"
assert_equal "quoted-main.example" "$CF_ZONE" "load_cloudflare_auth uses quoted CF_ZONE_MAIN"

auth_file_ids_only="$TMP_DIR/auth-ids-only"
cat <<'AUTH' > "$auth_file_ids_only"
CF_ZONE_ID="zone-only-one"
CF_ZONE_ID="zone-only-two"
AUTH

reset_auth_env
load_cloudflare_auth "$auth_file_ids_only"
assert_equal "zone-only-one" "$CF_ZONE_ID" "load_cloudflare_auth uses first CF_ZONE_ID when no zones listed"
assert_equal "" "${CF_ZONE:-}" "load_cloudflare_auth leaves CF_ZONE empty when none listed"


echo "== cf_auth_file / cf_auth_opt =="
reset_auth_env
cf_auth_file "auth-file" "$auth_file"
assert_equal "$auth_file" "$CF_AUTH_FILE" "cf_auth_file parses --auth-file value"

reset_auth_env
cf_auth_opt "account" "acct123"
assert_equal "acct123" "$CF_ACCOUNT_ID_CLI" "cf_auth_opt parses --account"

reset_auth_env
cf_auth_opt "token" "tok123"
assert_equal "tok123" "$CF_API_TOKEN_CLI" "cf_auth_opt parses --token"

reset_auth_env
cf_auth_opt "email" "user@example.com"
assert_equal "user@example.com" "$CF_API_EMAIL_CLI" "cf_auth_opt parses --email"

reset_auth_env
cf_auth_opt "key" "key456"
assert_equal "key456" "$CF_API_KEY_CLI" "cf_auth_opt parses --key"

reset_auth_env
cf_auth_opt "ca-key" "cakey789"
assert_equal "cakey789" "$CF_CA_KEY_CLI" "cf_auth_opt parses --ca-key"

reset_auth_env
cf_auth_opt "auth" "token"
assert_equal "token" "$CF_AUTH_CLI" "cf_auth_opt parses --auth token"


echo "== cf_api_headers_mode =="
reset_auth_env
CF_API_TOKEN="token123"
cf_api_headers_mode "token"
assert_contains "${CF_API_HEADERS[*]}" "Authorization: Bearer token123" "token mode adds bearer header"

reset_auth_env
CF_API_KEY="key123"
CF_API_EMAIL="user@example.com"
cf_api_headers_mode "key"
assert_contains "${CF_API_HEADERS[*]}" "X-Auth-Key: key123" "key mode adds X-Auth-Key"
assert_contains "${CF_API_HEADERS[*]}" "X-Auth-Email: user@example.com" "key mode adds X-Auth-Email"

reset_auth_env
run_subshell cf_api_headers_mode "token" >/dev/null
assert_status 1 $? "token mode fails without CF_API_TOKEN"


echo "== cf_api_request_mode =="
STUB_BIN="$TMP_DIR/bin"
mkdir -p "$STUB_BIN"
cat <<'STUB' > "$STUB_BIN/curl"
#!/bin/bash
printf '%s\n' "$@"
STUB
chmod +x "$STUB_BIN/curl"
PATH="$STUB_BIN:$PATH"

reset_auth_env
CF_API_TOKEN="token123"
output=$(cf_api_request_mode "token" "GET" "/zones?name=example.com")
assert_contains "$output" "-X" "cf_api_request_mode includes method option"
assert_contains "$output" "GET" "cf_api_request_mode uses method"
assert_contains "$output" "Authorization: Bearer token123" "cf_api_request_mode uses bearer auth"
assert_contains "$output" "https://api.cloudflare.com/client/v4/zones?name=example.com" "cf_api_request_mode builds URL"

echo "== cf_origin_ca_request =="
reset_auth_env
CF_CA_KEY="cakey123"
output=$(cf_origin_ca_request "GET" "/certificates?zone_id=abc")
assert_contains "$output" "X-Auth-User-Service-Key: cakey123" "cf_origin_ca_request uses Origin CA key"

reset_auth_env
CF_API_TOKEN="token123"
output=$(run_subshell cf_origin_ca_request "GET" "/certificates?zone_id=abc")
assert_status 1 $? "cf_origin_ca_request fails without CA key even when token is set"
assert_contains "$output" "CF_CA_KEY required" "cf_origin_ca_request requires Origin CA key"

reset_auth_env
CF_API_KEY="key123"
CF_API_EMAIL="user@example.com"
output=$(run_subshell cf_origin_ca_request "GET" "/certificates?zone_id=abc")
assert_status 1 $? "cf_origin_ca_request fails without CA key even when key/email are set"
assert_contains "$output" "CF_CA_KEY required" "cf_origin_ca_request requires Origin CA key"

echo "== cf_api_request checked =="
cat <<'STUB' > "$STUB_BIN/curl"
#!/bin/bash
out=""
fmt=""
status="200"
body='{"success":true,"errors":[]}'
for arg in "$@"; do
    case "$arg" in
        *"/fail"*) status="403"; body='{"success":false,"errors":[{"message":"denied"}]}' ;;
    esac
done
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -w) fmt="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "$out" ]; then
    printf '%s' "$body" > "$out"
fi
printf '%s' "$status"
STUB
chmod +x "$STUB_BIN/curl"

reset_auth_env
CF_API_TOKEN="token123"
tmp_out="$TMP_DIR/cf-api-checked-ok"
cf_api_request "GET" "/zones" "" "checked" >"$tmp_out"
output=$(cat "$tmp_out")
assert_contains "$output" "\"success\":true" "cf_api_request checked returns body"
assert_equal "200" "$CF_API_LAST_STATUS" "cf_api_request checked sets status"
assert_equal "true" "$CF_API_LAST_SUCCESS" "cf_api_request checked sets success"

reset_auth_env
CF_API_TOKEN="token123"
output=$(run_subshell cf_api_request "GET" "/fail" "" "checked")
status=$?
assert_status 1 "$status" "cf_api_request checked fails on non-2xx or success false"
assert_contains "$output" "FAIL:" "cf_api_request checked reports failure"
assert_contains "$output" "denied" "cf_api_request checked includes API error"

echo "== cf_api_request / cf_origin_ca_request error paths =="
reset_auth_env
output=$(run_subshell cf_api_request "GET" "/zones")
assert_status 1 $? "cf_api_request fails without credentials"
assert_contains "$output" "Account API token" "cf_api_request error mentions account API token"

reset_auth_env
output=$(run_subshell cf_origin_ca_request "GET" "/certificates?zone_id=abc")
assert_status 1 $? "cf_origin_ca_request fails without credentials"
assert_contains "$output" "CF_CA_KEY required" "cf_origin_ca_request error mentions CF_CA_KEY"


echo "== cf_api_success / cf_api_error_messages =="
json_ok='{"success":true,"errors":[]}'
json_err='{"success":false,"errors":[{"message":"denied"},{"message":"missing"}]}'

assert_equal "true" "$(cf_api_success "$json_ok")" "cf_api_success parses success"
assert_equal "false" "$(cf_api_success "$json_err")" "cf_api_success parses failure"
assert_equal "denied missing " "$(cf_api_error_messages "$json_err")" "cf_api_error_messages joins errors"


if [ "$failures" -gt 0 ]; then
    echo "\n$failures test(s) failed." >&2
    exit 1
fi

echo "\nAll tests passed."
