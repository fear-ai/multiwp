# Repository Guidelines

## Project Structure & Module Organization
- Root docs: `CONF.md` (environment prerequisites) and `MULTI.md` (multisite setup notes).
- No compile/build system; operate from the repo root so relative template paths resolve.

`scripts/`: operational Bash scripts
- setup-wp.sh: WordPress multisite bootstrap (expects sudo-capable Ubuntu user).
- add-domains.sh: Add domains/hostnames to an network.
- cloud-cert.sh: Issue and install certs for the multisite host (cloud/SSL helper).

`templates/`: WordPress and Apache config templates
- wp-config-multisite*.php
- apache-*.conf
- .htaccess

## Coding Style & Naming Conventions
- Shell scripts use Bash (`#!/bin/bash`), 4-space indentation, and `set -e` for fail-fast behavior; prefer POSIX-friendly.
- Filenames kebab-case for scripts and template descriptors.
- Defensive checks (user, path, and service guards) and clear echo/log lines for major actions.
- Keep template variables obvious {{PLACEHOLDER}} and document required substitutions.

## Testing Guidelines
- Suggest sanity-checking scripts via `bash -n` or `shellcheck`

## Commit & Pull Request Guidelines
- Commit messages: present-tense, imperative summary: Add domain helper prompts; history focused on operational changes.
- Pull requests may state the environment when relevant or changed, including Ubuntu/PHP/MySQL versions
- Include file references when noting changes; attach logs or screenshots for Apache/WordPress validation when relevant.

## Security & Configuration Tips
- Validate hosts and paths before writing to system locations (`/etc/apache2`, `/var/www/html/wordpress`).
- NEVER hardcode credentials; rely on prompts or environment variables, avoid running as root.
