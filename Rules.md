# Cloudflare Firewall Rules Export and Apply
Date: January 20, 2026

This document defines the initial design for a Cloudflare firewall rules utility named `rules-cf.sh`. The goal is to export firewall rules from a single source zone into a portable JSON file and then apply those rules to explicitly selected target zones. The design favors clarity, minimal options, and explicit intent over convenience features that hide which zones are being modified.

## Scope and intent
The script focuses on Cloudflare firewall rules expressed through the Rulesets API in the `http_request_firewall_custom` phase. Exported files are meant to be readable, auditable, and reusable across zones without carrying zone-specific metadata. The design intentionally avoids automatic domain discovery and batching so the operator remains in control of which zones are read and modified.

This is a design-only document. Implementation details are described so the eventual script can be built consistently with the existing `scripts/` conventions and auth handling, but there is no code in this document that should be executed directly.

## Command interface
The CLI is intentionally small. The defaults are designed for export first, and apply is an explicit action. The following usage block is the target shape for the script:

```bash
rules-cf.sh --export --source <domain> [--output rules.<domain>.json] [--all]
rules-cf.sh --apply --domain <domain> [--domain <domain>...] [--input rules.<domain>.json]
```

Key behaviors:
- `--export` is the default mode. If no mode flag is provided, the script exports.
- `--source <domain>` specifies the source zone apex for export. This is required in export mode.
- `--output` defaults to `rules.<domain>.json` where `<domain>` is the normalized zone name.
- `--all` includes disabled rules in the export; without it, only enabled rules are exported.
- `--apply` requires at least one `--domain` target. If `--input` is omitted, it defaults to `rules.<domain>.json` using the first target domain. There is no `--domains-file` or `--site-type` filtering to avoid accidental bulk edits.

## Export workflow
The export operation should follow a simple, auditable path:
1) Resolve the zone ID for the `--source` domain.
2) Read the entrypoint ruleset for `http_request_firewall_custom`.
3) Normalize the returned rules into a portable JSON payload, stripping all zone-specific metadata and rule IDs.
4) Write the normalized JSON to the output file path, using the default name when `--output` is omitted.

The portable payload should contain only a rules list and optional metadata that helps with human review, such as name or description. The file may retain a `phase` field when present in the source ruleset so apply can use it directly; if no phase is present, apply defaults to `http_request_firewall_custom`.

## Apply workflow
Apply is explicit and opt-in. The script should never modify a zone unless `--apply` is provided and one or more `--domain` values are specified.

The apply flow is:
1) Parse the JSON input file and confirm it contains a list of rules.
2) For each target domain, resolve the zone ID and fetch the existing entrypoint ruleset.
3) Replace the existing rules with the rules from the file. This is a full replacement operation, not a merge.
4) Report which zones were updated and how many rules were written.

This design deliberately avoids a merge feature. Operators should treat the exported rules file as the source of truth and re-apply when changes are made.

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
- There is no merge mode, no phase override option, and no bulk selection via `--domains-file` or `--site-type`.

This scope keeps the tool simple and aligns it with the current operational maturity: export from one known-good zone and apply to a defined list of targets.
