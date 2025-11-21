# multiwp repository OpenAI Codex settings

## Project Structure & Modules
- Internal or proprietary server-specific settings: `CONF.md`
- WordPress Multisite configuration project:`MULTI.md`
- No compile/build system currently; may need to operate from the repo root for relative template and script paths
- Glossary of SSL/DNS/Cloudflare terminology: `DNSTerms.md`

`scripts/`: operational Bash scripts
- apache-vhost.sh: Add domains/hostnames to the network; uses templates and Cloudflare-origin cert paths.
- cloud-dns.sh: Create Cloudflare zone + DNS records via API (no UI interaction).
- cloud-cert.sh: Issue and install certs for the multisite host (cloud/SSL helper).
- install-cert.sh: Validate or install Cloudflare Origin cert/key, default `/etc/ssl/cloudflare-origin/`
- [obsole right now] setup-wp.sh: WordPress Multisite setup

`templates/`: WordPress and Apache config templates
- wp-config-multisite*.php
- apache-*.conf
- .htaccess

## Coding Style & Naming Conventions
- Shell scripts use Bash `#!/bin/bash`, 4-space indentation, `set -e` for fail-fast behavior; prefer POSIX-friendly.
- Filenames kebab-case for scripts and template descriptors.
- Defensive checks (user, path, and service guards) and clear echo/log lines for major actions.
- Keep template variables obvious {{PLACEHOLDER}} and document required substitutions.

## Security & Configuration
- Validate hosts and paths before writing to system locations (`/etc/apache2`, `/var/www/html/wordpress`).
- NEVER hardcode credentials; rely on prompts or environment variables, avoid running as root.

## Testing
- Suggest sanity-checking scripts via `bash -n` or `shellcheck`

## Commit & Pull Request
- Commit messages: present-tense, imperative summary, history focused on operational changes: "Add domain helper prompts"
- Pull requests may state the development, test, operaing systemenvironment, when relevant or changeds. May include Node, Ubuntu/PHP/MySQL versions.
- Include file references when noting changes; attach logs or screenshots for Apache/WordPress validation when relevant.

## Structure and Update
- When adding new sections or subjects, leave existing sections intact unless explicitly requested to change them.
- When resequencing, only move sections or paragraphs; do not alter their content.
- When refactoring, you may rewrite or condense, but do not delete or omit existing material unless instructed.
- Order sections so dependencies are introduced before they’re referenced.
- Use an expansive, professional voice and include rationale and dependencies rather than terse summaries.
- When a user says “stop” or “halt,” cease running commands or edits immediately and await further instruction; do not retry failed patches unless asked.
- on command failure, report the issue once and ask before retrying, instead of looping.
- Do not run git commands (status/add/commit) unless explicitly instructed; leave commits to user.
- When told to “read” or “input” a file, open and quote the current version from the repository rather than relying on prior context or memory so instructions reflect the actual on-disk content.
- Titles and subtitles should be plain, with no commentary or parenthetical remarks in the heading.
