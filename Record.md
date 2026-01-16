# Recording Status Updates
Date: January 16, 2026

## Overview
The purpose of recording is to keep the domain inventory (`domains.csv`) aligned with the actual provisioning and validation outcomes without requiring manual edits after every run. The default behavior is to record successful outcomes while avoiding downgrades, so a transient failure does not erase previously validated stages. This keeps the inventory stable and trustworthy while still allowing explicit overrides when a downgrade is intentional.

## Dependencies and Sources of Truth
This design depends on the following sources, which define the underlying interfaces and data structures:

- `scripts/Scripts.md` defines the authoritative options and behaviors of `onboard-zone.sh`, `cloud-redirect.sh`, and `test-record.sh`.
- `Plan.md` and the `domains.csv` header define the inventory schema and the meaning of `status_cf`, `status_origin`, and `status_wp` values.
- `scripts/Shell.md` defines the helper conventions used by `record_update_csv` in `common.sh`.

This document focuses on the recording policy and workflow and avoids duplicating the full interface details already captured in `scripts/Scripts.md`.

## Read-Only Counterpart
The repository now includes a clear separation between read-only validation and recording. `check-read.sh` runs the broader validation sweep without writing to `domains.csv`, while `test-record.sh` runs a focused subset of validations and records successful outcomes. This split keeps routine checks safe for daily use while reserving state mutation for deliberate recording runs.

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

## Open Questions and TODOs
The items below require follow-up to harden the recording system and clarify intent boundaries:

1) Add a write lock around `domains.csv` updates to prevent concurrent runs from clobbering each other. The helper currently includes a TODO for this.
2) Decide whether `test-record.sh` should support explicit downgrade-on-failure behavior (for example, setting `status_cf=none` when edge checks fail) rather than only updating on success.
3) Clarify the intended handling for domains that intentionally change between `redirect` and `https` without a `site_type` change; the current policy requires `--downgrade` for that transition.
4) Define how to record `status_wp=install` in a repeatable way, since the current automated checks only confirm configuration (`config`).
5) Inventory intent is not inferred from `redirect_url` alone when `site_type` is empty; empty values are normalized to `none` and treated as explicit skips until `site_type` is set.
