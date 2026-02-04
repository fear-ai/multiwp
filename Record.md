# Recording Status Updates
Date: January 16, 2026

## Overview
The purpose of recording is to keep the domain inventory (`domains.csv`) aligned with the actual provisioning and validation outcomes without requiring manual edits after every run. The default behavior is to record successful outcomes while avoiding downgrades, so a transient failure does not erase previously validated stages. This keeps the inventory stable and trustworthy while still allowing explicit overrides when a downgrade is intentional.

## Dependencies and Sources of Truth
This design depends on the following sources, which define the underlying interfaces and data structures:

- `scripts/Scripts.md` defines the authoritative options and behaviors of `onboard-zone.sh`, `cloud-redirect.sh`, and `test-record.sh`.
- The `domains.csv` header defines the inventory schema, and this document defines the meaning of `status_cf`, `status_origin`, and `status_wp` values.
- `scripts/Shell.md` defines the helper conventions used by `csv_put_fields` in `common.sh`.

This document focuses on the recording policy and workflow and avoids duplicating the full interface details already captured in `scripts/Scripts.md`.

## Read-Only Counterpart
The repository now includes a clear separation between read-only validation and recording. `check-verify.sh` runs the broader validation sweep without writing to `domains.csv`, while `test-record.sh` runs a focused subset of validations and records successful outcomes. This split keeps routine checks safe for daily use while reserving state mutation for deliberate recording runs.

## Domain and Zone Data Sources
Recording depends on consistent interpretation of the inventory fields and the Cloudflare auth file. The goal is to keep “domain name” and “zone id” unambiguous so the recording system does not drift across accounts or zones.

The current sources are:
- `domains.csv` stores the apex domain in `domain` and the Cloudflare zone identifier in `zone_id`. The `zone_name` column is informational and is recorded from the API.
- Auth files store zone pairs as `CF_ZONE=<apex>` and `CF_ZONE_ID=<id>`. `CF_ZONE_MAIN` is informational only and is not used to select a zone.

The canonical mapping used throughout this repository is:
- `domain` (CSV) == apex zone name.
- `zone_id` (CSV/auth) == Cloudflare zone identifier used for API calls.
- `zone_name` (CSV) == informational echo from the API; it does not drive selection.

## Intent Signals per Site Type
The `site_type` column is the primary intent flag, but it is not the only signal. Additional fields determine the intended behavior for each site type and prevent ambiguity during recording.

- `singlesite` intent is reinforced by `wp_root` (when a single-site install lives outside the multisite root) and by the absence of `multisite_domain` or `redirect_url`. When `wp_root` is missing, validation can still run using the default root (`/var/www/html/<domain>`), but the intent is weaker and should be treated as a warning scenario.
- `multisite` intent is reinforced by `multisite_domain`, which identifies the network apex. A multisite domain without `multisite_domain` is considered incomplete for intent purposes and should be flagged for completion.
- `redirect` intent is reinforced by `redirect_url`, which defines the destination for Cloudflare Redirect Rules. A redirect domain with an empty `redirect_url` is treated as incomplete, even if `site_type` is set.

These intent signals are used to decide which checks are applicable and to determine which status values are meaningful for a given domain.

In addition to the active site types above, `site_type=none`, `site_type=ignore`, and `site_type=worker` serve as explicit skip markers. Empty `site_type` values are normalized to `none`, and domains in this state are not validated or recorded by the read-only or recording scripts until an explicit intent is set.

## Status Update Policy
Recording updates are monotonic by default. The scripts record success states only and skip downgrades unless explicitly overridden. This prevents a transient failure from overwriting previously validated results.

The canonical order used for no-downgrade checks is:

- `status_cf`: `none` -> `added` -> `redirect` or `https` -> `worker` or `ignore`
- `status_origin`: `none` -> `apache`
- `status_wp`: `none` -> `install` -> `config` -> `load`

`redirect` and `https` are treated as peer end states for Cloudflare, so switching between them requires `--downgrade` to make the change explicit. `worker` and `ignore` are treated as higher-priority terminal values and are not overwritten without `--downgrade`.

When a redirect or worker configuration is confirmed, the preferred state is to mirror intent in both fields: `site_type=redirect` with `status_cf=redirect`, and `site_type=worker` with `status_cf=worker`. When `site_type=ignore` is set, `status_cf` is treated as historical and may remain at its last confirmed stage or at `added`.

## Record Controls
The following controls are shared across scripts that update `domains.csv`:

- Recording is on by default. Use `--norecord` to suppress any update to the CSV while still running the underlying checks or provisioning steps.
- Downgrades are blocked by default. Use `--downgrade` to allow updates that would otherwise be blocked by the monotonic status policy.
- Use `--date` (or `DATASTORE_DATE`) to override the snapshot timestamp when deterministic backups are needed. The expected format is `YYYYmmdd_HHMMSS`.

These flags are implemented consistently in `onboard-zone.sh`, `cloud-redirect.sh`, and `test-record.sh`.

## Backup and Write Behavior
Before writing any update, the existing `domains.csv` file is moved aside so the previous state is preserved. The backup filename is `datastore_YYYYmmdd_HHMMSS.csv`, created in the same directory as `domains.csv`. A single run only creates one backup; subsequent updates during the same process write to the new `domains.csv` without creating additional backups.

This move-first approach ensures that, if a write fails, the last known good inventory still exists for recovery. It also makes it easy to diff the new file against the last snapshot.

## Driver and Workflow
Recording is now split across provisioning and verification steps so intent and validation remain distinct.

- `onboard-zone.sh` records zone metadata, nameserver labels, and sets `status_cf=added` when a zone exists but is not yet active.
- `cloud-redirect.sh` ensures redirect rules exist and records `status_cf=redirect` and `redirect_url` for redirect-only domains when recording is enabled.
- `test-record.sh` runs validation checks and records success states:
  - Edge checks -> `status_cf=https` for standard domains, `status_cf=redirect` for redirect-only domains.
  - Origin checks -> `status_origin=apache`.
  - WordPress checks -> `status_wp=config`.

Each step uses the same recording helper so status updates are consistent across scripts.

## Row Matching and Update Semantics
Recording relies on a consistent domain match so reads and writes align. The recording helper lowercases the target domain and matches it against the `domain` column after trimming and lowercasing. This keeps lookups case-insensitive while preserving the original `domain` value already stored in the CSV.

When a row is found, the update behavior is selective rather than wholesale. Non-status fields are only updated when a non-empty value is supplied, and status fields follow the monotonic policy unless `--downgrade` is provided. When no matching row exists, a new row is created with the normalized (lowercase) domain value and the supplied updates.

## Zone ID Resolution and Orchestrator Scope
Domain-scoped scripts resolve the zone id with an explicit priority order: auth file match (by zone name), then `domains.csv` (`zone_id`), then API lookup. This ensures a domain always maps to the correct zone even when multiple zones exist in the same auth file, while still allowing the CSV to remain the canonical inventory source for recorded values.

The orchestrators (`check-verify.sh` and `test-record.sh`) intentionally handle zone ids more narrowly. They read `zone_id` directly from `domains.csv` and pass it through for API checks, and they skip API-based checks when the zone id is missing. This behavior is deliberate for three reasons:

1) **Deterministic scope:** Orchestrators often run across many domains and should not “discover” zones outside the declared inventory. Relying on `domains.csv` keeps the scope explicit and avoids cross-account drift.
2) **Operational safety:** API lookups during broad orchestration can mask inventory gaps by silently resolving missing zone ids. That makes the inventory look complete when it is not. Skipping the API instead forces the missing zone id to be recorded explicitly.
3) **Performance and rate limits:** Orchestrators are designed to be fast, read-only sweeps. Avoiding per-domain API lookups reduces API load and keeps routine runs predictable.

When a zone id is missing, the intended path is to fix the inventory first (for example, by running `onboard-zone.sh` or `check-auth.sh --check-ids`) rather than letting the orchestration layer infer it on the fly.

## Account-Scoped Auth and Inventory Alignment
The current model allows multiple zones in a single `.auth` file while `domains.csv` may reference multiple accounts. This blurs the account/zone/domain relationship and makes it easy for scripts to resolve the wrong zone when a stale `CF_ZONE_ID` is set or a domain is missing from the inventory. The proposed design is to make `.auth` files account-scoped and to align `domains.csv` with that account scope.

Design objectives:
- Each Cloudflare account has a dedicated `.auth` file with `CF_ACCOUNT_ID`, `CF_ACCOUNT_NAME`, and a `CF_DOMAINS` list (comma-separated).
- Each `domains.csv` is either account-specific (recommended) or uses the `auth_file` column consistently to point at the correct account file.
- Script defaults should avoid using a stale `CF_ZONE_ID` from an unrelated account when domains are not in scope for that auth file.

Mismatch handling:
- If a domain appears in `CF_DOMAINS` but not in the account’s `domains.csv`, add it to the CSV before running provisioning scripts.
- If a domain appears in the CSV but not in `CF_DOMAINS`, add it to the auth file or move it to the correct account file.
- When a CSV includes multiple `auth_file` values, require explicit `--auth-file` usage so zone resolution does not default to the wrong account.

Split an inventory into per-account CSV files:
```bash
python3 - <<'PY'
import csv
from collections import defaultdict

src = "domains.csv"
groups = defaultdict(list)

with open(src, newline="") as fh:
    reader = csv.DictReader(fh)
    fieldnames = reader.fieldnames or []
    for row in reader:
        key = (row.get("auth_file") or "unknown").strip()
        groups[key].append(row)

for auth_file, rows in groups.items():
    slug = auth_file.replace("/", "_").replace("~", "home") if auth_file else "unknown"
    out = f"domains_{slug}.csv"
    with open(out, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {out} ({len(rows)} rows)")
PY
```

Re-merge account CSV files back into a single inventory:
```bash
python3 - <<'PY'
import csv
import glob

files = sorted(glob.glob("domains_*.csv"))
rows = []
fieldnames = None
seen = set()

for path in files:
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = fieldnames or reader.fieldnames
        for row in reader:
            domain = (row.get("domain") or "").strip().lower()
            if not domain or domain in seen:
                continue
            seen.add(domain)
            rows.append(row)

with open("domains.csv", "w", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
print(f"Wrote domains.csv ({len(rows)} rows)")
PY
```

Onboarding domains with account-scoped auth:
1) Add the domain to `CF_DOMAINS` in the account’s `.auth` file.
2) Ensure `auth_file` in the CSV row matches the account `.auth` file.
3) Run `onboard-zone.sh` with `--auth-file` set to the account file to avoid cross-account defaults.

## Open Questions and TODOs
The items below require follow-up to harden the recording system and clarify intent boundaries:

1) Add a write lock around `domains.csv` updates to prevent concurrent runs from clobbering each other. The helper currently includes a TODO for this.
2) Decide whether `test-record.sh` should support explicit downgrade-on-failure behavior (for example, setting `status_cf=none` when edge checks fail) rather than only updating on success.
3) Clarify the intended handling for domains that intentionally change between `redirect` and `https` without a `site_type` change; the current policy requires `--downgrade` for that transition.
4) Define how to record `status_wp=install` in a repeatable way, since the current automated checks only confirm configuration (`config`).
5) Inventory intent is not inferred from `redirect_url` alone when `site_type` is empty; empty values are normalized to `none` and treated as explicit skips until `site_type` is set.
