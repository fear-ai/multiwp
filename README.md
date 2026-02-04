# WordPress Multisite Tools
Date: January 20, 2026

## Introduction
This project implements a WordPress multisite network in subdirectory mode with apex domain mapping. Each client site uses its own domain while sharing WordPress core, themes, and plugins for operational efficiency. Cloudflare provides DNS, CDN, and edge security. The repository includes the runbooks, scripts, and templates needed to host many domains via Cloudflare and Apache with per-domain origin certificates. Use the Documentation Map below to choose the right document for your role and avoid duplicating guidance.

## Expected Audience
This documentation is written for experienced system managers, administrators, and operators, as well as network and system developers. Each role can enter at the right layer without losing the dependency chain.

Recommended entry points by role:
- System administrators responsible for the network, Cloudflare, Ubuntu, and Apache should start with `Operations.md` section 1 (`Operations.md#1-introduction`) and then proceed to sections 3–6 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`). Operations introduces the host baseline and then points you to `HardenUbuntu.md` for the full Ubuntu/Apache/PHP/MySQL hardening sequence; after completing that baseline, return to Operations at section 4.3 (`Operations.md#43-origin-certs`) and continue through origin TLS, vhosts, and multisite.
- WordPress administrators focused on site mapping and content integrity can jump to `Operations.md` section 5 (`Operations.md#5-multisite-ops`).
- Developers adapting or extending the scripts should begin with `scripts/Shell.md` and `scripts/Scripts.md`, then consult `MULTI.md` sections 2–3 (`MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`) for architectural context.

This sequence keeps operational dependencies clear: Cloudflare edge behavior must align before origin TLS and vhost wiring can be trusted, and WordPress routing depends on both layers being correct.

## Key Concepts
The architectural model, dependencies, and tradeoffs are defined in `MULTI.md` sections 2–5 (`MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`, `MULTI.md#4-infrastructure-layers`, `MULTI.md#5-operational-tradeoffs`). The operational steps, commands, and validation checks are defined in `Operations.md` sections 3–6 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`). This README only summarizes how to navigate the documentation and scripts.

## Validated Environment
- **Server**: Ubuntu 24.04
- **Web**: Apache 2.4.58
- **PHP**: 8.3.11
- **Database**: MySQL 8.0.43
- **WordPress**: 6.9 Multisite

---

## Quick Start: Administrator

Scripts use commands: `curl`, `dig`, `jq`, `wp`, `apache2ctl`, `openssl`. Make sure these are installed and the system administrator can run them. For the canonical onboarding and troubleshooting steps, start with `Operations.md` section 1 (`Operations.md#1-introduction`) and proceed through sections 3–6 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`). Operations will call out when to pause and complete the host baseline in `HardenUbuntu.md` before continuing with origin TLS and multisite configuration.

### Add Site to the Network

**Access** sudo on the origin Ubuntu host; Cloudflare account for the domains.
**Goal:** Domain registered, nameservers pointed to Cloudflare, zone created in Cloudflare, and SSL/TLS configured.

#### Configure Zone on Cloudflare (via UI)
Use `Operations.md` section 3.4 (`Operations.md#34-https-flow`) for the exact steps and settings.

#### Issue and install Cloudflare origin certificate
Follow `Operations.md` section 4.3 (`Operations.md#43-origin-certs`) for the UI or API path and the exact command.

#### Create Apache vhosts
`./scripts/apache-vhost.sh domain.com`

#### Add to WordPress multisite
`./scripts/install-site.sh domain.com "Site Title" email@domain.com`
Assumes WordPress multisite is already installed; see `Operations.md` section 5.1 (`Operations.md#51-site-onboarding`) for the setup sequence.

#### Verify
`./scripts/check-domain.sh domain.com`

### Query Multisite Setup
Use `Operations.md` sections 5.2 and 6.1 (`Operations.md#52-site-troubleshooting`, `Operations.md#61-validation-checks`) for the authoritative validation checks and troubleshooting sequence.

---

## Quick Start: Developer

### Documentation Map
The documents below describe different layers of the system and are intended to be read in this order so the operational dependencies remain clear.

- `README.md`: Entry point and quick start with the script index.
- `Operations.md`: Consolidated runbook for Cloudflare, origin, and WordPress operations in dependency order (see sections 3–6: `Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`).
- `HardenUbuntu.md`: Host hardening guidance focused on Ubuntu security baselines and verification.
- `Perf.md`: Performance strategy, tooling, and the execution runbook for benchmarking and tuning.
- `scripts/Shell.md`: Conventions for writing scripts in this repository and using shared helpers.
- `scripts/Scripts.md`: Authoritative script interfaces, options, and environment variables.
- `Record.md`: Recording policy for updating `domains.csv` across provisioning and validation steps.
- `CloudflareMCP.md` (optional, experimental): MCP portal access and validation notes; not part of the production flow.
- `MULTI.md` (optional): Strategic architecture decisions, tradeoffs, and future work (see sections 2–8: `MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`, `MULTI.md#4-infrastructure-layers`, `MULTI.md#5-operational-tradeoffs`, `MULTI.md#6-implementation-issues--lessons`, `MULTI.md#7-abandoned-approaches`, `MULTI.md#8-future-investigation`).
- `DNSTerms.md` (optional): DNS and Cloudflare terminology reference and vendor links.

### Documentation Ownership and Scope
The map above is the entrypoint order; the list below states ownership so topics do not drift or duplicate. This is intended to keep operational guidance coherent and reduce “which doc is the source of truth” ambiguity.

- `Operations.md`: end-to-end operational runbook, including Cloudflare edge settings, redirects, origin TLS, vhost wiring, paths, and WordPress onboarding and verification.
- `HardenUbuntu.md`: Ubuntu baseline and service installation/configuration, including Apache, PHP, MySQL, SSH, UFW, sysctl, netplan, and unattended upgrades.
- `MULTI.md`: architecture, design decisions, and domain model rationale.
- `Perf.md`: performance methodology, tooling, and test execution.
- `Rules.md`: Cloudflare ruleset workflows and file formats.
- `scripts/Scripts.md`: script interfaces, options, and environment variables. Any option registry work belongs here as an implementation detail.
- `Record.md`: `domains.csv` recording policy and update rules.
- `DNSTerms.md`: industry terminology and external references.

WordPress security settings are currently documented in `Operations.md` section 4.7 (`Operations.md#47-wp-configphp-settings`) and mirrored in the `templates/wp-config-*.php` comments. The recommended placement is to keep procedural and file-level guidance in Operations (and templates), while keeping architectural rationale in `MULTI.md` where needed. `HardenUbuntu.md` should not duplicate WordPress-level settings.

### Repository Structure

```
multiwp/
├── AGENTS.md                      # AI assistant guardrails and repo-specific instructions
├── README.md                      # This file
├── MULTI.md                       # Architecture & strategic decisions
├── Operations.md                  # Consolidated operational runbook
├── HardenUbuntu.md                # Host hardening guidance focused on Ubuntu baseline controls
├── Record.md                      # Recording policy for domains.csv updates
├── DNSTerms.md                    # DNS & Cloudflare terminology
├── CloudflareMCP.md               # Cloudflare MCP notes and validation steps
├── scripts/
│   [list below]
├── templates/
│   ├── apache-http.conf           # Apache HTTP vhost template
│   ├── apache-ssl.conf            # Apache HTTPS vhost template
│   ├── htaccess-multisite         # WordPress multisite rewrite rules
│   ├── htaccess-singlesite        # WordPress single-site rewrite rules
│   ├── wp-config-multisite.php    # Multisite wp-config template
│   ├── wp-config-multisite-deployed.php # Multisite wp-config (production-style)
│   ├── wp-config-singlesite.php   # Single-site wp-config template
│   ├── wp-config-singlesite-deployed.php # Single-site wp-config (production-style)
│   └── ...
```

### Scripts

Scripts are grouped by role so entrypoints, orchestration runners, and shared libraries stay clear. Status is a best-effort indicator of whether a script has been exercised in this repo; update it as scripts are run.

Program scripts (entrypoints, alphabetical):
| Script | Purpose | Status |
|--------|---------|--------|
| `apache-vhost.sh` | Create Apache HTTP + SSL vhosts for domain | Exercised |
| `back-wp.sh` | Freeze and back up a WordPress site | Not exercised |
| `check-auth.sh` | Compare CF_DOMAINS in auth files to domains.csv | Not exercised |
| `check-cf.sh` | Inspect Cloudflare zone settings via API | Exercised |
| `check-edge.sh` | Validate Cloudflare edge behavior and headers | Exercised |
| `check-origin.sh` | Validate origin certs, vhosts, and Apache health | Exercised |
| `check-server.sh` | Validate Ubuntu/Apache/PHP/MySQL baseline settings | Not exercised |
| `check-wp.sh` | Validate multisite mappings and site URLs | Exercised |
| `cloud-dns.sh` | Create/update DNS records in an existing Cloudflare zone | Exercised |
| `cloud-redirect.sh` | Ensure Cloudflare Redirect Rules for redirect-only domains | Exercised |
| `cloud-settings.sh` | Apply Cloudflare HTTPS/security settings | Not exercised |
| `cloudflare-ips.sh` | Generate Cloudflare allowlist rules for UFW | Not exercised |
| `get-cert.sh` | Issue or install Cloudflare Origin cert/key (API or manual) | Not exercised |
| `install-site.sh` | Add site to WordPress multisite, map to apex domain | Exercised |
| `mcp-cf.sh` | Validate Cloudflare MCP portal access | Exercised |
| `onboard-zone.sh` | Create or ensure Cloudflare zone + DNS and update domains.csv | Not exercised |
| `perf-load.sh` | Run load tests and capture telemetry for a WordPress site | Exercised |
| `rules-cf.sh` | Get, put, or copy Cloudflare rulesets (firewall, cache, rate) | Exercised |
| `setup-wp.sh` | Bootstrap WordPress multisite base configuration | Not exercised |
| `slice-logs.sh` | Extract log slices for review and correlation | Not exercised |
| `verify-cf-auth.sh` | Validate Cloudflare credentials (token/key) | Exercised |

Orchestration scripts (entrypoints):
| Script | Purpose | Status |
|--------|---------|--------|
| `check-verify.sh` | Run syntax/unit tests and read-only edge/DNS/origin/WP checks | Exercised |
| `check-domain.sh` | End-to-end validation (edge, origin, WP) | Exercised |
| `test-record.sh` | Run validation checks and record status updates in domains.csv | Not exercised |

Helper and library scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `common.sh` | Shared library functions (sourced by other scripts) | Library |
| `auth.sh` | Cloudflare auth helpers and API request utilities | Library |
| `cli.sh` | Shared option parsing helpers | Library |
| `orch.sh` | Orchestration helper functions for check runners | Library |
| `mcp.sh` | MCP helper functions | Library |

Unit test scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `test_common.sh` | Unit tests for shared helpers | Test |
| `test_cf.sh` | Unit tests for Cloudflare helpers | Test |
| `test_cli.sh` | Unit tests for CLI helpers | Test |
| `test_mcp.sh` | Unit tests for MCP helpers | Test |

#### Test scripts syntax
`bash -n scripts/*.sh`

#### Permissions
Permissions and ownership policy for WordPress files are documented in `Operations.md` section 4.5 (`Operations.md#45-wordpress-files-and-permissions`). The README does not repeat them to avoid drift.

---

### Troubleshooting
Use `Operations.md` sections 5.2 and 6.1 (`Operations.md#52-site-troubleshooting`, `Operations.md#61-validation-checks`) for the authoritative troubleshooting and validation flow.

---

## Open Questions, Gaps, and Pending Decisions
This list aggregates outstanding questions, TODOs, and unresolved design points across the documentation. Each item links to the document that carries the full context or tradeoff discussion.

### Documentation and Ownership
- **Operations vs. HardenUbuntu overlap:** reconcile remaining duplication and ensure each file follows the ownership rules above (`Operations.md`, `HardenUbuntu.md`).
- **Apache/PHP/MySQL doc split:** move Apache/PHP/MySQL configuration out of `HardenUbuntu.md` and `Operations.md` into a dedicated document (TODO).

### Cloudflare Edge and Policy
- **Cloudflare schema validation applicability:** decide whether schema validation should be enabled at all, what conditions justify it, and how to validate impact before standardizing (`Operations.md#345-security-settings`).
- **Cloudflare API workflow standardization:** define the minimal repeatable API flow for zone onboarding and clarify where UI validation remains mandatory (`Operations.md#35-automation`).
- **Security hardening scope:** confirm which edge and host controls are mandatory across all zones and how exceptions are documented (`MULTI.md#88-security-hardening`).

### Recording, Inventory, and Automation
- **Recording policy questions (postponed):** write lock, downgrade behavior, status transitions (including `status_wp=install`), redirect transition rules, and whether API lookups should mask inventory gaps (`Record.md#open-questions-and-todos`).
- **Automation plan open items:** inventory format, runner design, and credential policy follow-ups (`Record.md#open-questions-and-todos`).

### Scripts and Validation
- **Scripts TODOs and option registry:** decide whether to introduce a canonical option registry, whether to add enum validation for CLI/env values, whether to formalize shared helper predicates like `cf_has_*`, whether to revisit origin cert auth defaults, and whether to consolidate overlapping checks (`scripts/Scripts.md#todo-revisit`).
- **UFW allowlist verification (postponed):** define how `check-server.sh` should confirm UFW Cloudflare allowlist correctness (`scripts/Scripts.md#todo-revisit`).
- **MCP validation open items (postponed):** pending questions about Access/MCP endpoints and tooling (`CloudflareMCP.md#open-items`).

### Architecture and Scaling
- **Database isolation decision:** define whether multisite stays on a shared database or needs stronger isolation and what triggers the change (`MULTI.md#82-database-isolation--security`).
- **Performance optimization sequencing:** establish which optimizations come first and what thresholds justify architectural changes (`MULTI.md#85-performance-optimization`).
- **WordPress update strategy:** define staging/rollback expectations and cadence as site count grows (`MULTI.md#810-wordpress-core-update-strategy`).
- **Architecture and future investigations:** track broader platform questions, alternatives, and deferred ideas in `MULTI.md` section 8 (`MULTI.md#8-future-investigation`).

### Performance and Telemetry
- **MySQL runtime vs. config reconciliation (postponed):** decide how to compare `SHOW VARIABLES/STATUS` to `mysqld.cnf` and where to report mismatches (`Perf.md#mysql-runtime-vs-config-reconciliation`).

### Source References for Open Items
These references point to the primary locations where the open items are described in full detail and with the intended scope and rationale. Use these anchors when you need the full background before deciding or implementing.
- **Staging environment evaluation**: cost/benefit of a staging host, data sync strategy, and safe update workflows (`MULTI.md#86-staging-environment`).
- **Content delivery and asset optimization**: Cloudflare cache utilization, Images, upload CDN, cache rules, and purge workflows (`MULTI.md#87-content-delivery--asset-optimization`).
- **Scaling strategy**: thresholds for splitting multisite, multi-origin considerations, and migration planning (`MULTI.md#89-scaling-strategy`).
- **Schema validation policy**: applicability, validation method, and automation considerations for Cloudflare schema validation (`Operations.md#345-security-settings`).
- **Database isolation tradeoffs**: per-site database feasibility, isolation tooling, and restore implications (`Perf.md#database-isolation--security-future`).
- **Performance optimization sequencing**: which optimizations should be prioritized and how they should be validated (`Perf.md#performance-optimization-future`).
- **Recording policy questions**: write locks, status transitions, and downgrade handling in `domains.csv` (`Record.md#open-questions-and-todos`).
- **Script interface and helper policy**: option registry, enum validation, and shared helper predicate conventions (`scripts/Scripts.md#todo-revisit`).
- **MCP access validation**: availability of API endpoints, handshake tooling, and Free-tier gating (`CloudflareMCP.md#open-items`).

---

## References
- [WordPress Multisite Guide] https://developer.wordpress.org/advanced-administration/multisite/create-network
- [WP-CLI Handbook] https://make.wordpress.org/cli/handbook/
- [Cloudflare SSL Modes] https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/
- [Cloudflare Origin Certificates] https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/

---
