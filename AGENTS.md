# Repository Guidelines

## Project Structure & Module Organization
- Root docs: `CONF.md` (environment prerequisites) and `MULTI.md` (multisite setup notes).
- No compile/build system; operate from the repo root so relative template paths resolve.

`scripts/`: operational Bash scripts
- setup-wp.sh: WordPress multisite bootstrap (expects sudo-capable Ubuntu user).
- apache-vhost.sh: Add domains/hostnames to the network; uses templates and Cloudflare-origin cert paths.
- cloud-dns.sh: Create Cloudflare zone + DNS records via API (no UI interaction).
- cloud-cert.sh: Issue and install certs for the multisite host (cloud/SSL helper).
- install-cert.sh: Validate or install Cloudflare Origin cert/key at `/etc/ssl/cloudflare-origin/{certs,keys}` for SSL vhosts.

`templates/`: WordPress and Apache config templates
- wp-config-multisite*.php
- apache-*.conf
- .htaccess
- Glossary: DNSTerms.md (DNS/Cloudflare terminology)

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

## Structure and Update
- When adding new sections or subjects, leave existing sections intact unless explicitly requested to change them.
- When resequencing, only move sections or paragraphs; do not alter their content.
- When refactoring, you may rewrite or condense, but do not delete or omit existing material unless instructed.
- Order sections so dependencies are introduced before they’re referenced.
- Use an expansive, professional voice and include rationale and dependencies rather than terse summaries.
- When a user says “stop” or “halt,” cease running commands or edits immediately and await further instruction; do not retry failed patches unless asked.
- On apply_patch or command failure, report the issue once and ask before retrying, instead of looping.
