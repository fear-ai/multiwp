#!/bin/bash
# check-auth.sh - Compare domain lists between auth files and domains.csv.
# For options, environment variables, defaults see usage().
#
# Example: check-auth.sh --auth-file ~/.config/cloudflare/alphaeos.auth

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

AUTH_FILE="${CF_AUTH_FILE:-$HOME/.config/cloudflare/default.auth}"
DOMAINS_FILE_LOCAL="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
CHECK_IDS=false

usage() {
    cat <<'EOF'
check-auth.sh - Compare domain lists between auth files and domains.csv.
Example: check-auth.sh --auth-file ~/.config/cloudflare/alphaeos.auth

Options:
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)
  --domains-file PATH [DOMAINS_FILE] (default: domains.csv in repo root)
  --check-ids  Compare zone IDs from auth file, domains.csv, and API
  --help  Show this help

Notes:
  - Uses CF_DOMAINS in the auth file (comma-separated list of domains).
  - If CF_DOMAINS is empty, falls back to CF_ZONE entries in the auth file.
  - If domains.csv contains multiple auth_file values, supply --auth-file to select.
  - --check-ids requires API credentials for the auth file account and will query the API.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                auth-file=*)
                    cf_auth_file "${OPTARG}" "${!OPTIND-}"
                    AUTH_FILE="$CF_AUTH_FILE"
                    ;;
                auth-file)
                    cf_auth_file "${OPTARG}" "${!OPTIND-}"
                    AUTH_FILE="$CF_AUTH_FILE"
                    OPTIND=$((OPTIND+1))
                    ;;
                domains-file=*) DOMAINS_FILE_LOCAL="${OPTARG#*=}" ;;
                domains-file)
                    [ -n "${!OPTIND-}" ] || err "--domains-file requires a value"
                    DOMAINS_FILE_LOCAL="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                check-ids) CHECK_IDS=true ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ -f "$AUTH_FILE" ] || err "Auth file not found: $AUTH_FILE"
[ -f "$DOMAINS_FILE_LOCAL" ] || err "domains.csv not found: $DOMAINS_FILE_LOCAL"

CF_AUTH_FILE="$AUTH_FILE"
DOMAINS_FILE="$DOMAINS_FILE_LOCAL"

AUTH_SOURCE="CF_DOMAINS"
AUTH_DOMAINS_RAW="$(auth_var "$AUTH_FILE" CF_DOMAINS || true)"
AUTH_DOMAINS=()
if [ -n "$AUTH_DOMAINS_RAW" ]; then
    if ! parse_comma_list "$AUTH_DOMAINS_RAW" AUTH_DOMAINS "CF_DOMAINS"; then
        err "CF_DOMAINS contains empty values"
    fi
else
    warn "CF_DOMAINS is empty in $AUTH_FILE"
    AUTH_SOURCE="CF_ZONE"
    AUTH_ZONE_RAW=$(auth_values "$AUTH_FILE" CF_ZONE || true)
    while read -r zone; do
        [ -n "$zone" ] || continue
        AUTH_DOMAINS+=("$zone")
    done <<<"$AUTH_ZONE_RAW"
fi

CSV_DOMAINS_RAW="$(python3 - "$DOMAINS_FILE_LOCAL" "$AUTH_FILE" <<'EOF'
import csv
import os
import sys

csv_path = sys.argv[1]
auth_path = sys.argv[2]

auth_values = set()
rows = []

with open(csv_path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        rows.append(row)
        auth = (row.get("auth_file") or "").strip()
        if auth:
            auth_values.add(auth)

auth_target = auth_path.strip()
if auth_target and auth_target not in auth_values and auth_values:
    base = os.path.basename(auth_target)
    matches = [a for a in auth_values if os.path.basename(a) == base]
    if len(matches) == 1:
        auth_target = matches[0]

if auth_values and auth_target:
    rows = [r for r in rows if (r.get("auth_file") or "").strip() == auth_target]
elif len(auth_values) > 1 and not auth_target:
    raise SystemExit("domains.csv contains multiple auth_file values; pass --auth-file to select")

for row in rows:
    domain = (row.get("domain") or "").strip().lower()
    if domain:
        print(domain)
EOF
)"

CSV_DOMAINS=()
while read -r domain; do
    [ -n "$domain" ] || continue
    CSV_DOMAINS+=("$domain")
done <<<"$CSV_DOMAINS_RAW"

AUTH_SET=()
for domain in "${AUTH_DOMAINS[@]}"; do
    normalized=$(normalize_domain "$domain")
    validate_domain "$normalized" >/dev/null || err "Invalid domain in CF_DOMAINS: $domain"
    AUTH_SET+=("$normalized")
done

CSV_SET=()
for domain in "${CSV_DOMAINS[@]}"; do
    normalized=$(normalize_domain "$domain")
    validate_domain "$normalized" >/dev/null || err "Invalid domain in domains.csv: $domain"
    CSV_SET+=("$normalized")
done

only_in_auth=()
for domain in "${AUTH_SET[@]}"; do
    found=false
    for item in "${CSV_SET[@]}"; do
        if [ "$domain" = "$item" ]; then
            found=true
            break
        fi
    done
    if [ "$found" != true ]; then
        only_in_auth+=("$domain")
    fi
done

only_in_csv=()
for domain in "${CSV_SET[@]}"; do
    found=false
    for item in "${AUTH_SET[@]}"; do
        if [ "$domain" = "$item" ]; then
            found=true
            break
        fi
    done
    if [ "$found" != true ]; then
        only_in_csv+=("$domain")
    fi
done

section "AUTH" "Domains"
kv "AUTH_FILE" "$AUTH_FILE"
kv "AUTH_SOURCE" "$AUTH_SOURCE"
kv "AUTH_DOMAIN_COUNT" "${#AUTH_SET[@]}"
kv "CSV_DOMAIN_COUNT" "${#CSV_SET[@]}"

if [ ${#only_in_auth[@]} -gt 0 ]; then
    warn "Domains listed in ${AUTH_SOURCE} but missing in domains.csv: ${only_in_auth[*]}"
fi
if [ ${#only_in_csv[@]} -gt 0 ]; then
    warn "Domains present in domains.csv but missing in ${AUTH_SOURCE}: ${only_in_csv[*]}"
fi

pre_mismatch=false
if [ ${#only_in_auth[@]} -gt 0 ] || [ ${#only_in_csv[@]} -gt 0 ]; then
    pre_mismatch=true
    if [ "$CHECK_IDS" != true ]; then
        exit 1
    fi
fi

if [ "$CHECK_IDS" = true ]; then
    if [ -n "${CF_AUTH_FILE-}" ]; then
        cf_init_auth "$CF_AUTH_FILE"
    else
        cf_init_auth
    fi
    cf_require_auth "for --check-ids"
    require_cmds jq

    domains_to_check=()
    seen=()
    for domain in "${AUTH_SET[@]}" "${CSV_SET[@]}"; do
        if [ -z "$domain" ]; then
            continue
        fi
        already=false
        for item in "${seen[@]}"; do
            if [ "$domain" = "$item" ]; then
                already=true
                break
            fi
        done
        if [ "$already" != true ]; then
            seen+=("$domain")
            domains_to_check+=("$domain")
        fi
    done

    any_error=false
    any_mismatch=false

    for domain in "${domains_to_check[@]}"; do
        normalized=$(normalize_domain "$domain")
        if ! validate_domain "$normalized" >/dev/null; then
            warn "Invalid domain for ID check: $domain"
            any_error=true
            continue
        fi

        auth_id=""
        csv_id=""
        api_id=""
        auth_status="missing"
        csv_status="missing"
        api_status="missing"

        if auth_val=$(cf_zone_id_from_auth "$normalized"); then
            auth_id="$auth_val"
            auth_status="ok"
        else
            case "$?" in
                3) auth_status="missing-id" ;;
                2) auth_status="no-auth-file" ;;
                *) auth_status="missing" ;;
            esac
        fi

        if csv_val=$(cf_zone_id_from_csv "$normalized"); then
            csv_id="$csv_val"
            csv_status="ok"
        else
            case "$?" in
                3) csv_status="missing-id" ;;
                2) csv_status="no-csv" ;;
                *) csv_status="missing" ;;
            esac
        fi

        api_resp=$(cf_api_request GET "/zones?name=${normalized}&status=active")
        if [ "$(cf_api_success "$api_resp")" = "true" ]; then
            api_id=$(echo "$api_resp" | jq -r '.result[0].id // empty')
            if [ -n "$api_id" ]; then
                api_status="ok"
            else
                api_status="missing"
            fi
        else
            api_status="error"
        fi

        chosen=""
        chosen_src=""
        if [ -n "$auth_id" ]; then
            chosen="$auth_id"
            chosen_src="auth-file"
        elif [ -n "$csv_id" ]; then
            chosen="$csv_id"
            chosen_src="csv"
        elif [ -n "$api_id" ]; then
            chosen="$api_id"
            chosen_src="api"
        else
            any_error=true
        fi

        section "AUTH" "ZoneIds"
        kv "DOMAIN" "$normalized"
        kv "AUTH_ZONE_ID" "$auth_id"
        kv "AUTH_STATUS" "$auth_status"
        kv "CSV_ZONE_ID" "$csv_id"
        kv "CSV_STATUS" "$csv_status"
        kv "API_ZONE_ID" "$api_id"
        kv "API_STATUS" "$api_status"
        if [ -n "$chosen" ]; then
            kv "CHOSEN_ZONE_ID" "$chosen"
            kv "CHOSEN_SOURCE" "$chosen_src"
        else
            warn "No zone ID resolved for $normalized"
        fi

        if [ "$auth_status" = "missing-id" ]; then
            warn "Auth file lists zone name without zone id for $normalized"
        elif [ "$auth_status" = "no-auth-file" ]; then
            warn "Auth file missing or unreadable for $normalized"
        fi
        if [ "$csv_status" = "missing-id" ]; then
            warn "domains.csv entry missing zone id for $normalized"
        elif [ "$csv_status" = "no-csv" ]; then
            warn "domains.csv missing or unreadable for $normalized"
        fi
        if [ "$api_status" = "error" ]; then
            warn "API lookup failed for $normalized: $(cf_api_error_messages "$api_resp")"
        fi

        mismatch=false
        if [ -n "$auth_id" ] && [ -n "$csv_id" ] && [ "$auth_id" != "$csv_id" ]; then
            section "AUTH" "Mismatches"
            warn "Mismatch auth vs csv for $normalized: $auth_id != $csv_id"
            mismatch=true
        fi
        if [ -n "$auth_id" ] && [ -n "$api_id" ] && [ "$auth_id" != "$api_id" ]; then
            section "AUTH" "Mismatches"
            warn "Mismatch auth vs api for $normalized: $auth_id != $api_id"
            mismatch=true
        fi
        if [ -n "$csv_id" ] && [ -n "$api_id" ] && [ "$csv_id" != "$api_id" ]; then
            section "AUTH" "Mismatches"
            warn "Mismatch csv vs api for $normalized: $csv_id != $api_id"
            mismatch=true
        fi

        if [ "$mismatch" = true ]; then
            any_mismatch=true
        fi
        if [ "$auth_status" = "missing-id" ] || [ "$csv_status" = "missing-id" ] || [ "$api_status" = "error" ]; then
            any_error=true
        fi
    done

    if [ "$pre_mismatch" = true ] || [ "$any_mismatch" = true ] || [ "$any_error" = true ]; then
        exit 1
    fi
fi
