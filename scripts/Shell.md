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
  -h, --help    Show this help
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
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

- Run as ubuntu with sudo, never as root
- Use `priv()` wrapper from common.sh
- Validate hostnames and paths
- Never hardcode credentials

## Project Idioms

**safe_name()**: Removes dots/hyphens from domain for filenames
```bash
safe=$(safe_name "example.com")  # Returns "examplecom"
```

**priv()**: Sudo wrapper
```bash
priv mkdir -p /etc/ssl/certs
```

**WordPress operations**: Always run as www-data
```bash
priv -u www-data wp --path=/var/www/html/wordpress site list
```
