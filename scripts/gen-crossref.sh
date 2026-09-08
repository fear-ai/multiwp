#!/bin/bash
# Generate scripts/Generated.md: option and helper cross-references.
# Derived from the scripts themselves so the tables cannot drift.
# Usage: ./scripts/gen-crossref.sh > scripts/Generated.md
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPTS_DIR"

cat <<'HDR'
# Generated Cross-References

**This document is generated. Do not edit by hand — regenerate it instead.**

Both tables below are derived from the scripts in `scripts/`. Hand edits are
overwritten and, historically, drift: before this file was split out, the helper
list omitted `slice-logs.sh` (which does source `common.sh`) and `onboard-site.sh`
was missing from both tables.

Regenerate:

```bash
./scripts/gen-crossref.sh > scripts/Generated.md
```

Authority: `scripts/Scripts.md` defines option semantics and is written by hand;
this file only records which script implements what.

---

## Option Cross-Reference (Alphabetical)

Long options are collected from each script's own `case` arms, so this reflects
what is implemented rather than what is documented.

HDR

# Long options: collected from each script's own case arms.
# Arms appear as `name)` or `name=*)` inside `case "${OPTARG}"` (getopts long-option
# dispatch), and as `--name)` in plain argument loops. Bare `--name)` arms that are
# flags of an invoked command (e.g. mysql --skip-column-names) are excluded by
# requiring the arm to assign a shell variable or be a known dispatch form.
for f in *.sh; do
    awk -v file="$f" '
        # Track whether we are inside a case block dispatching on OPTARG or "$1"/"$opt".
        /case[[:space:]]+"?\$\{?OPTARG/ { inopt=1 }
        # auth.sh/cli.sh parse shared long options in helpers that dispatch on
        # $opt rather than $OPTARG; those arms are real CLI options too.
        /case[[:space:]]+"\$opt"/           { inopt=1 }
        /^[[:space:]]*esac/            { inopt=0 }
        inopt && match($0, /^[[:space:]]*(--)?[a-zA-Z][a-zA-Z0-9-]*(=\*)?\)/) {
            arm = substr($0, RSTART, RLENGTH)
            gsub(/^[[:space:]]*/, "", arm)
            gsub(/\)$/, "", arm)
            gsub(/=\*$/, "", arm)
            gsub(/^-+/, "", arm)
            if (arm != "help" && length(arm) > 1)
                printf "%s\t%s\n", arm, file
        }
    ' "$f" 2>/dev/null
done | sort -u -t"$(printf '\t')" -k1,1 -k2,2 | awk -F'\t' '
    { if ($1 != prev) { if (prev) printf "\n"; printf "- --%s,%s", $1, $2; prev=$1 }
      else printf ";%s", $2 }
    END { if (prev) printf "\n" }'

echo
echo "Short options (getopts):"
echo
for f in *.sh; do
    awk -v file="$f" '
        /while[[:space:]]+getopts/ { ing=1 }
        ing && match($0, /^[[:space:]]*[a-zA-Z])/) {
            arm = substr($0, RSTART, RLENGTH); gsub(/[[:space:]()]/, "", arm)
            printf "%s\t%s\n", arm, file
        }
        /^[[:space:]]*esac/ { ing=0 }
    ' "$f" 2>/dev/null
done | sort -u -t"$(printf '\t')" -k1,1 -k2,2 | awk -F'\t' '
    { if ($1 != prev) { if (prev) printf "\n"; printf "- -%s,%s", $1, $2; prev=$1 }
      else printf ";%s", $2 }
    END { if (prev) printf "\n" }'

cat <<'HDR2'

## Helper Inclusion Cross-Reference

Which program and test scripts source each helper library.

HDR2

for helper in common.sh cli.sh cmd.sh auth.sh orch.sh mcp.sh; do
    users=$(grep -l "SCRIPTS_DIR/$helper\"" *.sh 2>/dev/null |
            grep -v "^$helper$" | tr '\n' ';' | sed 's/;$//')
    printf -- "- %s: %s\n" "$helper" "${users:-(none)}"
done
