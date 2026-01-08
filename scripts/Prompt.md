# Program Script Prompts
Date: January 8, 2026

This file provides copy/paste prompts for applying the standard header and `usage()` format across program scripts in `scripts/`. The prompts are intentionally explicit so the resulting changes are consistent, repeatable, and easy to review. Each prompt targets a single program script and emphasizes that behavior should not change—only documentation structure and ordering. It consolidates the older Prompt0 guidance so there is one place to reference.

## Shared Prompt (Applied Per Script)

Use the following prompt text as the basis for each script-specific prompt. The script-specific sections below simply apply this prompt to an individual file path to reduce ambiguity when running updates.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# <script>.sh - <Short description>.
# For options, environment variables, defaults see usage().
#
# Example: <script>.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
<script>.sh - <Short description>.
Example: <script>.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: <script path>
```

## Script-Specific Prompts

The following prompts apply the shared prompt to each program script. These are intended to be used one at a time to avoid unintended cross-file changes.

### apache-vhost.sh

Use this prompt for Apache vhost provisioning changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# apache-vhost.sh - Add Apache vhosts for WordPress domains.
# For options, environment variables, defaults see usage().
#
# Example: apache-vhost.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
apache-vhost.sh - Add Apache vhosts for WordPress domains.
Example: apache-vhost.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/apache-vhost.sh
```

### cf-check.sh

Use this prompt for Cloudflare settings inspection changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# cf-check.sh - Inspect Cloudflare zone settings via the API.
# For options, environment variables, defaults see usage().
#
# Example: cf-check.sh [OPTIONS] <zone>
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
cf-check.sh - Inspect Cloudflare zone settings via the API.
Example: cf-check.sh [OPTIONS] <zone>

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/cf-check.sh
```

### check-edge.sh

Use this prompt for edge verification changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# check-edge.sh - Validate Cloudflare edge behavior for domains.
# For options, environment variables, defaults see usage().
#
# Example: check-edge.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
check-edge.sh - Validate Cloudflare edge behavior for domains.
Example: check-edge.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/check-edge.sh
```

### check-origin.sh

Use this prompt for origin verification changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# check-origin.sh - Validate origin certificates, Apache configuration, and vhost wiring.
# For options, environment variables, defaults see usage().
#
# Example: check-origin.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
check-origin.sh - Validate origin certificates, Apache configuration, and vhost wiring.
Example: check-origin.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/check-origin.sh
```

### check-wp.sh

Use this prompt for WordPress mapping checks.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# check-wp.sh - Validate WordPress site URLs for domains.
# For options, environment variables, defaults see usage().
#
# Example: check-wp.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
check-wp.sh - Validate WordPress site URLs for domains.
Example: check-wp.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/check-wp.sh
```

### cloud-dns.sh

Use this prompt for Cloudflare DNS provisioning changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
# For options, environment variables, defaults see usage().
#
# Example: cloud-dns.sh <domain> <ipv4> [ipv6]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
Example: cloud-dns.sh <domain> <ipv4> [ipv6]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/cloud-dns.sh
```

### get-cert.sh

Use this prompt for origin certificate issuance changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# get-cert.sh - Issue or install Cloudflare Origin certs and keys for domains.
# For options, environment variables, defaults see usage().
#
# Example: get-cert.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
get-cert.sh - Issue or install Cloudflare Origin certs and keys for domains.
Example: get-cert.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/get-cert.sh
```

### install-site.sh

Use this prompt for multisite provisioning changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# install-site.sh - Add a new site to WordPress multisite and map to an apex domain.
# For options, environment variables, defaults see usage().
#
# Example: install-site.sh [OPTIONS] <domain> [title] [email]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
install-site.sh - Add a new site to WordPress multisite and map to an apex domain.
Example: install-site.sh [OPTIONS] <domain> [title] [email]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/install-site.sh
```

### setup-wp.sh

Use this prompt for base WordPress setup changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# setup-wp.sh - WordPress multisite base configuration.
# For options, environment variables, defaults see usage().
#
# Example: setup-wp.sh
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
setup-wp.sh - WordPress multisite base configuration.
Example: setup-wp.sh

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/setup-wp.sh
```

### verify-cf-auth.sh

Use this prompt for credential validation changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# verify-cf-auth.sh - Validate Cloudflare API credentials.
# For options, environment variables, defaults see usage().
#
# Example: verify-cf-auth.sh [OPTIONS]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
verify-cf-auth.sh - Validate Cloudflare API credentials.
Example: verify-cf-auth.sh [OPTIONS]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/verify-cf-auth.sh
```

### verify-domain.sh

Use this prompt for combined verification changes.

```text
Please update the specified script to conform to the current header and usage conventions.

Header format (top of file):
#!/bin/bash
# verify-domain.sh - Run edge, origin, and WordPress checks for domains.
# For options, environment variables, defaults see usage().
#
# Example: verify-domain.sh [OPTIONS] domain1 [domain2...]
#
# Notes:
# - <note 1>
# - <note 2>

usage() format (first lines only, no extra Usage or Examples blocks):
verify-domain.sh - Run edge, origin, and WordPress checks for domains.
Example: verify-domain.sh [OPTIONS] domain1 [domain2...]

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, root, ssl, common, then --help last.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.

Apply to: scripts/verify-domain.sh
```
