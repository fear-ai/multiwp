# Shell Script Conventions

## Script Structure

```bash
#!/bin/bash
# script-name.sh - Brief description
#
# Usage: script-name.sh [OPTIONS] <required> [optional]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

require_cmd dependency

usage() {
    cat <<'EOF'
Usage: script-name.sh [OPTIONS] <domain>
Description of what this does.
Options:
  --help        Show this help
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage; exit 0 ;;
        -*) err "Unknown option: $1" ;;
        *) break ;;
    esac
    shift
done

[ $# -ge 1 ] || { usage; exit 1; }

DOMAIN="$1"

log "Starting operation for $DOMAIN"
# Main logic here
log "Completed successfully"
```

## Style

- 4-space indentation
- Quote variables: `"$var"`
- Use `$()` not backticks
- Functions: lowercase_with_underscores
- Constants: UPPERCASE_WITH_UNDERSCORES
- Files: kebab-case.sh

## Error Handling

- Use `err()` from common.sh for fatal errors
- Use `log()` for informational messages
- Validate inputs early
- Check existence before operations

## Security

- Run as a user with sudo privileges, never as root
- Use `priv()` wrapper from common.sh
- Validate hostnames and paths
- Never hardcode credentials

Some validation scripts accept `--allow-root` (skip the root guard) and `--no-sudo` (disable sudo usage). Use these only in constrained environments where sudo is unavailable or you are intentionally running as root, and understand that `priv()` will then run commands as the current user.

## Project Idioms

**safe_name()**: Removes dots/hyphens from domain for filenames
```bash
safe=$(safe_name "example.com")  # Returns "examplecom"
```

**cli.sh helpers**: Shared option parsing and usage lines for common flags.
Use these helpers so `--root`, `--ssl-dir`, `--allow-root`, `--no-sudo`, and Cloudflare auth flags behave consistently across scripts.
```bash
if cli_handle_root_opt "${OPTARG}" WORDPRESS_ROOT_LOCAL "${!OPTIND-}"; then
    :
fi
```
```bash
cli_usage_root
cli_usage_ssl_dir
```

**priv()**: Sudo wrapper
```bash
priv mkdir -p /etc/ssl/certs
```
`priv()` is a thin wrapper around `sudo` that centralizes privilege escalation. The intent is to run scripts as a sudo-capable operator (for example, `ubuntu`) and elevate only for the specific filesystem or service actions that require it. This reduces blast radius while keeping operational commands consistent across scripts.

Example: run a command as the web user while keeping the script itself under the operator account. This is the intended pattern for WP-CLI so file ownership and permissions match the web server user.
```bash
priv -u www-data wp --path=/var/www/html/wordpress option get home
```

Reference: the implementation lives in `scripts/common.sh` and can be switched off for constrained environments by setting `SUDO_BIN` to an empty string in that file. Keep the wrapper in place even when disabling sudo so the calling pattern remains consistent.

**WordPress operations**: Always run as www-data
```bash
priv -u www-data wp --path=/var/www/html/wordpress site list
```
