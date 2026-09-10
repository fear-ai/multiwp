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

echo "== trim_spaces / normalize_site_type =="
assert_equal "value" "$(trim_spaces "  value  ")" "trim_spaces trims leading and trailing whitespace"
assert_equal "none" "$(normalize_site_type "")" "normalize_site_type maps empty to none"
assert_equal "none" "$(normalize_site_type "   ")" "normalize_site_type maps whitespace to none"
assert_equal "singlesite" "$(normalize_site_type "SingleSite")" "normalize_site_type lowercases values"
assert_equal "worker" "$(normalize_site_type " WORKER ")" "normalize_site_type trims and lowercases"

echo "== site_type_is_skip =="
site_type_is_skip "none"
assert_status 0 $? "site_type_is_skip matches none"
site_type_is_skip "ignore"
assert_status 0 $? "site_type_is_skip matches ignore"
site_type_is_skip "worker"
assert_status 0 $? "site_type_is_skip matches worker"
site_type_is_skip "singlesite"
assert_status 1 $? "site_type_is_skip rejects singlesite"

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

echo "== validate_ip =="
validate_ip "192.0.2.1"
assert_status 0 $? "validate_ip accepts valid IPv4"
validate_ip "1.1.1.1"
assert_status 0 $? "validate_ip accepts public IPv4"
validate_ip "8.8.8.8"
assert_status 0 $? "validate_ip accepts public resolver IPv4"
validate_ip "93.184.216.34"
assert_status 0 $? "validate_ip accepts public example.com IPv4"
validate_ip "172.15.255.255"
assert_status 0 $? "validate_ip accepts 172.15.255.255 (outside RFC1918)"
validate_ip "172.32.0.0"
assert_status 0 $? "validate_ip accepts 172.32.0.0 (outside RFC1918)"
validate_ip "192.167.255.255"
assert_status 0 $? "validate_ip accepts 192.167.255.255 (outside RFC1918)"
validate_ip "192.169.0.0"
assert_status 0 $? "validate_ip accepts 192.169.0.0 (outside RFC1918)"
validate_ip "999.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects out of range"
validate_ip "192.0.2" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects invalid format"
validate_ip "224.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects multicast range"
validate_ip "255.255.255.255" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects broadcast"
validate_ip "10.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects RFC1918 10.0.0.0/8"
validate_ip "172.16.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects RFC1918 172.16.0.0/12"
validate_ip "192.168.1.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects RFC1918 192.168.0.0/16"
validate_ip "169.254.1.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects link-local 169.254.0.0/16"
validate_ip "127.0.0.1" >/dev/null 2>&1
assert_status 1 $? "validate_ip rejects loopback 127.0.0.0/8"

echo "== parse_bool =="
assert_equal "true" "$(parse_bool "true")" "parse_bool accepts true"
assert_equal "true" "$(parse_bool "TRUE")" "parse_bool accepts uppercase true"
assert_equal "true" "$(parse_bool "YES")" "parse_bool accepts yes"
assert_equal "true" "$(parse_bool " y ")" "parse_bool accepts y with whitespace"
assert_equal "false" "$(parse_bool "false")" "parse_bool accepts false"
assert_equal "false" "$(parse_bool "FALSE")" "parse_bool accepts uppercase false"
assert_equal "false" "$(parse_bool "No")" "parse_bool accepts no"
assert_equal "false" "$(parse_bool " n ")" "parse_bool accepts n with whitespace"
parse_bool "maybe" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects invalid value"
parse_bool "" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects empty string"
parse_bool "   " >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects whitespace"
parse_bool "tru" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects partial token"
parse_bool "yesplease" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects extra characters"
parse_bool "1" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects numeric true"
parse_bool "0" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects numeric false"
parse_bool "on" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects on"
parse_bool "off" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects off"
parse_bool "t" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects t"
parse_bool "f" >/dev/null 2>&1
assert_status 1 $? "parse_bool rejects f"

echo "== parse_comma_list =="
LIST=()
parse_comma_list "alpha, beta,gamma" LIST "list"
assert_equal "3" "${#LIST[@]}" "parse_comma_list splits three tokens"
assert_equal "alpha" "${LIST[0]}" "parse_comma_list trims leading tokens"
assert_equal "beta" "${LIST[1]}" "parse_comma_list trims whitespace"
assert_equal "gamma" "${LIST[2]}" "parse_comma_list keeps last token"

output=$(run_subshell parse_comma_list "alpha,,gamma" LIST "list")
status=$?
assert_contains "$output" "FAIL:" "parse_comma_list reports empty token"
assert_status 1 "$status" "parse_comma_list fails on empty token"

echo "== kv_file_var / kv_file_values =="
kv_file="$TMP_DIR/kv-file"
cat <<'EOF' > "$kv_file"
KEY=first
KEY=second
QUOTED="value"
BLANK=
EOF
assert_equal "first" "$(kv_file_var "$kv_file" KEY)" "kv_file_var returns first match"
assert_equal "value" "$(kv_file_var "$kv_file" QUOTED)" "kv_file_var strips quotes"
values=$(kv_file_values "$kv_file" KEY)
assert_equal $'first\nsecond' "$values" "kv_file_values returns all matches"

echo "== warn =="
output=$(run_subshell warn "test warning")
assert_contains "$output" "Warning:" "warn prefixes output"
assert_contains "$output" "test warning" "warn includes message"

echo "== fail =="
output=$(run_subshell fail "test failure")
assert_contains "$output" "FAIL:" "fail prefixes output"
assert_contains "$output" "test failure" "fail includes message"

echo "== load_dns_redirects / is_redirect_domain =="
domains_path="$TMP_DIR/domains.csv"
cat <<'EOF' > "$domains_path"
domain,site_type,redirect_url
example.com,redirect,https://target.example/
www.example.com,redirect,https://alt.example/path
other.example.com,singlesite,
EOF
DOMAINS_FILE="$domains_path"
load_dns_redirects
assert_equal "2" "${#DNS_REDIRECT_LIST[@]}" "load_dns_redirects loads redirect list from domains.csv"
assert_equal "example.com" "${DNS_REDIRECT_LIST[0]}" "load_dns_redirects normalizes redirect list"
assert_equal "www.example.com" "${DNS_REDIRECT_LIST[1]}" "load_dns_redirects keeps list order"
assert_equal "https://target.example/" "$(redirect_target example.com)" "redirect_target returns apex target"
assert_equal "https://alt.example/path" "$(redirect_target WWW.EXAMPLE.COM)" "redirect_target normalizes domain"
assert_equal "" "$(redirect_target other.example.com)" "redirect_target empty for non-redirect"
is_redirect_domain "WWW.EXAMPLE.COM"
assert_status 0 $? "is_redirect_domain matches normalized domain"
is_redirect_domain "other.example.com"
assert_status 1 $? "is_redirect_domain rejects non-redirect domain"

echo "== record_backup_datastore =="
backup_dir="$TMP_DIR/record"
mkdir -p "$backup_dir"
backup_csv="$backup_dir/domains.csv"
cat <<'EOF' > "$backup_csv"
domain,status_cf
example.com,
EOF
DATASTORE_BACKUP_DONE=false
DATASTORE_DATE="20260116_120000"
record_backup_datastore "$backup_csv" >/dev/null 2>&1
expected_backup="$backup_dir/datastore_20260116_120000.csv"
# The live datastore must still exist: the backup is a copy, not a move. A move
# leaves no inventory if the rewrite that follows fails.
if [ -f "$expected_backup" ] && [ -f "$backup_csv" ]; then
    pass "record_backup_datastore uses DATASTORE_DATE override"
else
    fail "record_backup_datastore did not create expected backup"
fi
if [ -f "$expected_backup" ] && cmp -s "$expected_backup" "$backup_csv"; then
    pass "record_backup_datastore preserves the live datastore"
else
    fail "record_backup_datastore did not preserve the live datastore"
fi
DATASTORE_DATE=""
DATASTORE_BACKUP_DONE=false

echo "== priv with sudo enabled =="
SUDO_STUB="$TMP_DIR/sudo"
cat <<'EOF' > "$SUDO_STUB"
#!/bin/bash
printf '%s\n' "$@"
EOF
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

echo "== load_operator_conf =="
# Each case re-sources common.sh in a subshell with a clean environment, so the
# loader runs from scratch the way a real script invocation does.
CONF_DIR="$TMP_DIR/conf"
mkdir -p "$CONF_DIR"
CONF_FILE="$CONF_DIR/site.conf"
cat >"$CONF_FILE" <<'CONF'
WP_ADMIN_EMAIL=ops@example.net
ORIGIN_IP=198.51.100.7
CONF
chmod 600 "$CONF_FILE"

load_conf_case() {
    env -u WP_ADMIN_EMAIL -u ORIGIN_IP "$@" \
        MULTIWP_CONF="$CONF_FILE" \
        bash -c '. "$0"; printf "%s|%s" "${WP_ADMIN_EMAIL-}" "${ORIGIN_IP-}"' \
        "$SCRIPTS_DIR/common.sh" 2>/dev/null
}

assert_equal "ops@example.net|198.51.100.7" "$(load_conf_case)" \
    "load_operator_conf reads keys from the config file"
assert_equal "env@wins.test|198.51.100.7" "$(load_conf_case WP_ADMIN_EMAIL=env@wins.test)" \
    "load_operator_conf lets the environment win over the config file"

chmod 644 "$CONF_FILE"
output=$(env -u WP_ADMIN_EMAIL MULTIWP_CONF="$CONF_FILE" \
    bash -c '. "$0"' "$SCRIPTS_DIR/common.sh" 2>&1)
assert_contains "$output" "expected 600" "load_operator_conf warns on loose permissions"
chmod 600 "$CONF_FILE"

output=$(env -u WP_ADMIN_EMAIL MULTIWP_CONF="$CONF_DIR/absent.conf" \
    bash -c '. "$0"; echo "ok"' "$SCRIPTS_DIR/common.sh" 2>&1)
assert_equal "ok" "$output" "load_operator_conf ignores a missing config file"

echo "== domains_csv_path =="
# domains_csv_path resolves against ROOT_DIR, so give each case its own tree
# rather than the checkout's real inventory.
INV_ROOT="$TMP_DIR/inv"
mkdir -p "$INV_ROOT"
csv_path_case() {
    env -u DOMAINS_FILE "$@" bash -c '
        ROOT_DIR="$1"; . "$0"; domains_csv_path' \
        "$SCRIPTS_DIR/common.sh" "$INV_ROOT" 2>/dev/null
}
printf 'domain,account_id,ip\na.com,ACCT111,192.0.2.1\n' >"$INV_ROOT/domains-alpha.csv"
assert_equal "$INV_ROOT/domains-alpha.csv" "$(csv_path_case)" \
    "domains_csv_path prefers the only non-empty split inventory"

printf 'domain,account_id,ip\nb.com,ACCT222,192.0.2.2\n' >"$INV_ROOT/domains-beta.csv"
assert_equal "$INV_ROOT/domains.csv" "$(csv_path_case)" \
    "domains_csv_path falls back to the legacy file when ambiguous"

: >"$INV_ROOT/domains-beta.csv"
assert_equal "$INV_ROOT/domains-alpha.csv" "$(csv_path_case)" \
    "domains_csv_path ignores an empty split inventory"

assert_equal "/explicit/path.csv" "$(csv_path_case DOMAINS_FILE=/explicit/path.csv)" \
    "domains_csv_path honours an explicit DOMAINS_FILE"

echo "== domains_csv_for_auth =="
printf 'domain,account_id,ip\nb.com,ACCT222,192.0.2.2\n' >"$INV_ROOT/domains-beta.csv"
printf 'CF_ACCOUNT_ID=ACCT222\n' >"$TMP_DIR/auth-beta.env"
printf 'CF_ACCOUNT_ID=NOSUCH\n' >"$TMP_DIR/auth-missing.env"
auth_case() {
    bash -c 'ROOT_DIR="$1"; . "$0"; domains_csv_for_auth "$2"' \
        "$SCRIPTS_DIR/common.sh" "$INV_ROOT" "$1" 2>/dev/null
}
assert_equal "$INV_ROOT/domains-beta.csv" "$(auth_case "$TMP_DIR/auth-beta.env")" \
    "domains_csv_for_auth maps an account to its inventory"
auth_case "$TMP_DIR/auth-missing.env" >/dev/null 2>&1
assert_status 1 $? "domains_csv_for_auth fails on an unknown account"
auth_case "$TMP_DIR/absent.env" >/dev/null 2>&1
assert_status 1 $? "domains_csv_for_auth fails on a missing auth file"

echo "== csv_split_row =="
# The bug this guards: `IFS=$'\t' read` collapses runs of tab (tab is IFS
# whitespace), so a blank field silently shifts every later value one position
# left. The blank-middle and blank-run cases below both failed that way.
csv_split_row "$(printf 'a\tb\tc')" one two three
assert_equal "a" "$one" "csv_split_row assigns first field"
assert_equal "c" "$three" "csv_split_row assigns last field"

csv_split_row "$(printf 'a\tb\t\tc\td')" f1 f2 f3 f4 f5
assert_equal "" "$f3" "csv_split_row keeps a blank middle field empty"
assert_equal "c" "$f4" "csv_split_row does not shift after a blank field"
assert_equal "d" "$f5" "csv_split_row keeps trailing field aligned"

csv_split_row "$(printf '\t\tz')" g1 g2 g3
assert_equal "" "$g1" "csv_split_row keeps a leading blank field empty"
assert_equal "" "$g2" "csv_split_row keeps consecutive blank fields"
assert_equal "z" "$g3" "csv_split_row aligns after a run of blanks"

csv_split_row "$(printf 'only')" h1 h2 h3
assert_equal "only" "$h1" "csv_split_row assigns the single present field"
assert_equal "" "$h2" "csv_split_row blanks variables past the row"

# Callers pass arbitrary names; internals must not collide with them.
csv_split_row "$(printf 'p\tq')" name row
assert_equal "p" "$name" "csv_split_row tolerates a target named 'name'"
assert_equal "q" "$row" "csv_split_row tolerates a target named 'row'"

echo "== expected_cloudflare_ns =="
assert_equal "addyson.ns.cloudflare.com kanye.ns.cloudflare.com" \
    "$(expected_cloudflare_ns "addyson kanye")" \
    "expected_cloudflare_ns expands short inventory labels"
assert_equal "josephine.ns.cloudflare.com" \
    "$(expected_cloudflare_ns "josephine.ns.cloudflare.com")" \
    "expected_cloudflare_ns leaves an FQDN unchanged"
expected_cloudflare_ns "" >/dev/null 2>&1
assert_status 1 $? "expected_cloudflare_ns fails on empty input"

if [ "$failures" -gt 0 ]; then
    printf "\n%s test(s) failed.\n" "$failures" >&2
    exit 1
fi

printf "\nAll tests passed.\n"
