# Generated Cross-References

**This document is generated. Do not edit by hand — regenerate it instead.**

Both tables below are derived from the scripts in `scripts/`. Hand edits are
overwritten and, historically, drift: before this file was split out, the helper
list omitted `slice-logs.sh` (which does source `common.sh`) and `onboard-site.sh`
was missing from both tables.

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

- --account,auth.sh
- --account-name,auth.sh
- --all,rules-cf.sh
- --allow-redirects,rules-cf.sh
- --allow-root,check-server.sh;cli.sh;test-record.sh
- --always-use-https,cloud-settings.sh
- --apache-dir,cli.sh
- --api,check-domain.sh;check-edge.sh;check-verify.sh;get-cert.sh;test-record.sh
- --apply,mcp-cf.sh
- --auth,auth.sh
- --auth-file,auth.sh;check-auth.sh;check-verify.sh;cli.sh;test-record.sh
- --auto,get-cert.sh
- --autosite,check-verify.sh;check-wp.sh;test-record.sh
- --backup-directory,back-wp.sh
- --bearer,mcp-cf.sh
- --cache,perf-load.sh
- --cache-bust,perf-load.sh
- --ca-key,auth.sh
- --ca-key-file,auth.sh
- --catalog,mcp-cf.sh
- --check-ids,check-auth.sh;check-verify.sh
- --connections,perf-load.sh
- --copy,rules-cf.sh
- --create,cloud-dns.sh
- --date,cli.sh
- --dest,rules-cf.sh
- --dns-provider,onboard-zone.sh
- --domain,cli.sh;slice-logs.sh
- --domains-file,check-auth.sh;check-domain.sh;check-verify.sh;cloud-redirect.sh;cloud-settings.sh;onboard-zone.sh;test-record.sh
- --downgrade,cloud-redirect.sh;onboard-zone.sh;test-record.sh
- --dry-run,cloud-settings.sh
- --duration,perf-load.sh;slice-logs.sh
- --email,auth.sh
- --err,perf-load.sh
- --file,rules-cf.sh
- --force,get-cert.sh
- --get,rules-cf.sh
- --head,perf-load.sh
- --hsts,cli.sh
- --http,apache-vhost.sh
- --http-timeout,cli.sh
- --include-ignore,check-verify.sh;test-record.sh
- --init,perf-load.sh
- --interval,perf-load.sh
- --ip,onboard-zone.sh
- --key,auth.sh
- --key-file,auth.sh
- --load,perf-load.sh
- --managed-add-security-headers,cloud-settings.sh
- --manual,get-cert.sh
- --min-tls-version,cloud-settings.sh
- --multisite,check-verify.sh;check-wp.sh;test-record.sh
- --multisite-domain,onboard-zone.sh
- --mysql-interval,perf-load.sh
- --none,perf-load.sh
- --norecord,cloud-redirect.sh;onboard-zone.sh;test-record.sh
- --no-report,perf-load.sh;slice-logs.sh
- --no-sudo,check-server.sh;cli.sh;test-record.sh
- --out-dir,perf-load.sh;slice-logs.sh
- --output,cloudflare-ips.sh
- --pad,slice-logs.sh
- --portal-url,mcp-cf.sh
- --put,rules-cf.sh
- --rate,perf-load.sh
- --raw,check-cf.sh
- --redirect-url,cloud-redirect.sh;onboard-zone.sh
- --registrar,onboard-zone.sh
- --report,perf-load.sh;slice-logs.sh
- --run-id,back-wp.sh;perf-load.sh
- --run-param,slice-logs.sh
- --singlesite,check-verify.sh;check-wp.sh;test-record.sh
- --site-type,check-verify.sh;onboard-site.sh;onboard-zone.sh;test-record.sh
- --site-types,cloud-settings.sh
- --slice,perf-load.sh
- --src,rules-cf.sh
- --ssl,apache-vhost.sh;cloud-settings.sh
- --ssl-dir,cli.sh
- --stage,cli.sh
- --state,check-verify.sh;test-record.sh
- --telemetry,perf-load.sh
- --template,apache-vhost.sh
- --template-check,check-wp.sh
- --template-dir,cli.sh
- --threads,perf-load.sh
- --token,auth.sh
- --token-file,auth.sh
- --type,rules-cf.sh
- --ufw,cloudflare-ips.sh
- --update,cloud-dns.sh
- --wp-root,cli.sh
- --zone,check-cf.sh;check-edge.sh
- --zone-id,check-cf.sh;check-edge.sh;verify-cf-auth.sh

Short options (getopts):

- -e,check-cf.sh
- -s,check-cf.sh

## Helper Inclusion Cross-Reference

Which program and test scripts source each helper library.

- common.sh: apache-vhost.sh;back-wp.sh;check-auth.sh;check-cf.sh;check-domain.sh;check-edge.sh;check-origin.sh;check-server.sh;check-verify.sh;check-wp.sh;cloud-dns.sh;cloudflare-ips.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-site.sh;onboard-zone.sh;perf-load.sh;rules-cf.sh;setup-wp.sh;slice-logs.sh;test_cf.sh;test_cli.sh;test_cmd.sh;test_common.sh;test_mcp.sh;test-record.sh;verify-cf-auth.sh
- cli.sh: apache-vhost.sh;back-wp.sh;check-auth.sh;check-cf.sh;check-domain.sh;check-edge.sh;check-origin.sh;check-server.sh;check-verify.sh;check-wp.sh;cloud-dns.sh;cloudflare-ips.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-site.sh;onboard-zone.sh;perf-load.sh;rules-cf.sh;slice-logs.sh;test_cli.sh;test-record.sh;verify-cf-auth.sh
- cmd.sh: perf-load.sh;test_cmd.sh
- auth.sh: check-auth.sh;check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test_cf.sh;test_cli.sh;test-record.sh;verify-cf-auth.sh
- orch.sh: check-domain.sh
- mcp.sh: mcp-cf.sh;test_mcp.sh
