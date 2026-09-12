#!/bin/bash
# onboard-site.sh - Onboard a domain: create the Cloudflare zone/DNS, then the redirect rule if applicable.
# For options, environment variables, defaults see usage().
#
# Example: onboard-site.sh --domain example.com --site-type redirect --redirect-url https://example.net/

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DEFAULT_SITE_TYPE="redirect"
# Estate-specific values are never hardcoded in a committed file (see Shell.md).
# They come from the operator config (~/.config/multiwp/site.conf) via
# load_operator_conf, or from the environment. Empty means "no default": the
# corresponding flag simply is not forwarded, and the child script applies its
# own default or reports the missing value.
DEFAULT_REDIRECT_URL="${REDIRECT_TARGET_URL-}"
DEFAULT_AUTH_FILE="${DEFAULT_AUTH_FILE-}"

DOMAINS=()
DRY_RUN=false
SITE_TYPE=""
SITE_TYPE_SET=false
REDIRECT_URL_SET=false
AUTH_FILE_SET=false
PASSTHROUGH_ARGS=()

usage() {
    cat <<EOF
onboard-site.sh - Onboard a domain: create the Cloudflare zone/DNS, then the redirect rule if applicable.
Example: onboard-site.sh domain.tld
Example: onboard-site.sh --domain example.com --site-type redirect --redirect-url https://example.net/

Options:
  --domain NAME  Domain to onboard (repeatable; positional also accepted)
  --site-type TYPE  Inventory site_type (singlesite, multisite, redirect, worker, ignore, none; default: $DEFAULT_SITE_TYPE)
  --help  Show this help

All other options (--ip, --redirect-url, --registrar, --dns-provider, --domains-file,
--date, --norecord, --downgrade, and Cloudflare auth options --auth, --auth-file,
--account, --account-name, --token, --key, --email, --ca-key) are forwarded as-is to
onboard-zone.sh and, when applicable, cloud-redirect.sh. See scripts/Scripts.md for
the full option reference of each wrapped script.

Defaults (used only when the corresponding option/env var is not supplied):
  --site-type $DEFAULT_SITE_TYPE
  --redirect-url $DEFAULT_REDIRECT_URL
  --auth-file $DEFAULT_AUTH_FILE

Notes:
  - With no options, "onboard-site.sh domain.tld" onboards a redirect to REDIRECT_TARGET_URL
    domain using the shared Cloudflare account auth file.
  - Runs onboard-zone.sh first to create/ensure the zone, DNS records, and domains.csv entry.
  - When --site-type redirect is set, also runs cloud-redirect.sh to create the redirect rule.
  - For site_type multisite, singlesite, worker, ignore, or none, only onboard-zone.sh runs;
    remaining steps (Apache vhost, origin cert, install-site.sh, etc.) are printed as next steps
    rather than attempted, since those require prerequisites this script does not verify.
EOF
}

# Forwards a long option to PASSTHROUGH_ARGS, consuming a following value token
# unless the option was given in --opt=value form.
forward_valued_opt() {
    local optarg="$1"
    if [[ "$optarg" == *=* ]]; then
        PASSTHROUGH_ARGS+=("--${optarg}")
        return 0
    fi
    PASSTHROUGH_ARGS+=("--${optarg}")
    if [ -n "${!OPTIND-}" ]; then
        PASSTHROUGH_ARGS+=("${!OPTIND}")
        OPTIND=$((OPTIND+1))
    fi
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                site-type=*) SITE_TYPE="${OPTARG#*=}"; SITE_TYPE_SET=true ;;
                site-type)
                    [ -n "${!OPTIND-}" ] || err "--site-type requires a value"
                    SITE_TYPE="${!OPTIND}"
                    SITE_TYPE_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                redirect-url|redirect-url=*)
                    REDIRECT_URL_SET=true
                    forward_valued_opt "${OPTARG}"
                    ;;
                auth-file|auth-file=*)
                    AUTH_FILE_SET=true
                    forward_valued_opt "${OPTARG}"
                    ;;
                norecord|downgrade)
                    PASSTHROUGH_ARGS+=("--${OPTARG}")
                    ;;
                # cloud-redirect.sh implements --dry-run; onboard-zone.sh does not.
                # Forwarding it to both made every --dry-run run abort in the zone
                # stage, so it is tracked separately and applied only to the
                # redirect stage, with the zone stage skipped to match intent.
                dry-run)
                    DRY_RUN=true
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    else
                        # Forward anything else (auth options, --ip, etc.) to the wrapped
                        # scripts unchanged, taking a value unless it is a known flag.
                        forward_valued_opt "${OPTARG}"
                    fi
                    ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

if [ ${#DOMAINS[@]} -eq 0 ]; then
    [ $# -ge 1 ] || { usage; exit 1; }
    DOMAINS+=("$1")
    shift
fi

[ $# -eq 0 ] || err "Too many positional arguments: $*"
finalize_domains DOMAINS || { usage; exit 1; }
[ ${#DOMAINS[@]} -eq 1 ] || err "onboard-site.sh accepts exactly one domain per run"

domain="${DOMAINS[0]}"

if [ "$SITE_TYPE_SET" = false ]; then
    SITE_TYPE="$DEFAULT_SITE_TYPE"
    SITE_TYPE_SET=true
fi
if [ "$SITE_TYPE" = "redirect" ] && [ "$REDIRECT_URL_SET" = false ] && [ -z "${REDIRECT_URL-}" ]; then
    PASSTHROUGH_ARGS+=("--redirect-url" "$DEFAULT_REDIRECT_URL")
fi
if [ "$AUTH_FILE_SET" = false ] && [ -z "${CF_AUTH_FILE-}" ]; then
    PASSTHROUGH_ARGS+=("--auth-file" "$DEFAULT_AUTH_FILE")
fi

ZONE_SCRIPT="$SCRIPTS_DIR/onboard-zone.sh"
REDIRECT_SCRIPT="$SCRIPTS_DIR/cloud-redirect.sh"
[ -x "$ZONE_SCRIPT" ] || err "Missing script: $ZONE_SCRIPT"
[ -x "$REDIRECT_SCRIPT" ] || err "Missing script: $REDIRECT_SCRIPT"

section "ZONE" "Create"
kv "DOMAIN" "$domain"
# SITE_TYPE_SET is unconditionally true by this point (set above when the caller
# omitted --site-type), so it is not re-tested here.
kv "SITE_TYPE" "$SITE_TYPE"

zone_args=("${PASSTHROUGH_ARGS[@]}" "--site-type" "$SITE_TYPE" "--domain" "$domain")

# Report which stage failed. Under `set -e` a bare call aborts the wrapper with
# no indication of how far onboarding got, leaving the operator unsure whether
# the zone exists.
if [ "$DRY_RUN" = true ]; then
    log "Dry run: would run $ZONE_SCRIPT ${zone_args[*]}"
elif ! "$ZONE_SCRIPT" "${zone_args[@]}"; then
    err "Zone provisioning failed for $domain; redirect rule not attempted"
fi

# normalize_site_type so "Redirect" or a decorated value takes the same branch.
if [ "$(normalize_site_type "$SITE_TYPE")" = "redirect" ]; then
    log "site_type=redirect; creating redirect rule for $domain"
    redirect_args=("${PASSTHROUGH_ARGS[@]}" "--domain" "$domain")
    [ "$DRY_RUN" = true ] && redirect_args+=("--dry-run")
    if ! "$REDIRECT_SCRIPT" "${redirect_args[@]}"; then
        err "Zone was provisioned for $domain but the redirect rule failed; rerun cloud-redirect.sh"
    fi
    section "ZONE" "NextSteps"
    kv "DOMAIN" "$domain"
    kv "NEXT" "set the zone nameservers at the registrar, then rerun check-edge.sh"
    status_pass "onboard=done site_type=redirect domain=$domain"
    exit 0
fi

case "$SITE_TYPE" in
    multisite)
        log "site_type=multisite; remaining manual steps for $domain:"
        log "  1) Issue/install origin cert: ./scripts/get-cert.sh $domain"
        log "  2) Create Apache vhosts: ./scripts/apache-vhost.sh $domain"
        log "  3) Add to multisite: ./scripts/install-site.sh $domain \"<Title>\" <email>"
        log "  4) Verify: ./scripts/check-domain.sh $domain"
        ;;
    singlesite)
        log "site_type=singlesite; remaining manual steps for $domain:"
        log "  1) Issue/install origin cert: ./scripts/get-cert.sh $domain"
        log "  2) Create Apache vhosts: ./scripts/apache-vhost.sh $domain"
        log "  3) Bootstrap WordPress: ./scripts/setup-wp.sh $domain"
        log "  4) Verify: ./scripts/check-domain.sh $domain"
        ;;
    worker|ignore|none|"")
        log "site_type=${SITE_TYPE:-none}; no further onboarding steps required by this script"
        ;;
    *)
        log "site_type=$SITE_TYPE; no known follow-up steps defined, check scripts/Scripts.md"
        ;;
esac

status_pass "onboard=zone-only site_type=${SITE_TYPE:-none} domain=$domain"
