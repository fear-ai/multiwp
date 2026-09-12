# Script Interfaces and Configuration
Date: January 9, 2026

This document centralizes script interfaces, configuration expectations, environment variables, and defaults for `scripts/`. It is the interface contract for operators and automation. Each script prints authoritative help via `usage()`; when this document conflicts, update it to match script output. `scripts/Shell.md` covers Bash conventions and shared helpers.

## Structure and Audience

Audience: operators running scripts, automation authors relying on stable
interfaces, and maintainers updating shared helpers.

Each script prints authoritative help via `usage()`. Where any document conflicts
with that output, the script wins and the document is corrected.

### Contents

- [Conventions](#conventions) — terminology, data sources, structured output markers.
- [Script Catalog](#script-catalog) — program scripts by layer, then orchestration, helpers, tests.
- [Settings](#settings) — edge expectations that affect how check scripts read results.
- [Options and Environment](#options-and-environment) — pointer to `Options.md`.
- [Cross-References](#cross-references) — pointer to `Generated.md`.
- [Development Prompts](#development-prompts) — prompt-scoping guidance.
- [TODO (Revisit)](#todo-revisit) — deferred interface questions.

### Document set

| Document | Holds | Maintained |
|---|---|---|
| `Scripts.md` (this file) | catalog, roles, settings, conventions | by hand |
| `Options.md` | option and environment definitions | by hand, must match `usage()` |
| `Generated.md` | option and helper cross-references | generated |
| `Shell.md` | Bash conventions and shared helpers | by hand |

## Conventions
### Script categories and roles

Scripts are grouped into four roles so operators and maintainers can reason about entrypoints and shared behavior:

- **Helper/library scripts** (`common.sh`, `cli.sh`, `cmd.sh`, `auth.sh`, `mcp.sh`) are sourced by other scripts and are not intended to be executed directly.
- **Program scripts** are user-facing entrypoints with `usage()` output and option parsing. They perform a single operation such as provisioning, validation, or performance measurement.
- **Orchestration scripts** are program scripts that call other program scripts in a defined order to provide multi-step workflows without duplicating logic.
- **Test scripts** run standalone unit checks for helper behavior and parsing logic.

This document uses these roles to group the catalog and to describe where shared helpers should be applied.

### Terminology alignment (domain, host, zone)

Terminology follows `DNSTerms.md`, and usage follows `Operations.md`. This keeps script output, CSV inventory fields, and Cloudflare API lookups unambiguous.

- **Domain**: The apex/registrable domain (`example.com`). In Cloudflare terms this is the **zone name** and is used for `--domain`, `zone_name`, and `CF_ZONE`.
- **Zone**: The Cloudflare zone object (identified by `zone_id`). When a script needs the zone identifier, it should use `zone_id`/`CF_ZONE_ID`.
- **Host**: A fully-qualified hostname (apex or subdomain), e.g., `www.example.com`. Use `HOST` only when the value is not necessarily the apex.

When outputting key/value pairs, use `DOMAIN` for the apex domain, `ZONE` for the Cloudflare zone name, `ZONE_ID` for the Cloudflare zone identifier, and `HOST` for FQDNs. Only use `DOMAINS` when the value is a list of apex domains.

### Interface and data format locations

Inputs and outputs live in a few focused places so updates stay consistent:

- **Command-line interfaces**: `scripts/Scripts.md` (this document) plus each script’s `usage()` output. `scripts/Options.csv` cross-references options by script.
- **Domain inventory (`domains.csv`)**: The header row in `domains.csv` is the schema, and `Record.md` is the authoritative policy for values and status transitions.
- **Cloudflare auth files (`.auth`)**: `scripts/example.auth` is the reference format; `scripts/Scripts.md` documents expected variables, defaults, and precedence rules.
- **Script output formats**: `scripts/Scripts.md` documents the unified output conventions for new and updated scripts. `scripts/Shell.md` documents the underlying log/error helpers.

### CSV cross-references and option registry (postponed)

This repository uses two CSV cross-references—`Helpers.csv` and `Options.csv`—to describe helper inclusion and option ownership. These files are useful for audits and quick interface scans, but they are also the most prone to drift because the data they summarize is spread across scripts.

The core problem is that helper inclusion is easy to parse, while options are not. Helpers can be detected by scanning `source` statements. Options, however, are parsed through a mix of shared helpers, custom parsing logic, mode-dependent branches, and `usage()` output that is intentionally human-readable rather than machine-structured. As a result, any automated generation of `Options.csv` needs either a strict usage format or a structured option registry. Until that is decided, `Options.csv` remains a manual artifact.

#### Standardizing options to support CSV generation

Two changes support reliable `Options.csv` generation without changing script semantics:

1) **Standardize option presentation.** Split `usage()` into clear **Arguments** (positional) and **Options** sections, keep one option per line, and use a consistent ordering (script-specific, auth, paths, common privilege flags, `--help` last). This improves operator clarity today and makes future parsing straightforward.

2) **Avoid duplicated option parsing.** Shared options (for example `--domain`, `--wp-root`, `--ssl-dir`, `--date`, `--hsts`) should be parsed through `cli.sh` helpers instead of custom per-script parsing. This centralizes validation and keeps usage text aligned with real behavior. The same applies to Cloudflare auth options via `cli_cf_auth_opt`.

These changes are beneficial even if CSV generation remains manual, but they are also prerequisites for reliable automation. Decisions and implementation are postponed until we choose between strict usage parsing and a registry approach.

#### Option registry and shared schema (postponed)

A registry makes option ownership explicit and removes ambiguity in `Options.csv`. A minimal pattern would define an `OPTIONS=()` array in each script and derive both `usage()` output and CSV entries from that array. Shared options can live in `cli.sh` as `CLI_OPTIONS=()` and be merged by scripts that use them.

This approach would:
- Make option ownership unambiguous.
- Allow `Options.csv` to be generated accurately.
- Reduce help-text drift by deriving usage from a single source.

The tradeoff is modest refactoring in each script. The decision and implementation are postponed so we can weigh the maintenance impact against the value of automated CSV generation.

#### Generating the CSVs (postponed)

`Helpers.csv` can be generated reliably today by scanning `source` statements. `Options.csv` can only be generated reliably after we standardize option presentation or adopt an option registry. Until that decision is made, both CSVs remain manually curated, with `Options.csv` being the higher-risk source of drift.

### Auth helper partitioning (postponed)

`auth.sh` currently mixes three concerns: CSV lookups, auth variable initialization, and zone/account resolution via API. For clarity and maintainability, the preferred partitioning keeps `auth.sh` as the Cloudflare-specific hub but separates logic into small, purpose-driven helpers:

- **CSV row resolution**: a single helper that reads and returns the full CSV row for a domain, so `cf_auth_from_csv`, zone ID lookup, and account ID lookup share the same parsing logic.
- **Zone ID resolution**: a helper that returns a `zone_id` plus the source (auth file, CSV, or API) and a consistent status code or warning when the ID is missing.
- **Auth initialization**: a helper that encapsulates `cf_reset_auth_vars`, `cf_auth_from_csv`, and `cf_init_auth`, so scripts do not duplicate the same three-step setup.

This partitioning keeps the API request helpers and credential validation in `auth.sh` while reducing duplication and making resolution paths explicit. Decisions and implementation are postponed until we align on the option registry approach and the extent of refactoring we want to take on.

### Output format (planned for structured scripts)

Unified output format supports human scanning and machine parsing. Each section begins with a strict marker, followed by `KEY=VALUE` lines and optional status lines. This allows easy parsing with `awk`, `rg`, or CSV/JSON post-processing without losing human readability.

Section marker:
```
== SECTION:Topic
```

Rules:
- `SECTION` is uppercase (`AUTH`, `BACKUP`, `CF`, `DNS`, `EDGE`, `SETTINGS`, `RULES`, `ZONE`, `CERT`, `FIREWALL`, `ORIGIN`, `SERVER`, `WP`, `ORCH`, `MCP`, `LOGS`, `PERF`).
- `Topic` is UpperCamelCase without spaces (`Tls`, `DnsProxy`, `RedirectRule`).
- Section markers appear on their own line and are always prefixed with `==`.

Key/value lines:
```
DOMAIN=example.com
ZONE_ID=0123456789abcdef0123456789abcdef
```

Status lines (planned):
```
PASS key=value
INFO key=value
ERROR key=value
```

`ERROR` is reserved for failures; the distinction between fatal and non-fatal errors is handled by `err()` (exit) versus `fail()` (continue), as described in `scripts/Shell.md`.

Tables below list the **complete** set of `SECTION` values and expected `Topic` values for the current script arsenal. Helper/library scripts (`common.sh`, `cli.sh`, `auth.sh`, `mcp.sh`) do not emit section markers.

#### SECTION values, scripts, and Topics

| SECTION | Scripts | Topics (expected values) |
| --- | --- | --- |
| `AUTH` | `verify-cf-auth.sh`, `check-auth.sh` | `AuthFile`, `Env`, `Token`, `Key`, `OriginCa`, `Domains`, `ZoneIds`, `Mismatches` |
| `BACKUP` | `back-wp.sh` | `Freeze`, `Archive` |
| `CF` | `check-cf.sh` | `Zone`, `Dns`, `Settings`, `Api` |
| `DNS` | `cloud-dns.sh` | `Zone`, `Records`, `Proxy`, `Create` |
| `EDGE` | `check-edge.sh`, `cloud-redirect.sh` | `Dns`, `Https`, `RedirectRule`, `Headers` |
| `SETTINGS` | `cloud-settings.sh` | `ZoneSettings`, `Baseline` |
| `RULES` | `rules-cf.sh` | `Get`, `Put`, `Copy` |
| `ZONE` | `onboard-zone.sh`, `onboard-site.sh` | `Create`, `Dns`, `Record`, `Delegation`, `NextSteps` |
| `CERT` | `get-cert.sh` | `OriginCa`, `Install`, `Verify` |
| `FIREWALL` | `cloudflare-ips.sh` | `IpList`, `UfwRules` |
| `ORIGIN` | `apache-vhost.sh`, `check-origin.sh` | `Vhosts`, `Tls`, `Enable` |
| `SERVER` | `check-server.sh` | `Os`, `Updates`, `Ssh`, `Network`, `Ufw`, `Apache`, `Mysql`, `Redis`, `Cron` |
| `WP` | `setup-wp.sh`, `install-site.sh`, `check-wp.sh` | `Install`, `Site`, `Mapping`, `Root`, `Config`, `Routing`, `Security`, `Templates` |
| `ORCH` | `check-verify.sh`, `record-status.sh`, `check-domain.sh` | `Selection`, `Run`, `Record`, `Results` |
| `MCP` | `mcp.sh`, `mcp-cf.sh` | `Server`, `Request`, `Response` |
| `PERF` | `perf-load.sh` | `Summary`, `Telemetry`, `Process` |
| `LOGS` | `slice-logs.sh` | `Analyze`, `Csv` |

The `test_*.sh` scripts emit no section markers; they use `PASS:` / `FAIL:` lines
and a final summary. An earlier revision of this table listed a `TEST` section
with `Setup`/`Cases`/`Results` topics, and `INIT`/`LOAD`/`NONE` for
`perf-load.sh`; none of those were ever emitted.

#### Script-to-section mapping

Use this mapping when implementing or refactoring output so every script emits the expected section markers.

| Script | SECTION | Topics |
| --- | --- | --- |
| `verify-cf-auth.sh` | `AUTH` | `AuthFile`, `Env`, `Token`, `Key`, `OriginCa` |
| `check-auth.sh` | `AUTH` | `Domains`, `ZoneIds`, `Mismatches` |
| `back-wp.sh` | `BACKUP` | `Freeze`, `Archive` |
| `check-cf.sh` | `CF` | `Zone`, `Dns`, `Settings`, `Api` |
| `cloud-dns.sh` | `DNS` | `Zone`, `Records`, `Proxy`, `Create` |
| `check-edge.sh` | `EDGE` | `Dns`, `Https`, `RedirectRule`, `Headers` |
| `cloud-redirect.sh` | `EDGE` | `RedirectRule` |
| `cloud-settings.sh` | `SETTINGS` | `ZoneSettings`, `Baseline` |
| `rules-cf.sh` | `RULES` | `Get`, `Put`, `Copy` |
| `onboard-zone.sh` | `ZONE` | `Create`, `Dns`, `Record`, `Delegation` |
| `onboard-site.sh` | `ZONE` | `Create`, `NextSteps` (its children emit `Dns`, `Record`, `Delegation`, `EDGE:RedirectRule`) |
| `get-cert.sh` | `CERT` | `OriginCa`, `Install`, `Verify` |
| `cloudflare-ips.sh` | `FIREWALL` | `IpList`, `UfwRules` |
| `apache-vhost.sh` | `ORIGIN` | `Vhosts`, `Enable`, `Tls` |
| `check-origin.sh` | `ORIGIN` | `Vhosts`, `Tls` |
| `check-server.sh` | `SERVER` | `Os`, `Updates`, `Ssh`, `Network`, `Ufw`, `Apache`, `Mysql`, `Redis`, `Cron` |
| `setup-wp.sh` | `WP` | `Install`, `Config`, `Templates` |
| `install-site.sh` | `WP` | `Site`, `Mapping` |
| `check-wp.sh` | `WP` | `Root`, `Config`, `Routing`, `Security`, `Templates` |
| `check-verify.sh` | `ORCH` | `Selection`, `Run`, `Results` |
| `record-status.sh` | `ORCH` | `Selection`, `Record`, `Results` |
| `check-domain.sh` | `ORCH` | `Selection`, `Run`, `Results` |
| `mcp.sh` | `MCP` | `Server`, `Request`, `Response` |
| `mcp-cf.sh` | `MCP` | `Server`, `Request`, `Response` |
| `perf-load.sh` | `PERF` | `Summary`, `Telemetry`, `Process` |
| `slice-logs.sh` | `LOGS` | `Analyze`, `Csv` |
| `test_common.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_cli.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_cmd.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_cf.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_mcp.sh` | `TEST` | `Setup`, `Cases`, `Results` |

## Script Catalog

This catalog groups scripts by operational layer and marks each script as provisioning or verification/investigation. Full option and environment-variable details live in `Options.md`.

### Cloudflare Layer

Cloudflare scripts handle credentials, DNS records, certificates, and edge validation. A typical flow starts with credential checks, provisions DNS inside an existing zone, then issues certificates, and ends with settings and edge validation. Zone creation is out of scope for these scripts and must be completed before DNS provisioning begins.

Verification (read-only), alphabetical:
- `check-auth.sh`
- `check-cf.sh`
- `check-edge.sh`
- `verify-cf-auth.sh`

Provisioning, alphabetical:
- `cloud-dns.sh`
- `cloud-redirect.sh`
- `cloud-settings.sh`
- `cloudflare-ips.sh` (firewall allowlist helper)
- `get-cert.sh`
- `onboard-zone.sh`
- `rules-cf.sh`

### Host Layer (Ubuntu and Base Services)

Host-level scripts report Ubuntu, Apache, PHP, and MySQL baselines. These checks are read-only and validate the hardening guidance in `HardenUbuntu.md` before or after origin configuration changes.

- `check-server.sh` — verification (read-only)

### Origin Layer (Apache and TLS)

Origin scripts configure or validate Apache vhosts and TLS wiring. Provisioning precedes verification.

- `apache-vhost.sh` — provisioning
- `check-origin.sh` — verification (read-only)

### WordPress Layer

WordPress scripts bootstrap or validate multisite configuration and mapping. Provisioning precedes verification.

- `setup-wp.sh` — provisioning
- `install-site.sh` — provisioning
- `check-wp.sh` — verification (read-only)

### Orchestration Layer

Orchestration scripts are program scripts that combine multiple checks in a single run.

- `record-status.sh` — verification + recording
- `check-verify.sh` — verification (read-only)
- `check-domain.sh` — verification (read-only)

### Performance and Benchmarking

Performance scripts support load generation, backups, and log slicing for repeatable benchmarking. Some steps temporarily change WordPress state (for example maintenance mode during backups), so run them with the same care as other operational scripts.

- `back-wp.sh` — maintenance (temporary WordPress changes, writes backups)
- `perf-load.sh` — verification (read-only)
- `slice-logs.sh` — verification (read-only)

### check-verify

`check-verify.sh` is a lightweight entry point for read-only validation across multiple domains. It standardizes syntax checks, unit tests, edge/DNS checks, server checks, and origin/WordPress checks without requiring operators to remember the underlying script order or domain selection details.

Needs and requirements follow so future changes can be evaluated against the same constraints.

Needs:
- A single entry point that can run `syn`, `unit`, `auth`, `edge`, `dns`, `server`, `origin`, and `wp` in a predictable order.
- Domain selection driven by `domains.csv` or an explicit list of domains provided on the command line.
- Support for filtering by `status_cf` and `site_type` while avoiding `status_cf=ignore` and `status_cf=worker` plus `site_type=none`, `site_type=ignore`, and `site_type=worker` by default.

Requirements:
- Read-only behavior only; no API writes and no origin or WordPress mutations.
- Clear exit codes: syntax/unit failures should cause a non-zero exit, while edge/DNS checks should continue across domains.
- Consistent selection rules across all commands so a single invocation is trustworthy as a full read-only run.

Design notes:
- `check-verify.sh` reads `domains.csv` once and applies filters only when explicit domains are not supplied.
- If no command list is provided, `check-verify.sh` runs all commands in the order listed (excluding `auth`), so a default run is a full read-only pass.
- `edge` uses `check-edge.sh` (with `--api` when requested) and `dns` uses `check-cf.sh`.
- `server` uses `check-server.sh`, `origin` uses `check-origin.sh`, and `wp` uses `check-wp.sh`.
- `auth` uses `check-auth.sh` and is opt-in; it is not part of the default `all` list.
- `--auth-file` overrides the per-domain auth file from `domains.csv` for edge/DNS API calls.
- Server, Origin, and WordPress checks are read-only and depend on local filesystem access.
- Empty `site_type` values are normalized to `none`, and `site_type=none`, `site_type=ignore`, and `site_type=worker` are always skipped.
- When running `check-verify.sh` through an external command runner, use a timeout of at least 60 seconds for full domain lists to avoid premature termination.

Implementation plan:
1) Parse commands and options; when no commands are supplied, run the full command set in order.
2) Load domain metadata when needed and select the domain set (explicit list or filtered list).
3) Execute each command in the requested order, collecting failures without aborting domain loops.
4) Return a non-zero status if any syntax or unit test fails.

### Support and Tests

Test scripts and helper libraries are intentionally minimal. They do not parse options and run directly from the `scripts/` directory.

- `test_common.sh`, `test_cli.sh`, `test_cmd.sh`, `test_cf.sh` run unit checks for shared helpers.
- `common.sh`, `cli.sh`, `cmd.sh`, `auth.sh`, `mcp.sh` provide shared logic and should not be executed directly.

## Settings

This section lists the Cloudflare and edge behaviors validated by read-only checks. Use it to interpret script output while keeping `usage()` authoritative.

Prereqs: the zone is active in Cloudflare, nameservers point to Cloudflare, and scripts can read a valid auth file with the required credentials and `CF_ZONE_ID` or `CF_ZONE`.

### DNS and Proxy

Edge checks assume Cloudflare proxies the apex and `www` hostnames. DNS must exist and be proxied before HTTPS or header checks behave as expected.

- Apex: an **A** record for `@` pointing to the origin IPv4 address, with the proxy (orange cloud) enabled.
- `www`: a **CNAME** to the apex. If CNAME flattening hides the CNAME, an **A** record for `www` is acceptable and will be treated as valid by `check-edge.sh`.
- Optional: a wildcard `*` CNAME to the apex when you want Cloudflare to catch stray hostnames.

### Redirect Behavior

`check-edge.sh` validates canonical redirects and will fail if the redirect targets do not match the expected behavior. Redirect-only domains use `redirect_url` from `domains.csv` and skip HTTPS and API checks.

- Standard sites: `http://apex` should 301 to `https://apex`, and `https://www` should 301 to `https://apex`.
- Redirect-only sites: use a Cloudflare Redirect Rule that applies to all incoming requests and points to the configured `redirect_url`.

### SSL/TLS Mode

`check-edge.sh --api` requires SSL mode **Full (strict)**. This is a Cloudflare zone setting and is validated via the API.

- Path: `SSL/TLS` → `Overview` → set “SSL/TLS encryption mode” to **Full (strict)**.

Redirect-only zones skip HTTPS and API checks, so they can remain on Cloudflare’s default **Flexible** mode when a Redirect Rule is the only intended behavior. If you want redirect zones to fail closed when a rule is removed or misconfigured, use **Full (strict)** with a valid origin certificate so the fallback path stays protected.

### Edge HTTPS Features

The redirect expectations rely on Always Use HTTPS being enabled for standard WordPress sites.

- Path: `SSL/TLS` → `Edge Certificates` → enable “Always Use HTTPS”.
- HSTS is optional by default. If `--hsts=true` is supplied to `check-edge.sh`, the script fails when `strict-transport-security` is missing; when HSTS is not required it reports the header as info (present or absent) and includes its value if present.

### Response Headers

`check-edge.sh` requires several security headers on the HTTPS apex response. Provide them at the origin or via Cloudflare managed headers.

- Required headers: `x-content-type-options`, `x-frame-options`, `referrer-policy`.
- Optional headers (warn only): `x-xss-protection`, `expect-ct`.
- Path (Cloudflare managed headers): `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers”.

### WordPress Markers

For non-redirect domains, `check-edge.sh` fetches HTML and expects WordPress markers (`/wp-content` or `/wp-includes`). Cloudflare Pages or Workers sites will not satisfy this check; set `site_type=worker` (and `status_cf=worker` once validated) so they are skipped unless explicitly included.

### API-Visible Settings (check-cf)

`check-cf.sh` prints the full Cloudflare settings map and DNS records. It only enforces values when `-e key=value` is supplied. The settings most commonly enforced alongside edge checks include:

- `--ssl=strict`
- `always_use_https=on`
- `min_tls_version=1.2`
- `managed_add_security_headers=true`
- `leaked_credential_checks=false`

When you need to apply the baseline across many zones, use `cloud-settings.sh`. It reads `domains.csv` to select domains, queries current values before writing, and applies settings through the Cloudflare API. This keeps the baseline consistent without modifying DNS records or redirect rules, but it still requires edit-capable credentials and an active zone for each domain.

## Options and Environment

Option and environment-variable definitions live in `scripts/Options.md`. Each
entry there must match the script's own `usage()` output exactly.

## Cross-References

Option and helper-inclusion cross-references are generated from the scripts and
live in `scripts/Generated.md`. Regenerate with `./scripts/gen-crossref.sh`.

They were previously maintained by hand here and had drifted: `slice-logs.sh` and
`onboard-site.sh` were missing from the helper table, and `--none` and `--slice`
from the option table.

## Development Prompts

This section captures practical lessons from recent refactors and clarifies how prompt specificity improves both design quality and implementation speed. The intent is not to add overhead, but to ensure that small requests do not unintentionally become behavioral changes or structural redesigns.

### Guidance for prompt specificity

When a prompt touches shared helpers or cross-cutting behavior, include a short, explicit policy statement and a clear boundary for what should not change. This avoids implicit decisions about error handling, output formats, or dependency structure.

Useful patterns:
- State the intended behavior directly, using positive language. For example: “Fail fast when `common.sh` is missing” or “Keep output format unchanged.”
- Add a negative constraint to prevent scope creep. For example: “Do not add new helper files” or “Do not change auth precedence.”
- If the request is analysis-only, say so explicitly: “Provide analysis only; do not implement.”

### Examples that keep scope tight

These examples are derived from recent work and show how to avoid ambiguous requirements:

- “Add include guards to helper scripts that fail fast using the single-line `:?` form; do not add new helper files; update `scripts/Shell.md` to reflect the behavior.”
- “Analyze whether `Options.csv` can be generated from existing scripts; do not change code; propose approaches and tradeoffs only.”
- “Refactor duplicated `--domain` parsing to use `cli_domain_opt` everywhere; keep usage text and behavior unchanged.”

### Avoiding silent behavioral changes

Some refactors appear structural but still require policy decisions. Include those decisions up front so the implementation does not invent behavior:

- Dependency guards imply a policy: warn-only vs. fail-fast. Explicitly state which is expected.
- Changes to option handling can affect precedence or default values; call out “no behavior change” if that is the requirement.
- CSV generation or parsing can imply a canonical source of truth. If the decision is deferred, say “analysis only” and postpone implementation.

### Clarifying analysis versus implementation

Use a simple scope statement to distinguish a design analysis from a re-architecture:

- Analysis-only: define the problem, list options, and explain tradeoffs. No code changes.
- Implementation: pick a design, specify constraints, and name the files that should change.

This distinction matters most for changes like option registries or CSV automation, which require structural decisions and documentation updates.

### Prompt specificity checklist

A short checklist keeps prompts direct without adding ceremony:

- Intended behavior: what should happen on success and on failure.
- Constraints: what must not change.
- Scope: analysis-only or implement.
- Outputs: which documents or files should be updated.

This keeps refactors bounded, improves reviewability, and makes it easier to reason about cross-cutting changes.

## TODO (Revisit)

The items below capture small, implementation-focused follow-ups that keep helper behavior and option parsing consistent as the script surface grows.

- Helper predicates: `cf_has_env` and `cf_has_all` (in `auth.sh`) form the shared pattern for credential checks. `cf_has_env` treats unset and empty as absent, while `cf_has_all` requires every variable in the list to be present and non-empty. Intended usage: gate Cloudflare API calls and auth selection on presence checks (token/key/CA key), and validate required IDs (account/zone) before API requests. These helpers do not validate formats or resolve values; they only confirm presence. All `cf_has_*` helpers should delegate to these two functions so empty-vs-unset semantics stay consistent, and new helpers should follow the same pattern rather than re-implementing checks.
- Enum parsing: evaluate whether option values with limited sets (for example `--site-type`, `singlesite|multisite|autosite`, or `api|manual|auto`) should accept environment equivalents with explicit enum validation, and if so, keep CLI/env/auth error messaging aligned.
- Origin cert auth policy: `CF_CA_KEY` is required for Origin CA issuance and does not overlap with the global API key. The policy is to keep CA key usage scoped to Origin CA endpoints, and not to treat the global key as a substitute for CA key. Token vs key selection for non-Origin-CA API calls is documented elsewhere; do not conflate that with CA key usage.
- Review `record-status.sh` uses and `check-domain.sh` overlap to decide whether to consolidate or keep distinct (postponed).
- UFW allowlist verification: decide whether `check-server.sh` should validate by marker comment, by CIDR content, or by both, once the UFW workflow and template placement are finalized (postponed).

## Maintenance Log — 2026-09-12

Defects found by review and fixed. Each was reproduced before the change and re-verified after.

| Area | Defect | Fix |
| --- | --- | --- |
| `check-wp.sh:180` | `\\(` in an awk regex made awk **abort** (`Unmatched ( or \(`), so `--template-check` had never worked | single backslash; verified the capture now returns `DB_NAME` |
| `check-edge.sh`, `check-verify.sh` | `usage()` used a quoted heredoc (`<<'EOF'`) while the body contains `$(cli_usage_*)`, so `--help` printed literal `$(cli_usage_http_timeout)` | unquoted the heredoc; checked both bodies for unintended expansion |
| `check-verify.sh` | `--domains-file` was set but never exported, so child `check-*.sh` fell back to the default inventory | `export DOMAINS_FILE` on both parse arms |
| `gen-crossref.sh:50` | any inner `esac` cleared parser state, dropping every option declared after a nested `case`; `Generated.md` omitted `--dry-run` for `cloud-redirect.sh` | added a nesting depth counter; regenerated output differs by exactly the corrected row |
| `verify-cf-auth.sh` | `ca_checked=true` was set before verification was attempted, so a **skipped** Origin CA check (no zone id) exited 1 as a failure | set `ca_checked` only when the check actually runs; emits `INFO ca=skipped reason=no-zone-id` |
| 7 scripts | each hardcoded `DOMAINS_FILE` to `$ROOT_DIR/domains.csv`, bypassing `domains_csv_path()` and reading a 0-byte file while real split inventories existed | all now default via `$(domains_csv_path)` |
| `orch.sh` | 31-line library, one consumer, six caller-set globals, no tests | inlined into `check-domain.sh` as `run_domain_checks`; file removed |
| `test-record.sh` | not a test — writes inventory CSVs, but a `test*.sh` CI glob would execute it | renamed `record-status.sh`; 10 files updated |
| `onboard-site.sh` | hardcoded estate values (forbidden by Shell.md); `--dry-run` always failed; dead `SITE_TYPE_SET` conditionals; `ZONE:NextSteps` documented but never emitted | values moved to `site.conf` (`REDIRECT_TARGET_URL`, `DEFAULT_AUTH_FILE`); `--dry-run` routed only to the child that implements it; stage failures now reported; `NextSteps` emitted |
| `check-origin.sh` | printed certificate `-dates` but never asserted them, so an expired cert passed | `-checkend 0` fails on expiry; `-checkend $CERT_EXPIRY_WARN_SECONDS` (default 30d) warns |

Reuse improvement, same date: `cf_setup_zone <domain> [context]` (`auth.sh`) replaces the `cf_init_auth` → `cf_require_auth` → `cf_require_zone_id` sequence that `cloud-redirect.sh` and `cloud-settings.sh` each open-coded. The two copies had drifted — `cloud-settings.sh` cleared `CF_ZONE`/`CF_ZONE_ID` before loading auth and `cloud-redirect.sh` did not — so the helper adopts the safer ordering: clear stale globals, load auth, then set `CF_ZONE` for apex fallback. This matters in multi-domain loops, where a value left from the previous iteration would otherwise be reused for a domain with no inventory entry. Verified across three domains that each still resolves its own zone. Callers needing only credentials continue to call `cf_init_auth` + `cf_require_auth` directly.

Standardization pass, 2026-09-12:

| Change | Rationale |
| --- | --- |
| `cli_reorder_args` (`cli.sh`), adopted by `cloud-redirect.sh`, `cloud-settings.sh`, `onboard-zone.sh`, `check-domain.sh` | **Fixes a real bug.** `getopts` stops at the first non-option word, so `script domain.tld --flag` left `OPTIND=1`: flags after a positional were never parsed and were collected as domains, failing with `Error: domain must include a dot` for `--domains-file`. Verified before and after; flag-first ordering unchanged, typos still rejected. |
| `dns_lookup` (`common.sh`), adopted by all 5 `dig` sites in `check-edge.sh` | `check-edge.sh` used the host stub resolver, so a negative answer cached before a record existed kept record checks failing for the full 1800s SOA negative TTL while HTTP checks on the same host passed. Now pinned to `DELEGATION_RESOLVER`, matching the delegation check. The three `apps*` zones that flapped now pass consistently. |
| `--zone` added to `verify-cf-auth.sh`; `cli_cf_zone_opt` + `cli_usage_cf_zone` added to `cli.sh` and adopted by `check-cf.sh`, `check-edge.sh` | The script documented that it resolves `CF_ZONE_ID` from `CF_ZONE` but had no flag to set it, so the Origin CA check ran only when the raw zone ID was known. Verified: `--zone alternat.info` now resolves and validates. `check-cf.sh` and `check-edge.sh` each hand-rolled the same four arms; they now share one helper. **Deliberately not added** to `cloud-redirect.sh`, `cloud-settings.sh`, `onboard-zone.sh`, `cloud-dns.sh`: those iterate a domain list and resolve a zone per domain, so a single `CF_ZONE` would override every iteration. |
| `report_tee` / `report_log` / `report_section` / `report_kv` moved into `common.sh` | `perf-load.sh` and `slice-logs.sh` each implemented the same "print via the shared helper, then append to a transcript file" pattern under different variable names. The shared versions use one `REPORT_FILE`; `slice-logs.sh` maps its `--report`/`--no-report` semantics onto it. Verified the transcript is still written. |
| `slice-logs.sh` log-registry arrays declared | `analyze_admin_log` indexed `LOG_DEST[apache_admin_access]` while `LOG_DEST` was never declared, so under `set -u` the script **aborted** partway instead of taking its documented "log missing, skip" path. An undeclared array errors even with the `${arr[key]-}` default form, so `LOG_DEST`, `LOG_TYPE`, `LOG_OPTIONAL` and `LOG_IDS` are now declared empty. Pre-existing (present at 614231d). |
| `gen-crossref.sh` alternation arms | The arm regex required a single name before `)`, so `zone\|zone=*\|zone-id\|zone-id=*)` was invisible and the option was credited to `cli.sh` instead of the scripts an operator runs. Now splits on `\|`. This also corrected long-standing under-reporting: `--wp-root` listed only `cli.sh` and now lists all 8 real consumers, matching what `Options.csv` always said. |
| `note()` removed from `check-cf.sh` | Bypassed `common.sh`. The three informational messages became `log()`; the genuine zone-name mismatch stayed `warn()`. |
| `log_msg()` in `slice-logs.sh` now wraps `log()` | It was not redundant — it tees to a report file — but it bypassed the shared timestamp/stdout contract. It now builds on `log()` and keeps the tee. `LOGS:Analyze` / `LOGS:Csv` sections and a `status_pass` were added; the script previously emitted no structured markers at all across 731 lines. |

Note on `perf-load.sh`: its `report_section`/`report_kv` were left as-is. They already call `section`/`kv` and add a report-file tee, so they extend the shared contract rather than bypass it.

A claim from the earlier review that did **not** hold: unknown options are not silently treated as domains. `cli_domain_opt` returns 1 for anything but `domain`/`domain=*`, so the `*)` arm falls through to `usage; exit 1`. Verified: `--bogus-flag` prints usage and exits.

### Postponed task: standardize on Python for JSON and CSV

**Status: accepted, not scheduled.** Recorded here so it is not rediscovered as a new finding.

Today three parsers coexist. `auth.sh` alone uses `jq` 11 times and `python3` 3 times; seven scripts declare `require_cmds ... jq python3` and so depend on both interpreters. Several CSV readers additionally carry an `awk` fallback for hosts without `python3`.

Reasons to do it:
- `python3` is already a hard dependency (`require_cmds python3`); `jq` is an extra install. Standardizing on Python removes a dependency rather than adding one.
- The `awk` CSV fallbacks are the weak link. They are rarely exercised and silently wrong when they are: the `IFS=$'\t' read` field-shift bug (fixed 2026-09-11, see `csv_split_row`) and the `\\(` regex abort in `check-wp.sh` both lived in that class of code.
- One language for structured data makes the option/inventory helpers reviewable as a unit.

Scope when scheduled: roughly 30 `jq` call sites plus the `awk` fallbacks in `load_domain_meta` (`check-verify.sh`, `record-status.sh`) and `load_dns_redirects` (`common.sh`). Mechanical but wide, so it wants its own pass with tests rather than being folded into unrelated work. Do not drop `jq` from `require_cmds` until the last call site is converted.

Known remaining, not addressed: the three orchestrators (`check-domain.sh`, `check-verify.sh`, `record-status.sh`) still fan out over the same children in different orders; DNS records are read both via API (`check-cf.sh`) and `dig` (`check-edge.sh`) without reconciliation; several scripts use private logging helpers instead of `common.sh`.
