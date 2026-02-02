# Cloudflare Rulesets Get, Put, and Copy
Date: January 20, 2026

This document defines the design for a Cloudflare rulesets utility named `rules-cf.sh`. The goal is to fetch rules from a single source zone into a portable JSON file and then put those rules to explicitly selected target zones. The design favors clarity, minimal options, and explicit intent over convenience features that hide which zones are being modified.

## Scope and intent
The script focuses on Cloudflare rulesets expressed through the Rulesets API in three phases: firewall (`http_request_firewall_custom`), cache (`http_request_cache_settings`), and rate limiting (`http_ratelimit`). Exported files are meant to be readable, auditable, and reusable across zones without carrying zone-specific metadata. The design intentionally avoids automatic domain discovery and batching so the operator remains in control of which zones are read and modified.

This is a design-only document. Implementation details are described so the script stays consistent with the existing `scripts/` conventions and auth handling, but there is no code in this document that should be executed directly.

## Command interface
The CLI is intentionally small. The defaults are designed for get first, and put is an explicit action. The following usage block is the target shape for the script:

```bash
rules-cf.sh --get --type firewall --src <domain> [--file <domain>_<phase>.json] [--all]
rules-cf.sh --put --type cache --src <domain> --dest <domain> [--dest <domain>...] [--file <domain>_<phase>.json]
rules-cf.sh --copy --type rate --src <domain> --dest <domain> [--dest <domain>...] [--file <domain>_<phase>.json] [--all]
```

Key behaviors:
- `--get` is the default mode. If no mode flag is provided, the script fetches rules from `--src`.
- `--type` selects which ruleset phase to read or write: `firewall`, `cache`, or `rate` (default: `cache`).
- `--src <domain>` specifies the source zone apex for get or copy. This is required in get/copy mode.
- `--file` defaults to `<src>_<phase>.json` where `<phase>` is derived from the selected `--type`.
- `--all` includes disabled rules in the export; without it, only enabled rules are exported.
- `--put` requires at least one `--dest` target. If `--file` is omitted, it defaults to `<src>_<phase>.json` and `--src` must be provided to build the name. There is no `--domains-file` or `--site-type` filtering to avoid accidental bulk edits.
- `--copy` performs `--get` then `--put` using the same `--src`, `--dest`, and `--file`.

## Get workflow
The get operation should follow a simple, auditable path:
1) Resolve the zone ID for the `--src` domain.
2) Read the entrypoint ruleset for the selected phase.
3) Normalize the returned rules into a portable JSON payload, stripping all zone-specific metadata and rule IDs.
4) Write the normalized JSON to the output file path, using the default name when `--file` is omitted.

If the phase has no rules, or if only disabled rules exist and `--all` is not set, the script exits with a clear error so exports cannot silently produce empty files.

The portable payload should contain only a rules list and optional metadata that helps with human review, such as name or description. The file may retain a `phase` field when present in the source ruleset so put can use it directly; if no phase is present, put defaults to the phase associated with `--type`.

## Put workflow
Put is explicit and opt-in. The script should never modify a zone unless `--put` is provided and one or more `--dest` values are specified.

The put flow is:
1) Parse the JSON input file and confirm it contains a list of rules.
2) For each target domain, resolve the zone ID and fetch the existing entrypoint ruleset.
3) Replace the existing rules with the rules from the file. This is a full replacement operation, not a merge.
4) Report which zones were updated and how many rules were written.

This design deliberately avoids a merge feature. Operators should treat the exported rules file as the source of truth and re-put when changes are made.

## Export file format
The exported JSON must be concise and portable. The file should include only rules and a minimal set of metadata that aids review, but it must not include any Cloudflare-generated IDs.

Example export:

```json
{
  "name": "default",
  "description": "",
  "phase": "http_request_firewall_custom",
  "rules": [
    {
      "action": "block",
      "description": "xmlrpc",
      "enabled": true,
      "expression": "(http.request.uri.path eq \"/xmlrpc.php\")"
    }
  ]
}
```

## Authentication and access
The script should use the existing `auth.sh` helpers so it supports the same authentication modes and environment variables as the other Cloudflare scripts. The operator must supply either a scoped API token or a global API key + email pair with permission to read and update rulesets on the target zones. As a matter of policy, this script should never attempt to infer credentials from a zone; it should only rely on the explicit auth file or environment variables provided.

## Deferred items and explicit exclusions
Some features are intentionally postponed in order to keep the first version safe and predictable:
- Host-specific expressions such as `http.host` or `http.request.host` are not rewritten or validated yet. If they appear in the exported file, they will be applied as-is. A future enhancement can add warnings or rewrite logic if needed.
- There is no merge mode and no bulk selection via `--domains-file` or `--site-type`.

This scope keeps the tool simple and aligns it with the current operational maturity: get from one known-good zone and put to a defined list of targets.
