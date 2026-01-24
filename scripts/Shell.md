# Shell Script Conventions
Date: January 8, 2026

This document defines Bash development conventions for the scripts in this repository. It focuses on technique and structure for the shared script infrastructure, and it points to other documents for the full catalog of script arguments and environment variables.

This document is authoritative for Bash conventions and shared helper usage. `scripts/Scripts.md` is authoritative for option and environment variable definitions, including current interface conventions and validations.

## Baseline Bash Practices

The scripts prioritize predictable behavior, explicit error handling, and clear input validation. These conventions are the foundation for the shared helpers and are expected in all program scripts.

- Use `set -euo pipefail` near the top of each script to fail fast and prevent silent errors.
- Quote variables (`"$var"`) and use `$(...)` instead of backticks for command substitution.
- Use `lowercase_with_underscores` for functions, `UPPERCASE_WITH_UNDERSCORES` for constants, and kebab-case for filenames.
- Validate inputs early and exit with `err()` for fatal issues.

## Script Structure and Dependencies

Program scripts follow a consistent structure so shared helpers remain predictable. Scripts derive the repository root first, then source helpers from the repo’s `scripts/` directory. Only source what you need.

- Always derive `ROOT_DIR` from `BASH_SOURCE[0]`, then set `SCRIPTS_DIR="$ROOT_DIR/scripts"` so scripts run correctly from any working directory.
- Source `common.sh` first, then `cli.sh` or `auth.sh` as needed, using `SCRIPTS_DIR` to avoid path ambiguity.
- Use `require_cmd` for external dependencies before running logic.

## Logging, Status, and Error Conventions

The shared helpers establish the baseline logging and error behavior that all scripts should follow. The intent is to keep critical failures obvious and to make it safe for scripts to continue collecting results after a non-fatal failure.

The functions below are defined in `scripts/common.sh` and are the canonical entry points for logging and error signaling. Scripts that implement structured output can still emit their own `PASS/INFO/ERROR` lines, but the helpers remain the default for human-readable logs and for fatal exit behavior.

| Helper | Prefix | Stream | Exit behavior | Intended use |
| --- | --- | --- | --- | --- |
| `log` | `[HH:MM:SS]` | stdout | continue | Normal progress and informational output |
| `warn` | `[HH:MM:SS] Warning:` | stderr | continue | Non-fatal anomalies that should be noticed |
| `fail` | `[HH:MM:SS] FAIL:` | stderr | continue | A check failed but the script should continue collecting results |
| `err` | `[HH:MM:SS] ERROR:` | stderr | exit 1 | Fatal error; stop immediately |

For the planned unified output format (see `scripts/Scripts.md`), non-fatal failures should still use `fail()` internally but emit an `ERROR` status line in the structured output. This keeps the external output consistent while preserving the fatal/non-fatal distinction in script control flow.

## Options and Usage Formatting

Option parsing is a contract with operators, so `usage()` must be accurate and stable. For canonical option lists and script-specific details, refer to `scripts/Scripts.md`. The `scripts/Options.csv` cross-reference lists which scripts implement each option.

The repository standard is a single heredoc for `usage()` and a short title plus single-line example at the top of usage. Ordering must be consistent: script-specific options first, then auth, then root/ssl paths, then common privilege options, and `--help` last. The exact format and rules are captured in `scripts/Scripts.md`.

## Heredoc Conventions and File Emission

Heredocs are used throughout the scripts for `usage()` blocks and for inline Python or stub files in tests. To avoid delimiter collisions and to keep behavior consistent, use the following conventions:

- Use `<<'EOF'` for literal heredocs (no variable expansion). This is the default for `usage()` output, embedded Python blocks, and test fixtures.
- Use `<<EOF` only when you explicitly need variable expansion inside the heredoc body.
- When emitting a script that itself contains a heredoc, use `SCRIPT_EOF` for the outer delimiter (`<<'SCRIPT_EOF'`). This prevents the outer heredoc from terminating early when the inner script contains `EOF`.

Why this matters:
- A heredoc terminator is matched by line content, not by quoting. If the body contains a line with just `EOF`, the outer heredoc ends early, which truncates the file and produces syntax errors.
- Standardizing on `EOF` for inner heredocs and `SCRIPT_EOF` for outer generation avoids accidental collisions and makes the patterns predictable.

Preferred file emission method:
- Use `apply_patch` to add or update scripts when possible. It does not parse heredoc markers and therefore cannot be confused by nested heredocs. It also produces smaller, safer diffs for review.

Future transition:
- As scripts evolve, prefer migrating any file-generation steps away from shell heredocs and toward `apply_patch` or dedicated templates. This keeps complex scripts maintainable and reduces the risk of accidental truncation.

## Configuration Processing

Configuration flows are layered so defaults are predictable and priority is explicit. Scripts should apply these patterns consistently so operators can reason about outcomes without reading implementation details.

Priority (lowest to highest):
- Code defaults
- Auth file values (when a script uses `auth.sh`)
- Environment variables
- CLI options

Auth files are inputs of convenience, not authority. Values loaded from an auth file must yield to environment variables and CLI options so automation can set values without editing files.

Boolean handling is centralized in `common.sh` via `parse_bool`. Scripts must normalize auth-file or environment booleans to `true|false`, reject unknown tokens, and treat empty values as “use the default.” For option inputs, prefer value-style `--name=true|false` so the priority is explicit.

Domain handling is centralized in `common.sh`: `normalize_domain` trims and lowercases; `validate_domain` enforces label rules; `finalize_domains` normalizes, validates, and de-duplicates lists. Redirect-only domains are loaded from `domains.csv` via `load_dns_redirects` and checked with `is_redirect_domain` so origin/WP validators can skip expected redirects.

## Shared Helpers and Common Options

The helper libraries provide common logic for privileges, argument parsing, and Cloudflare authentication. Use them to keep behavior consistent across scripts and to avoid duplicated logic. `scripts/Scripts.md` and `scripts/Helpers.csv` summarize where helpers are used; this section stays focused on roles and key functions.

Key helpers:
- `priv()` in `common.sh` centralizes privilege escalation via `sudo`.
- `safe_name()` in `common.sh` creates safe filenames from domains.
- `normalize_domain`, `validate_domain`, `finalize_domains`, and `validate_ip` in `common.sh` keep domain and IP inputs consistent and safe.
- `cli_usage_*`, `cli_*_opt`, and `cli_cf_auth_opt` in `cli.sh` standardize argument parsing and help output.
- `auth.sh` centralizes Cloudflare auth handling and API request helpers.

## Security and Operational Discipline

Run scripts as a sudo-capable operator (for example, `ubuntu`) and use `priv()` for elevated actions. Avoid running as root. Only disable sudo with `--no-sudo` when the environment is constrained and you understand the impact. Never hardcode credentials; use environment variables or auth files as documented in `scripts/Scripts.md` and `scripts/example.auth`.
