# Generated Cross-References

**This document is generated. Do not edit by hand — regenerate it instead.**

Both tables below are derived from the scripts in `scripts/`. Hand edits are
overwritten and, historically, drift: before this file was split out, the helper
list omitted `slice-logs.sh` (which does source `common.sh`) and `onboard-site.sh`
was missing from both tables.

**Scope — how this differs from `Options.csv`.** This file lists the scripts that
declare an explicit `case` arm for an option, including alternation arms such as
`zone|zone=*|zone-id|zone-id=*)`. `Options.csv` additionally lists scripts that
accept an option only through a shared-helper fallback in their `*)` arm (for
example `cli_cf_auth_opt`, which supplies `--auth`, `--token` and `--account` to
every Cloudflare script without any of them naming those options). So
`Options.csv` is the answer to "which scripts accept this flag", while this file
answers "which scripts parse it themselves". A library name in a row here
(`cli.sh`, `auth.sh`) means the shared parser lives there; it is not a script an
operator runs.

Regenerate:

```bash
./scripts/gen-crossref.sh > scripts/Generated.md
```

Authority: `scripts/Scripts.md` defines option semantics and is written by hand;
this file only records which script implements what.

---

## Option Cross-Reference (Alphabetical)

Long options are collected from each script's own `case` arms, so this reflects
what is implemented rather than what is documented.

- --account,auth.sh;cli.sh
- --account-name,auth.sh;cli.sh
- --all,rules-cf.sh
- --allow-redirects,rules-cf.sh
- --allow-root,check-server.sh;cli.sh;record-status.sh
- --always-use-https,cloud-settings.sh
- --apache-dir,apache-vhost.sh;check-domain.sh;check-origin.sh;check-verify.sh;cli.sh;record-status.sh
- --api,check-domain.sh;check-edge.sh;check-verify.sh;get-cert.sh;record-status.sh
- --apply,mcp-cf.sh
- --auth,auth.sh;cli.sh
- --auth-file,auth.sh;check-auth.sh;check-verify.sh;cli.sh;onboard-site.sh;record-status.sh
- --auto,get-cert.sh
- --autosite,check-verify.sh;check-wp.sh;record-status.sh
- --backup-directory,back-wp.sh
- --bearer,mcp-cf.sh
- --cache,perf-load.sh
- --cache-bust,perf-load.sh
- --ca-key,auth.sh;cli.sh
- --ca-key-file,auth.sh;cli.sh
- --catalog,mcp-cf.sh
- --check-ids,check-auth.sh;check-verify.sh
- --connections,perf-load.sh
- --copy,rules-cf.sh
- --create,cloud-dns.sh
- --date,cli.sh;cloud-redirect.sh;onboard-zone.sh;record-status.sh
- --dest,rules-cf.sh
- --dns-provider,onboard-zone.sh
- --domain,apache-vhost.sh;cli.sh;slice-logs.sh
- --domains-file,check-auth.sh;check-domain.sh;check-verify.sh;cloud-redirect.sh;cloud-settings.sh;onboard-zone.sh;record-status.sh
- --downgrade,cloud-redirect.sh;onboard-site.sh;onboard-zone.sh;record-status.sh
- --dry-run,cloud-redirect.sh;cloud-settings.sh;onboard-site.sh
- --duration,perf-load.sh;slice-logs.sh
- --email,auth.sh;cli.sh
- --err,perf-load.sh
- --file,rules-cf.sh
- --force,get-cert.sh
- --get,rules-cf.sh
- --head,perf-load.sh
- --hsts,check-domain.sh;check-edge.sh;cli.sh;record-status.sh
- --http,apache-vhost.sh
- --http-timeout,check-domain.sh;check-edge.sh;cli.sh;record-status.sh
- --include-ignore,check-verify.sh;record-status.sh
- --init,perf-load.sh
- --interval,perf-load.sh
- --ip,onboard-zone.sh
- --key,auth.sh;cli.sh
- --key-file,auth.sh;cli.sh
- --load,perf-load.sh
- --managed-add-security-headers,cloud-settings.sh
- --manual,get-cert.sh
- --min-tls-version,cloud-settings.sh
- --multisite,check-verify.sh;check-wp.sh;record-status.sh
- --multisite-domain,onboard-zone.sh
- --mysql-interval,perf-load.sh
- --none,perf-load.sh
- --norecord,cloud-redirect.sh;onboard-site.sh;onboard-zone.sh;record-status.sh
- --no-report,perf-load.sh;slice-logs.sh
- --no-sudo,check-server.sh;cli.sh;record-status.sh
- --no-telemetry,perf-load.sh
- --out-dir,perf-load.sh;slice-logs.sh
- --output,cloudflare-ips.sh
- --pad,slice-logs.sh
- --pidstat,perf-load.sh
- --portal-url,mcp-cf.sh
- --put,rules-cf.sh
- --rate,perf-load.sh
- --raw,check-cf.sh
- --redirect-url,cloud-redirect.sh;onboard-site.sh;onboard-zone.sh
- --registrar,onboard-zone.sh
- --report,perf-load.sh;slice-logs.sh
- --run-id,back-wp.sh;perf-load.sh
- --run-param,slice-logs.sh
- --singlesite,check-verify.sh;check-wp.sh;record-status.sh
- --site-type,check-verify.sh;onboard-site.sh;onboard-zone.sh;record-status.sh
- --site-types,cloud-settings.sh
- --slice,perf-load.sh
- --src,rules-cf.sh
- --ssl,apache-vhost.sh;cloud-settings.sh
- --ssl-dir,apache-vhost.sh;check-domain.sh;check-origin.sh;check-verify.sh;cli.sh;get-cert.sh;record-status.sh
- --stage,check-wp.sh;cli.sh
- --state,check-verify.sh;record-status.sh
- --telemetry,perf-load.sh
- --telemetry-full,perf-load.sh
- --template,apache-vhost.sh
- --template-check,check-wp.sh
- --template-dir,check-wp.sh;cli.sh
- --threads,perf-load.sh
- --token,auth.sh;cli.sh
- --token-file,auth.sh;cli.sh
- --type,rules-cf.sh
- --ufw,cloudflare-ips.sh
- --update,cloud-dns.sh
- --wp-root,apache-vhost.sh;check-domain.sh;check-origin.sh;check-verify.sh;check-wp.sh;cli.sh;install-site.sh;record-status.sh
- --zone,check-cf.sh;check-edge.sh;cli.sh;verify-cf-auth.sh
- --zone-id,check-cf.sh;check-edge.sh;cli.sh;verify-cf-auth.sh

Short options (getopts):

- -e,check-cf.sh
- -s,check-cf.sh

## Helper Inclusion Cross-Reference

Which program and test scripts source each helper library.

- common.sh: apache-vhost.sh;back-wp.sh;check-auth.sh;check-cf.sh;check-domain.sh;check-edge.sh;check-origin.sh;check-server.sh;check-verify.sh;check-wp.sh;cloud-dns.sh;cloudflare-ips.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-site.sh;onboard-zone.sh;perf-load.sh;record-status.sh;rules-cf.sh;setup-wp.sh;slice-logs.sh;test_cf.sh;test_cli.sh;test_cmd.sh;test_common.sh;test_mcp.sh;verify-cf-auth.sh
- cli.sh: apache-vhost.sh;back-wp.sh;check-auth.sh;check-cf.sh;check-domain.sh;check-edge.sh;check-origin.sh;check-server.sh;check-verify.sh;check-wp.sh;cloud-dns.sh;cloudflare-ips.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-site.sh;onboard-zone.sh;perf-load.sh;record-status.sh;rules-cf.sh;slice-logs.sh;test_cli.sh;verify-cf-auth.sh
- cmd.sh: perf-load.sh;test_cmd.sh
- auth.sh: check-auth.sh;check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;record-status.sh;rules-cf.sh;test_cf.sh;test_cli.sh;verify-cf-auth.sh
- mcp.sh: mcp-cf.sh;test_mcp.sh
