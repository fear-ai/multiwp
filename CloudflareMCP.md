# Cloudflare MCP
Date: 2026-01-09

## Purpose
This document captures what Cloudflare’s MCP offering provides today, how it relates to the WordPress multisite hosting workflow in this repository, and where MCP does or does not replace the Cloudflare REST API calls used by our scripts. It is written for system administrators who own Cloudflare configuration and need a clear view of which MCP features can help with verification, documentation access, or monitoring, versus which configuration tasks still rely on REST API calls.

## Summary
Cloudflare’s managed MCP servers are service-specific and appear to focus on data access, documentation, or service telemetry. Based on the published catalog (inference), there is no general “Cloudflare API MCP” server that would replace zone and settings endpoints such as `/zones/{id}/settings`, so our scripts must continue to use the REST API for configuration validation. MCP can still add value in two areas (inference):

- Documentation access and workflow assistance via the Cloudflare Docs MCP server.
- Observability or analytics verification (e.g., DNS Analytics MCP server) where Cloudflare exposes such data via MCP.

In other words, MCP is a complementary layer for knowledge and monitoring workflows, not a replacement for the configuration checks in `check-cf.sh`, `cloud-dns.sh`, or `get-cert.sh`.

## Managed Servers
Cloudflare publishes a catalog of managed MCP servers and their endpoints. The catalog includes a range of servers such as Documentation, Observability, Radar, DNS Analytics, GraphQL, AI Gateway, and others. The catalog documentation states that managed MCP servers can read configurations, process data, make suggestions, and (when authorized) make changes. This indicates that MCP can support write operations, but only when the specific server and OAuth scopes allow it. [Cloudflare MCP servers] https://developers.cloudflare.com/agents/model-context-protocol/mcp-servers-for-cloudflare/

For our use case, the list is notable for what it does not include: there is no general “Cloudflare API” MCP server or a zone-settings server that exposes the same capabilities as the REST API endpoints used by our scripts. That means MCP cannot currently serve as a drop-in replacement for zone settings, DNS record management, or certificate provisioning.

## Portals
Cloudflare’s MCP portals are configured through Cloudflare Access (Cloudflare One). Portal configuration requires an active domain on Cloudflare (full or partial/CNAME setup) and a configured identity provider in Cloudflare Zero Trust. The portal documentation focuses on OAuth-based access through Cloudflare Access policies. It does not explicitly describe plan gating for MCP portals, so availability must be verified in the dashboard for a Free-tier account. [MCP portals] https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/mcp-servers/mcp-portals/ [Linked apps] https://developers.cloudflare.com/cloudflare-one/access-controls/ai-controls/linked-apps/

## Free Tier
The documentation is explicit that Cloudflare Access has a Free plan, and that Identity Provider integration is supported for any Zero Trust tier, including Free. The account limits page lists MCP portal and MCP server count limits but does not associate them with plan tiers beyond noting that Enterprise can raise limits. The MCP portals documentation itself does not state plan requirements. As a result, MCP portals and OAuth-based MCP access are best treated as “possible but unconfirmed” for Free tier until verified in the dashboard.

Definite (explicitly documented):
- Cloudflare Access Free plan exists. [Access Free plan] https://www.cloudflare.com/zero-trust/products/access/
- Identity provider integration (example: Okta) is available on any Zero Trust tier, including Free. [Okta IdP integration] https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/okta/
- Account limits include MCP portals and MCP servers per portal, with Enterprise able to raise limits. [Access account limits] https://developers.cloudflare.com/cloudflare-one/account-limits/

Ambiguous (not explicitly documented for Free tier):
- MCP portals availability and functionality on Free tier.
- OAuth-protected MCP servers availability and functionality on Free tier.
- Access logging and observability coverage for MCP portals on Free tier.

## Verification
The most reliable confirmation is to verify feature availability in the dashboard for the account in question. The following checks are straightforward and match the documented UI paths in the MCP portals guide. [MCP portals] https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/mcp-servers/mcp-portals/

1. Verify “AI controls” section exists in Zero Trust and that MCP server and MCP portal creation are available.
2. Create a small test MCP portal and confirm it can be reached at `/mcp` using an MCP client.
3. Add a simple IdP integration (or verify it exists already) and ensure Access policies can be applied.
4. If any of these steps prompt for an upgrade or are hidden, treat MCP portal functionality as unavailable on that tier.

## MCP Authentication
Cloudflare’s MCP portals sit on top of Cloudflare Access and OAuth. In practice, this means MCP clients handle OAuth on the user’s behalf, and bearer tokens are typically not exposed unless you build a custom client. This section consolidates the recommended OAuth path, client choices, and developer tooling in a structure that we can later lift into a standalone document if needed.

### OAuth
The recommended OAuth path for this project is to use a real MCP client that implements the Access login and per-server OAuth prompts. Cloudflare’s portal workflow explicitly expects an Access login, followed by per-server authorization. This keeps us aligned with Access policy enforcement and avoids brittle token scraping. [MCP portals] https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/mcp-servers/mcp-portals/

Availability of settings and writes:
- Cloudflare’s managed MCP server catalog states that MCP servers can read configurations, process data, make suggestions, and make changes when authorized. This indicates that write operations are possible on a per-server basis, but it does not enumerate which fields are writable. Treat write availability as server- and scope-dependent and verify per endpoint before attempting changes. [Cloudflare MCP servers] https://developers.cloudflare.com/agents/model-context-protocol/mcp-servers-for-cloudflare/

Token handling and acquisition:
- MCP clients initiate the OAuth flow by navigating to the portal URL, which triggers Access login and returns an authorization flow to the client.
- Cloudflare’s OAuth guide for MCP clients describes a programmatic flow in which a client receives an `authUrl`, the user completes authorization, and the client finishes the connection. [OAuth guide] https://developers.cloudflare.com/agents/guides/oauth-mcp-client/

Token transmission and storage:
- When a bearer token is available, `mcp-cf.sh` can submit it in the Authorization header for portal probing.
- MCP clients may store OAuth tokens internally or rely on Access session cookies; plan for short-lived tokens and avoid storing them in long-lived config files.
- If you build a custom client, capture the token in your client code and store it in a short-lived location (environment variable, temporary file with `chmod 600`, or in-memory cache). Do not commit tokens to the repo.

Token lifetime:
- Access issues both a global session token and an application token (JWT). The application token controls access to the specific Access application and defaults to 24 hours, with configuration allowing immediate timeout up to one month. [Session management] https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/
- The Access authorization cookie (`CF_Authorization`) follows the same session duration rules, which affects how long an MCP client can reuse a browser session. [Session management] https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/ [Authorization cookie] https://developers.cloudflare.com/cloudflare-one/identity/authorization-cookie/

Lower-priority auth mechanisms for this project:
- Linked Apps (bearer token forwarding to a self-hosted app). [Linked apps] https://developers.cloudflare.com/cloudflare-one/access-controls/ai-controls/linked-apps/
- Service tokens for Access Service Auth. [Service tokens] https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/

### Clients
The list below is intentionally tight and focused on our use case: portal verification and eventual automation. Each item is rated for relevance and feasibility.

1) MCP Inspector
   - Relevance: High. It is the standard open-source tool for MCP testing and is explicitly supported in Cloudflare portal docs.
   - Feasibility: High. Runs via `npx` and has a Docker image; no repo clone needed. [MCP Inspector] https://github.com/modelcontextprotocol/inspector [MCP portals] https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/mcp-servers/mcp-portals/

2) `mcp-remote`
   - Relevance: High. Cloudflare recommends it when clients do not fully support remote MCP.
   - Feasibility: High. Runs via `npx` and fits the same operational model as Inspector. [Remote MCP guide] https://developers.cloudflare.com/agents/guides/remote-mcp-server/ [MCP portals] https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/mcp-servers/mcp-portals/

3) MCP SDKs (TypeScript or Python)
   - Relevance: Medium-High. Best option for custom automation and token capture, but more build effort.
   - Feasibility: Medium. Requires app code and OAuth handling. [MCP SDK] https://modelcontextprotocol.io/docs/sdk [TypeScript SDK] https://github.com/modelcontextprotocol/typescript-sdk [Python SDK] https://modelcontextprotocol.github.io/python-sdk/

### Tooling
Tooling here means runtime services and development libraries that support MCP client work, not the ready-to-run client programs listed above.

Runtime environment:
- Node.js for Inspector and `mcp-remote` execution, or Docker if Node.js is not available. [MCP Inspector] https://github.com/modelcontextprotocol/inspector

Libraries:
- TypeScript SDK for custom clients and token capture workflows. [TypeScript SDK] https://github.com/modelcontextprotocol/typescript-sdk
- Python SDK for scripting and integration work. [Python SDK] https://modelcontextprotocol.github.io/python-sdk/

### Validation
The steps below validate our assumptions and drive iteration on `mcp-cf.sh`, with a specific focus on MCP Inspector as the OAuth client. Each step includes concrete actions and expected observable signals.

1) Validate an open portal with MCP Inspector
   - Purpose: Confirm the client can connect and complete the streamable HTTP handshake without auth.
   - Action:
     - Run: `npx @modelcontextprotocol/inspector`
     - Connect to: `https://docs.mcp.cloudflare.com/mcp`
   - Expected signals:
     - Inspector loads the tool list without Access prompts.
     - `./scripts/mcp-cf.sh --portal-url https://docs.mcp.cloudflare.com/mcp` returns `PASS: Portal reachable (authorized)`.

2) Validate a protected portal with MCP Inspector
   - Purpose: Confirm Access login and OAuth prompts are enforced for protected portals.
   - Action:
     - Connect Inspector to: `https://dns-analytics.mcp.cloudflare.com/mcp`
     - Complete Access login and OAuth authorization.
   - Expected signals:
     - Tool list appears only after Access login and OAuth.
     - `./scripts/mcp-cf.sh --portal-url https://dns-analytics.mcp.cloudflare.com/mcp` returns `WARN: Portal reachable; authorization required`.

3) Capture and reuse a bearer token
   - Purpose: Determine whether token reuse is practical for automation.
   - Action:
     - Complete OAuth in Inspector for the protected portal.
     - Export the bearer token produced by the client:
       - `export MCP_BEARER_TOKEN="..."`
     - Run:
       - `./scripts/mcp-cf.sh --portal-url https://dns-analytics.mcp.cloudflare.com/mcp --bearer "$MCP_BEARER_TOKEN"`
   - Expected signals:
     - `./scripts/mcp-cf.sh --portal-url https://dns-analytics.mcp.cloudflare.com/mcp --bearer "$MCP_BEARER_TOKEN"` returns `PASS: Portal reachable (authorized)`.

4) Validate token lifetime settings (short + long)
   - Purpose: Confirm Access session duration controls portal token validity.
   - Action:
     - In Zero Trust → Access → Settings → Session Management, set a short application session duration for the MCP portal.
     - Obtain a fresh token via the portal login flow and verify that it expires as expected.
     - Set the maximum allowed duration in the same settings location.
     - Obtain a new token and verify it remains valid across repeated checks.
   - Expected signals:
     - After expiry, `mcp-cf.sh` returns `WARN: Portal reachable; authorization required`.
     - Before expiry, `mcp-cf.sh` returns `PASS: Portal reachable (authorized)`.
   - Reference: Access session management documentation. [Session management] https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/

5) Iterate `mcp-cf.sh` for authenticated access
   - Purpose: Convert validated authentication behavior into reliable checks and tests.
   - Concrete iterations:
     - Add `--bearer-file PATH` to read a short-lived token from disk (kept out of the repo).
     - Standardize `MCP_BEARER_TOKEN` as the primary env override and document precedence with `--bearer`.
     - Add `--json` output for CI ingestion with explicit `status`, `http_code`, `portal_url`, and `auth_state`.
     - Add a `--timeout` option so we can tune the streamable HTTP probe without editing the script.
     - Report `401` vs `403` vs `5xx` with distinct, actionable messages.
     - Extend `test_mcp.sh` to cover new options and JSON output parsing.

## Script Plan
A dedicated MCP script can help record evidence, reduce manual re-checks, and (when permitted) carry out limited write operations. Because Cloudflare does not document public API endpoints for MCP portal management, the script must be explicit about which steps are automated, which are manual, and which require elevated permissions or an OAuth-based MCP session.

Proposed script: `scripts/mcp-cf.sh` (verification + optional write operations)

Implementation details (current script):
- Dependencies and helpers:
  - `common.sh` for logging, `require_cmd`, and consistent exit handling.
  - `auth.sh` for `CF_AUTH_FILE` loading and credential overrides.
  - `cli.sh` for shared option parsing (`--auth-file`, `--token`, `--key`, `--email`, `--account`).
  - `mcp.sh` for MCP-specific normalization and status mapping.
- Options:
  - `--portal-url URL` to probe an MCP portal endpoint (expected `/mcp` path).
  - `--bearer TOKEN` to pass a Bearer token for protected MCP portals.
  - `--catalog` to print the managed MCP server catalog reference list.
  - `--apply` (future) to enable write operations; currently exits with an error.
  - `--help` for usage.
- Environment:
  - `CF_AUTH_FILE`, `CF_ACCOUNT_ID`, `CF_API_TOKEN`, `CF_API_KEY`, `CF_API_EMAIL` for optional REST API calls (no REST calls are made yet).
  - `MCP_PORTAL_URL` as a fallback for `--portal-url`.
  - `MCP_BEARER_TOKEN` as a fallback for `--bearer`.
- Output conventions:
  - `PASS/WARN/INFO/FAIL` prefixes, one line per check.
  - A “Manual action required” section is always emitted to guide the UI verification flow.
- Exit codes:
  - `0` for a clean run with no hard failures.
  - Non-zero if required inputs are missing or a mandatory check fails.
- Read-only scope (substantiation):
  - `mcp-cf.sh` performs only a JSON-RPC `initialize` POST to the portal URL (see “Portal Connectivity Check” under “Read Only”).
  - It does not call Cloudflare REST API endpoints or modify Access configuration.
  - No mutation endpoints or write operations are present in the script or in the “Write Ops” section below.

Usage examples (Stage 1):
- `./scripts/mcp-cf.sh --catalog`
- `./scripts/mcp-cf.sh --portal-url https://mcp.example.com/mcp`
- `./scripts/mcp-cf.sh --portal-url https://mcp.example.com/mcp --bearer $TOKEN`
- `MCP_PORTAL_URL=mcp.example.com ./scripts/mcp-cf.sh`

### Read Only
- Preflight
  - Require `curl` only when probing a portal URL.
  - Load `CF_AUTH_FILE` and apply CLI overrides for future REST API use.
- Managed MCP Servers Catalog (static)
  - Output the known catalog list as documented (docs URL), or cache a local reference file.
  - This is documentation-oriented, not an API call.
- Access / Zero Trust Checks (manual + optional API probes)
  - If Cloudflare Access REST endpoints for MCP portals become documented, add:
    - `mcp_portal_list()` to list portals and record IDs and subdomains.
  - Until then, emit a “manual action required” section describing the UI path and evidence to capture.
- Portal Connectivity Check (if a portal URL is provided)
  - `mcp_portal_probe URL`:
    - Use HTTP POST with `Content-Type: application/json` and `Accept: application/json, text/event-stream` to send a minimal `initialize` JSON-RPC request.
    - Expect 200 with `text/event-stream` for open portals, 401/403 for protected portals without auth, and success with a valid Bearer token when provided.
- Output Format
  - For each check, emit PASS/WARN/INFO with a short reason and the command or UI path to repeat.

### Write Ops
Write operations should be disabled by default and require an explicit `--apply` (or `--write`) flag plus a confirmation step. This prevents accidental changes when using the script for routine verification.

Planned write operations (only if Cloudflare exposes documented APIs or MCP methods):
- Create or update MCP portal definitions (name, subdomain, linked servers).
- Update Access policy bindings for MCP portals.
- Register or revoke OAuth-linked apps for MCP usage.

These operations should only be implemented once Cloudflare documents the relevant endpoints or MCP tooling, and the script should refuse to run them without explicit confirmation.

## Implementation
The MCP workflow is new and still evolving in Cloudflare’s documentation, so the script should be delivered in small, safe stages.

Stage 1: Read-only verification (now)
- Implement `mcp-cf.sh` with the read-only capabilities above.
- No OAuth usage, no write operations, and no unverified API calls.
- Output a summary with all manual steps and evidence needed.

Stage 2: Optional connectivity probing
- Add MCP client probing if a supported CLI is available (optional dependency).
- Record the MCP endpoint response and expected status codes.

Stage 3: Limited write operations (future, gated)
- Add `--apply` gated write tasks only after Cloudflare documents the APIs or official MCP tooling for portal management.
- Log every change, and write an audit record (timestamp + inputs) to a local file.

Stage 4: Integration hooks (future)
- Integrate with `check-domain.sh` or `check-cf.sh` to cross-reference portal availability with zone metadata.

## Open Items
Open items for the script:
- Confirm whether Cloudflare exposes API endpoints for MCP portals in the Access API.
- Identify a minimal MCP handshake sequence that can be performed from shell, or select an MCP CLI tool as an optional dependency.
- Validate plan gating in the dashboard for Free-tier accounts.

This staged approach keeps early versions safe and read-only while leaving a clear path for write operations once Cloudflare’s tooling and documentation stabilize.
