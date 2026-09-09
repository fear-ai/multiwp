#!/bin/bash
# back-wp.sh - Freeze WordPress file changes and create backups for a domain.
# For options, environment variables, defaults see usage().
#
# Example: back-wp.sh --domain zero.directory --backup-directory /var/backups/wp/zero.directory

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
BACKUP_DIR=""
RUN_ID=""
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
back-wp.sh - Freeze WordPress file changes and create backups for a domain.
Example: back-wp.sh --domain zero.directory --backup-directory /var/backups/html/zero.directory

Options:
  --domain NAME  Domain to back up (repeatable; positional also accepted)
  --backup-directory DIR  Backup directory (default: /var/backups/html/<wp-root-basename>)
  --run-id ID  Override the run identifier used in filenames
$(cli_usage_common_priv)
  --help  Show this help

Notes:
  - This script sets DISALLOW_FILE_MODS to true, activates maintenance mode,
    exports the database, archives wp-content, and then deactivates maintenance mode.
  - Backups are written to the backup directory using the domain and run ID in filenames.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                backup-directory=*) BACKUP_DIR="${OPTARG#*=}" ;;
                backup-directory)
                    [ -n "${!OPTIND-}" ] || err "--backup-directory requires a path"
                    BACKUP_DIR="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                run-id=*) RUN_ID="${OPTARG#*=}" ;;
                run-id)
                    [ -n "${!OPTIND-}" ] || err "--run-id requires a value"
                    RUN_ID="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_common_opt "${OPTARG}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

for domain in "$@"; do
    DOMAINS+=("$domain")
done
finalize_domains DOMAINS || { usage; exit 1; }
[ ${#DOMAINS[@]} -ge 1 ] || { usage; exit 1; }

cli_require_non_root
require_cmds wp tar

resolve_wp_root_for_domain() {
    local domain="$1"
    local site_type=""
    local wp_root=""
    local row
    if row=$(csv_get_domain_fields "$domain" site_type wp_root 2>/dev/null || true); then
        IFS=$'\t' read -r site_type wp_root <<<"$row"
    fi
    site_type=$(normalize_site_type "$site_type")
    if [ -n "$wp_root" ]; then
        echo "$wp_root"
        return 0
    fi
    if [ "$site_type" = "singlesite" ]; then
        echo "/var/www/html/$domain"
        return 0
    fi
    echo "$WORDPRESS_ROOT"
}

backup_domain() {
    # Not local: the EXIT trap below runs at script scope, where function locals
    # are already gone. A local here made cleanup fail with "unbound variable"
    # and left DISALLOW_FILE_MODS set on the site. wp_root and domain are read
    # by cleanup too, so they must outlive the function for the same reason.
    domain="$1"
    wp_root="$2"
    maintenance_on=false
    mods_modified=false
    mods_value=""
    wp_config=""
    local backup_dir="$3"
    local run_id="$4"
    local needs_mods=false

    # Both RETURN and EXIT fire on an aborted backup, so cleanup runs twice.
    # Each branch clears its own flag, making the second pass a no-op.
    cleanup() {
        if [ "${maintenance_on:-false}" = true ]; then
            maintenance_on=false
            priv -u www-data wp --path="$wp_root" maintenance-mode deactivate >/dev/null 2>&1 || true
        fi
        if [ "${mods_modified:-false}" = true ]; then
            mods_modified=false
            if priv -u www-data wp --path="$wp_root" config set DISALLOW_FILE_MODS false --raw >/dev/null 2>&1; then
                :
            else
                priv wp --allow-root --path="$wp_root" config set DISALLOW_FILE_MODS false --raw >/dev/null 2>&1 || true
            fi
        fi
    }
    # RETURN alone does not fire when set -e aborts the function, which would
    # leave the site in maintenance mode with DISALLOW_FILE_MODS set - an
    # outage lasting until someone clears it by hand. EXIT covers the abort and
    # the signals cover an interrupted backup.
    trap cleanup RETURN EXIT INT TERM

    section "BACKUP" "Freeze"
    kv "DOMAIN" "$domain"
    kv "WP_ROOT" "$wp_root"
    kv "BACKUP_DIR" "$backup_dir"
    kv "RUN_ID" "$run_id"

    # 0750: the dump holds the full site database, including user tables. A
    # default-umask directory (0755) exposes it to every local user.
    priv install -d -m 750 "$backup_dir"
    wp_config="$wp_root/wp-config.php"
    mods_value=$(priv -u www-data wp --path="$wp_root" config get DISALLOW_FILE_MODS 2>/dev/null || true)
    # mods_modified drives the cleanup that resets DISALLOW_FILE_MODS to false,
    # so it must mean "this run set it", not "this run intends to set it". Were
    # it set before the config write, a failed write would abort under set -e
    # and cleanup would clear the flag on a site that already had it true.
    case "$mods_value" in
        true|TRUE|1) needs_mods=false ;;
        *) needs_mods=true ;;
    esac
    if [ "$needs_mods" = true ]; then
        if ! priv -u www-data wp --path="$wp_root" config set DISALLOW_FILE_MODS true --raw; then
            warn "wp-config.php not writable by www-data; using sudo to update $wp_config"
            priv wp --allow-root --path="$wp_root" config set DISALLOW_FILE_MODS true --raw
        fi
        mods_modified=true
    fi

    section "BACKUP" "Archive"
    priv -u www-data wp --path="$wp_root" maintenance-mode activate
    maintenance_on=true

    local db_file="${backup_dir}/${domain}_${run_id}.sql"
    local content_file="${backup_dir}/${domain}_wp-content_${run_id}.tgz"

    priv -u www-data wp --path="$wp_root" db export "$db_file"
    priv tar -czf "$content_file" -C "$wp_root" wp-content
    # wp/tar create these at the process umask (commonly 0644). Restrict them:
    # the dump contains the whole database, the archive the whole content tree.
    priv chmod 640 "$db_file" "$content_file"

    priv -u www-data wp --path="$wp_root" maintenance-mode deactivate
    maintenance_on=false

    echo "Database backup: $db_file"
    echo "wp-content backup: $content_file"
    status_pass "DOMAIN=$domain"
}

for domain in "${DOMAINS[@]}"; do
    run_id="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
    wp_root=$(resolve_wp_root_for_domain "$domain")
    backup_dir="${BACKUP_DIR:-/var/backups/html/${wp_root##*/}}"
    backup_domain "$domain" "$wp_root" "$backup_dir" "$run_id"
done
