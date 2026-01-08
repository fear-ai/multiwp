# Shell Script Conventions
Date: January 8, 2026

This document defines Bash development conventions for the scripts in this repository. It focuses on technique and structure for the shared script infrastructure, and it points to other documents for the full catalog of script arguments and environment variables.

## Baseline Bash Practices

The scripts prioritize predictable behavior, explicit error handling, and clear input validation. These conventions are the foundation for the shared helpers and are expected in all program scripts.

- Use `set -euo pipefail` near the top of each script to fail fast and prevent silent errors.
- Quote variables (`"$var"`) and use `$(...)` instead of backticks for command substitution.
- Use `lowercase_with_underscores` for functions, `UPPERCASE_WITH_UNDERSCORES` for constants, and kebab-case for filenames.
- Validate inputs early and exit with `err()` for fatal issues.

## Script Structure and Dependencies

Program scripts follow a consistent structure so shared helpers remain predictable. Most scripts should set `SCRIPT_DIR` and source helper libraries from there. Only source what you need.

- Always derive `SCRIPT_DIR` using `BASH_SOURCE[0]` so scripts run correctly from any working directory.
- Source `common.sh` first, then `cli.sh` or `auth.sh` as needed.
- Use `require_cmd` for external dependencies before running logic.

## Options and Usage Formatting

Option parsing is a contract with operators, so `usage()` must be accurate and stable. For canonical option lists and script-specific details, refer to `scripts/Arguments.md`. The `scripts/Options.csv` cross-reference lists which scripts implement each option.

The repository standard is a single heredoc for `usage()` and a short title plus single-line example at the top of usage. Ordering must be consistent: script-specific options first, then auth, then root/ssl paths, then common privilege flags, and `--help` last. The exact format and rules are captured in `scripts/Prompt.md`.

## Shared Helpers and Common Flags

The helper libraries provide common logic for privileges, argument parsing, and Cloudflare authentication. Use them to keep behavior consistent across scripts and to avoid duplicated logic. The definitive list of helper usage and script environments lives in `scripts/Arguments.md`, while `scripts/Helpers.csv` summarizes which scripts source each helper.

Key helpers:
- `priv()` in `common.sh` centralizes privilege escalation via `sudo`.
- `safe_name()` in `common.sh` creates safe filenames from domains.
- `cli_usage_*` and `cli_handle_*` in `cli.sh` standardize argument parsing and help output.
- `auth.sh` centralizes Cloudflare auth handling and API request helpers.

## Security and Operational Discipline

Run scripts as a sudo-capable operator (for example, `ubuntu`) and use `priv()` for elevated actions. Avoid running as root. Only disable sudo with `--no-sudo` when the environment is constrained and you understand the impact. Never hardcode credentials; use environment variables or auth files as documented in `scripts/Arguments.md` and `scripts/example.auth`.
