# Harden Ubuntu
Date: January 16, 2026

## Introduction
This guide defines the Ubuntu host hardening baseline for our WordPress origin servers. It focuses on operating system security, access control, patching, and logging so the host is stable before Apache, PHP, MySQL, or WordPress are configured. The emphasis is on clear, repeatable commands and verification steps so each change can be audited.

## Scope and ordering
The steps below follow dependency order. Access controls and SSH come first, then firewall, then updates, then time synchronization and logging. Optional protections follow after the core baseline. Apply these steps during initial provisioning or before any major production changes.

## Configuration scope and standardization
This hardening guide focuses on server-wide settings (Ubuntu, Apache, PHP, and MySQL) and assumes zone-specific concerns are handled in Operations.md and per-vhost configuration. This separation is intentional: server-wide controls must be consistent across all hosted domains, while each zone has its own vhost and Cloudflare settings.

Key scope decisions and standards:
- Server-wide settings cover Ubuntu, Apache modules/listeners, PHP runtime, and MySQL instance behavior. There are no per-domain database parameters in MySQL today; any domain-level behavior is handled through WordPress and vhosts.
- Vhosts are per zone. Zone-specific values live in Apache vhost files and Cloudflare settings, not in host-wide configuration.
- Cloudflare settings are expected to be largely common across zones (SSL mode, HTTPS, security headers). Deviations should be explicit and documented.
- Caching and filtering rules apply only to non-redirect zones (multisite and single-site). Redirect-only zones should avoid origin-facing cache rules.
- WordPress configuration structure and template usage are documented in Operations.md; this guide focuses on the host security and permission requirements for those files.
- IPv6 at the Cloudflare edge is acceptable when the origin is IPv4-only; Cloudflare can terminate IPv6 and proxy to the IPv4 origin. The hardening stance here is focused on the origin host, not on disabling Cloudflare edge IPv6.

Host validation script design:
We need a dedicated `check-server.sh` that reports host-level state for Ubuntu, Apache, PHP, and MySQL so the hardening baseline can be validated as consistently as edge and origin checks. The script should be read-only and should group its output into clear sections that map to this document. At minimum, it should:
- Report OS and kernel versions (`lsb_release`, `uname`).
- Report IPv6 runtime settings (`sysctl`), plus the contents of `/etc/sysctl.d/99-disable-ipv6-forward.conf` and any netplan IPv6 directives.
- Report UFW status, default policies, and the IPv6 toggle in `/etc/default/ufw`.
- Report Apache version, enabled modules, and vhost layout (`apache2ctl -V`, `-M`, `-S`).
- Report PHP runtime and OPcache settings.
- Report MySQL variables relevant to performance and logging, while warning if socket auth prevents access.

Host configuration script proposal:
We also need a separate apply script (for example, `configure-server.sh`) that can enforce the baseline with explicit flags and confirmation prompts. This script should be idempotent, default to a dry-run preview, and only apply changes after explicit confirmation. It should write a before/after report and re-run `check-server.sh` at the end to confirm changes. The intent is to separate read-only validation from mutation so operators can audit changes and roll them back if needed.

Data model limitation (to revisit):
Cloudflare auth files currently allow multiple zones in a single per-account file, while `domains.csv` is not tied to a specific account. This makes entity relationships ambiguous. We should revisit this and propose a more focused model that supports clear account/zone/domain relationships without losing flexibility.

## Baseline updates and packages
Bring the host current before applying configuration changes so your baseline uses the latest security patches.

Update packages:
```bash
sudo apt-get update && sudo apt-get -y upgrade
```

Install baseline packages used in this guide:
```bash
sudo apt-get install -y unattended-upgrades ufw needrestart
```

## Automatic security updates
Security updates reduce exposure to known vulnerabilities and should be enabled early so the host stays current after the initial provisioning. This section describes the minimal configuration that ensures security updates are applied, plus optional policy toggles you can adjust as operations mature.

Install and enable unattended upgrades:
```bash
sudo systemctl enable --now unattended-upgrades.service
```

Confirm service state and recent activity:
```bash
systemctl status unattended-upgrades.service
systemctl is-enabled unattended-upgrades.service
journalctl -u unattended-upgrades.service --since "7 days ago"
```

Configuration is split across two files. The required lines below should be present so the service runs and applies security updates.

`/etc/apt/apt.conf.d/20auto-upgrades` (enable periodic updates and unattended upgrades):
```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

`/etc/apt/apt.conf.d/50unattended-upgrades` (minimum allowed origins):
```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
```

Run a dry run when validating changes:
```bash
sudo unattended-upgrades --dry-run --debug
```

Additional policy toggles and recommendations (all in `/etc/apt/apt.conf.d/50unattended-upgrades`):
- `Unattended-Upgrade::Automatic-Reboot` and `Unattended-Upgrade::Automatic-Reboot-Time` control whether reboots happen automatically and when. The deciding factors are tolerance for unexpected downtime, availability of monitoring and on-call response, and whether you can reliably schedule maintenance windows. If short, off-hours interruptions are acceptable and you do not yet run formal maintenance windows, enable automatic reboots and set a narrow window. If even brief downtime is unacceptable or you run planned maintenance with change control, keep automatic reboots disabled and schedule manual reboots.
- `Unattended-Upgrade::Remove-Unused-Kernel-Packages` and `Unattended-Upgrade::Remove-Unused-Dependencies` keep disks tidy. Enable these on small disks or hosts with long uptime to avoid kernel accumulation and dependency drift.
- `Unattended-Upgrade::AutoFixInterruptedDpkg` reduces operator intervention after interrupted upgrades. Enable it on systems where unattended upgrades run without direct supervision.
- `Unattended-Upgrade::MinimalSteps` reduces lock times at the cost of longer overall upgrades. Use it when minimizing lock contention is more important than upgrade speed.

Automatic reboots complete security patching without operator intervention, but they can interrupt services at an unexpected time and can expose you to update loops if a reboot fails. Disabling automatic reboots avoids unscheduled interruptions but leaves the system in a partially updated state until you reboot manually. If you allow automatic reboots, set an explicit window that matches your maintenance expectations. If you disable them, track pending reboots and schedule them promptly.

For environments that start low-traffic but may grow, use a staged policy: begin with automatic reboots in a tight off-hours window to reduce operational load, then switch to manual reboots once you introduce uptime monitoring, maintenance windows, and change control. This keeps security updates flowing early, while making it easy to graduate to production discipline without changing the rest of the unattended-upgrades configuration.

Check whether a reboot is required after updates:
```bash
test -f /var/run/reboot-required && cat /var/run/reboot-required
```

## User and sudo setup
Create a dedicated administrative user account and grant it sudo so day-to-day operations do not rely on the root account. This makes audits clearer, limits accidental root usage, and keeps a single accountable identity for administrative actions. Ensure key-based access is in place before disabling password or root SSH.

Use your own administrative name. The examples below use `uwadmin`:
```bash
sudo adduser uwadmin
sudo usermod -aG sudo uwadmin
```

## SSH key basics
SSH uses a public and private key pair stored under `~/.ssh`. The private key stays on the client and is never copied to the server. The public key is installed in `authorized_keys` on the server to enable passwordless login. Keep permissions tight: `.ssh` should be 700 and `authorized_keys` should be 600.

## Key generation location
The preferred model is client-side generation, which keeps private keys off production servers and reduces exposure if a host is compromised. Server-side generation can be convenient for bootstrap automation, but it requires exporting private keys to clients, which increases the risk surface and adds key handling steps.

## Install the public key on the server
Prepare the server for the user key. This step creates the `authorized_keys` file so the public key can be installed after it is generated on the client.

```bash
sudo -u uwadmin mkdir -p /home/uwadmin/.ssh
sudo chmod 700 /home/uwadmin/.ssh
sudo cp <key.pub> /home/uwadmin/.ssh/authorized_keys
sudo chown uwadmin:uwadmin /home/uwadmin/.ssh/authorized_keys
sudo chmod 600 /home/uwadmin/.ssh/authorized_keys
```

## Client key generation examples
Generate the key on the client system, then upload the public key to the server and install it using the server-side steps above. Common copy methods include `ssh-copy-id` or copying the public key with `scp` and then running the server-side install commands.

### Windows 11
Generate a key using OpenSSH in PowerShell or Command Prompt:
```powershell
ssh-keygen -t ed25519 -C "uwadmin@<host>"
```

Upload the public key to the server:
```powershell
scp -P <ssh_port> $env:USERPROFILE\.ssh\id_ed25519.pub uwadmin@<host>:/tmp/uwadmin.pub
```

### macOS
Generate a key in Terminal on a recent macOS release:
```bash
ssh-keygen -t ed25519 -C "uwadmin@<host>"
```

Upload the public key to the server:
```bash
scp -P <ssh_port> ~/.ssh/id_ed25519.pub uwadmin@<host>:/tmp/uwadmin.pub
```

### Ubuntu
Generate a key in Terminal on Ubuntu as a local client example:
```bash
ssh-keygen -t ed25519 -C "uwadmin@<host>"
```

Copy the public key to the server:
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p <ssh_port> uwadmin@<host>
```

## Server-side generation example
Server-side key generation is not recommended for production, but it is sometimes used for bootstrap automation. If you choose this path, generate the key on the server and then copy the private key to each client that will use it. Protect the key during transfer and remove the private key from the server once distribution is complete.

Generate the key on the server:
```bash
sudo -u uwadmin ssh-keygen -t ed25519 -f /home/uwadmin/.ssh/id_ed25519 -C "uwadmin@<host>"
```

Copy the private key to a client using a secure channel:
```bash
scp -P <ssh_port> /home/uwadmin/.ssh/id_ed25519 clientuser@<client-host>:~/.ssh/
```

On the client, restrict permissions:
```bash
chmod 600 ~/.ssh/id_ed25519
```

Verify sudo access:
```bash
sudo -u uwadmin sudo -l
```

## References
- Windows OpenSSH key management: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
- Windows OpenSSH overview: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-overview
- Ubuntu OpenSSH server keys and ssh-copy-id guidance: https://documentation.ubuntu.com/server/how-to/security/openssh-server/
- OpenSSH ssh-keygen manual: https://manpages.ubuntu.com/manpages/questing/en/man1/ssh-keygen.1.html
- OpenSSH ssh-copy-id manual: https://manpages.ubuntu.com/manpages/questing/en/man1/ssh-copy-id.1.html
- macOS Remote Login overview: https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac

## SSH hardening
SSH is the highest-risk ingress path on a VPS, so we lock it down before opening the firewall.

Edit `/etc/ssh/sshd_config` to align the daemon with the no-password policy by setting `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, and `ChallengeResponseAuthentication no`, which together ensure only key-based authentication is accepted. The `AllowUsers` line is important because it limits SSH access to the named accounts only and reduces exposure from accidental or newly created users. Keep the list short and intentional, and make sure it includes the account you are testing from to avoid locking yourself out.
```
Port <ssh_port>
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
AllowUsers uwadmin
```

`UsePAM yes` keeps the PAM stack active for account restrictions, login tracking, and session policies without re-enabling password authentication when `PasswordAuthentication no` is set. This preserves standard Ubuntu access controls while enforcing key-only login.

Before reloading SSH, confirm the administrative user and key installation are complete by verifying `~/.ssh` permissions (700) and `authorized_keys` permissions (600), then test a key-based login from at least one client while keeping your current session open.

Validate and reload SSH:
```bash
sudo sshd -t
sudo systemctl reload ssh
```

Open a fresh SSH session to verify the full policy, and if it fails return to the configuration and validation steps before attempting again. After verification succeeds, record the final SSH settings for auditability and close the original session so the host is operating under the key-only policy with no legacy access paths.
```bash
ssh -p <ssh_port> uwadmin@<host>
```

### SSH probe traffic and logging expectations
Even with `PermitRootLogin no` and `PasswordAuthentication no`, SSH will log failed attempts that target root or use passwords. This is expected behavior: the log records the attempt, not a successful authentication. A single probe often produces multiple log lines (preauth, PAM failure, failed password, disconnect), so the count of log entries is usually higher than the number of connection attempts.

For investigation, `auth.log` (or `journalctl -u ssh`) provides the most detail about usernames and auth methods. The `btmp` file is useful only for coarse volume tracking because it records failed login events without the local port or requested service. UFW and kernel logs can help confirm destination ports for blocked traffic, which is useful if you need to prove that probes are hitting a non-default SSH port.

## Firewall baseline
UFW is the default Ubuntu firewall and should match the SSH port you selected. Only open what you need.

Set default policy and allow required ports:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow <ssh_port>/tcp
```

Enable and confirm:
```bash
sudo ufw enable
sudo ufw status verbose
```

## Additional addresses and interfaces
Hosts with multiple public addresses or interfaces expand the exposed surface area. Scanners routinely sweep provider IP ranges, so any routed address on the host will attract traffic, even if it is not referenced in DNS. If you do not need an additional public address, remove it from the network configuration so it is not reachable.

Use `ip -4 addr show` to inventory assigned IPv4 addresses and confirm which interface owns each one. If a secondary address is configured explicitly in netplan, remove it from the `addresses` list and apply the configuration. The active netplan file lives under `/etc/netplan/*.yaml`. Ensure the extra address is removed from the `addresses` list for the interface.

Example (edit the real file under `/etc/netplan/*.yaml`):
```yaml
network:
  version: 2
  ethernets:
    <interface>:
      addresses:
        - <primary_ipv4>/<cidr>
      # remove any secondary public IPv4 entries here
```

Apply the change:
```bash
sudo netplan apply
```

If you need a temporary removal to test impact before editing netplan, you can remove the address directly with `ip addr del`, but that change is not persistent across reboots. When removing addresses, keep a separate SSH session open to prevent lockouts.

## Disabled IPv6
If you do not publish AAAA records and do not intend to serve IPv6 directly, disabling IPv6 can reduce the attack surface and simplify firewall policy. The approach is to stop IPv6 address assignment in netplan, disable IPv6 at the kernel level, and (optionally) disable IPv6 handling in UFW so policy remains explicit. Netplan `dhcp6` and `accept-ra` both accept boolean values (`true/false` or `yes/no`) and should be set to `no` or `false` for an IPv4-only stance.

Netplan should disable DHCPv6 and router advertisements on the active interface. Update the active file under `/etc/netplan/*.yaml` so the interface has `dhcp6: no` and `accept-ra: no`.

Example (edit the real file under `/etc/netplan/*.yaml`):
```yaml
network:
  version: 2
  ethernets:
    <interface>:
      dhcp6: no
      accept-ra: no
```

Required lines in the active netplan file (for example, `/etc/netplan/50-cloud-init.yaml`):
```
dhcp6: no
accept-ra: no
```

Apply the change:
```bash
sudo netplan apply
```

### Kernel settings
Disable IPv6 at the kernel level by setting sysctl values at runtime and then making them persistent. The runtime change takes effect immediately, while the persistent file ensures the settings survive reboots. This is the foundation for the hardened stance because it prevents IPv6 address assignment at the OS level.
```bash
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
```

Persist the settings across reboots and reload them:
```bash
sudo sh -c 'printf "%s\n" \
  "net.ipv6.conf.all.disable_ipv6 = 1" \
  "net.ipv6.conf.default.disable_ipv6 = 1" \
  "net.ipv6.conf.lo.disable_ipv6 = 1" \
  > /etc/sysctl.d/99-disable-ipv6-forward.conf'
sudo sysctl --system
```

The spacing in `/etc/sysctl.d/99-disable-ipv6-forward.conf` is flexible (`key = value` and `key=value` are both valid). Use the file above as the canonical location for persistence, then validate syntax and operation:
```bash
sudo cat /etc/sysctl.d/99-disable-ipv6-forward.conf
sudo sysctl --system 2>&1 | rg -n "99-disable-ipv6-forward|ipv6|error|invalid"
sudo sysctl -n net.ipv6.conf.all.disable_ipv6
sudo sysctl -n net.ipv6.conf.default.disable_ipv6
sudo sysctl -n net.ipv6.conf.lo.disable_ipv6
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
cat /proc/sys/net/ipv6/conf/default/disable_ipv6
ip -6 addr show
```

### UFW IPv4-only
For a hardened IPv4-only stance, align all layers: kernel, firewall, and application listeners. The kernel change stops IPv6 address assignment, and UFW should be set to IPv4-only so the firewall configuration matches the OS reality and does not imply protection on a protocol you have disabled.

If you want UFW to be IPv4-only, set `IPV6=no` in `/etc/default/ufw` and then reload UFW by disabling and re-enabling it, which is required for the setting to take effect. Do this only after confirming that your SSH rule is present so you do not lock yourself out.

Required line in `/etc/default/ufw`:
```
IPV6=no
```

Reload UFW:
```bash
sudo ufw disable
sudo ufw enable
sudo ufw status verbose
```

### Apache listener alignment
Apache should use explicit IPv4 `Listen` directives so it never attempts to bind IPv6 sockets when IPv6 is disabled. This also avoids `AH00056` warnings about `[::]:80`. See the Apache listener section below for the canonical listener block.

### Verification (kernel, UFW, Apache)
After these changes, verify that the network layer is applying the Netplan IPv6 settings, then confirm the kernel flags, UFW toggle, and Apache listener configuration.
```bash
sudo netplan apply
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
cat /proc/sys/net/ipv6/conf/default/disable_ipv6
ip -6 addr show
```

Required line in `/etc/default/ufw`:
```
IPV6=no
```

Required listeners in `/etc/apache2/ports.conf`:
```
Listen 0.0.0.0:80
<IfModule ssl_module>
    Listen 0.0.0.0:443
</IfModule>
```

Confirm UFW is active and the SSH rule is still present:
```bash
sudo ufw status verbose
```

## Apache listeners, ports, and module surface
Apache listens on the ports declared in `/etc/apache2/ports.conf`, and it loads every module shown by `apache2ctl -M`. Both affect the host’s exposure. Keep the listener configuration aligned with the IPv6 stance described above, then validate the active sockets.
```bash
sudo ss -ltnp | awk 'NR==1 || /apache2/'
```

Keep the HTTPS `Listen` inside the SSL module block so it only binds when SSL is active. After changes, validate and reload:
```bash
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Module usage affects attack surface and compatibility. Start by documenting what is currently loaded:
```bash
apache2ctl -M
```

Current stance: keep the distro-default module set for the installed Apache version. The list below documents typical requirements and possible reductions for future review, but do not disable modules unless a specific need is identified and you can validate the impact.

For a WordPress + Apache + mod_php stack, the following modules are typically required or expected: `mpm_prefork`, `php`, `rewrite`, `ssl`, `headers`, `setenvif`, `reqtimeout`, `mime`, `dir`, `alias`, `deflate`, and the core authz/authn/logging modules. The items below are common candidates for removal when you want to reduce surface area, but only after confirming they are unused in your vhosts and `.htaccess`.

Commonly optional modules (disable only if unused):
- `autoindex` (directory listings). If `Options -Indexes` is always enforced and no directory indexes are expected, this module can be removed.
- `negotiation` (content negotiation, language variants). Rarely used in WordPress stacks.
- `status` (server-status). Keep only if you actively use `/server-status` for diagnostics.

Removing modules reduces surface area but can break assumptions in vhosts or `.htaccess`, so disable them one at a time and re-test site behavior.

Disable a module and reload:
```bash
sudo a2dismod autoindex
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### Apache prefork and global tuning
This host uses `mpm_prefork` with `mod_php`, so each Apache worker is a full PHP process. That makes concurrency settings and request timeouts the primary controls for CPU and memory pressure. Our tuning goal is to avoid over-committing a small host while keeping enough workers for normal traffic bursts. These are conservative starting values for Ubuntu 24 in this stack.

Prefork tuning (`/etc/apache2/mods-available/mpm_prefork.conf`), current applied values:
```apache
<IfModule mpm_prefork_module>
    StartServers             2
    MinSpareServers          2
    MaxSpareServers          4
    MaxRequestWorkers        6
    MaxConnectionsPerChild   800
</IfModule>
```

Note: `ServerLimit` is not currently set; Apache will use its internal default. If you later raise `MaxRequestWorkers`, set `ServerLimit` to the same value to avoid implicit caps.

Global tuning (`/etc/apache2/apache2.conf`):
```apache
Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 2
```

Security posture (`/etc/apache2/conf-available/security.conf`):
```apache
ServerTokens Prod
ServerSignature Off
TraceEnable Off  # default; keep as-is
```

Reasons and tradeoffs:
- Lower `MaxRequestWorkers` prevents CPU and memory thrash when PHP or WordPress requests spike.
- The current `MaxRequestWorkers 6` is intentionally conservative while benchmarking; raise it only after measuring per-process RSS and available headroom.
- `MaxConnectionsPerChild 800` helps recycle long-lived PHP workers so memory growth does not accumulate.
- `Timeout 60` stops slow or stalled clients from occupying scarce prefork workers.
- `KeepAliveTimeout 2` reduces idle worker time while still allowing short bursts of reuse.

After adjusting, validate and reload:
```bash
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### Default vhosts for direct IP traffic
Default vhosts catch traffic that arrives by IP address or with an unknown `Host` header. Keep `DocumentRoot /var/www/html/construction` so a controlled fallback exists, but use `<Location /> Require all denied </Location>` in both default vhosts to reject requests immediately. This avoids serving content to unexpected hostnames while still keeping a controlled landing page ready if you later choose to allow it.

If you want the construction page to be visible, comment out the `<Location /> Require all denied </Location>` block in the default vhosts so the `DocumentRoot` can be served. Apply this only to the default vhosts:
- `/etc/apache2/sites-available/000-default.conf`
- `/etc/apache2/sites-available/000-default-ssl.conf`

### Directory options and `.htaccess` rewrites
The detailed `.htaccess` structure (single-site vs multisite) is documented in Operations.md. This section focuses on the host requirements and permissions that keep those rules secure and functional.

Because we keep rewrite rules in `.htaccess`, Apache must allow overrides and must permit symlink traversal for rewrite rules to function. The safest operational path is to keep `AllowOverride All` on the WordPress docroot and use `Options FollowSymLinks` unless you have a specific reason to tighten it.

Keep `.htaccess` write-restricted even if the rest of the WordPress tree is owned by `www-data`. The baseline policy is to keep `.htaccess` (and the site root directory) owned by root or the deployer account with group `www-data`, and keep permissions at 640. See Operations.md for the full WordPress ownership and permissions model.

If you choose to switch to `SymLinksIfOwnerMatch`, validate that permalinks and admin paths still resolve correctly:

1) Run `sudo apache2ctl configtest` and reload Apache.
2) For each site, request the front page, a known permalink, `/wp-login.php`, `/wp-admin/`, and `/wp-json/`.
3) Check the per-site Apache error logs for rewrite or permission errors.

Do not remove both `FollowSymLinks` and `SymLinksIfOwnerMatch` while `.htaccess` remains the source of rewrite rules; Apache will refuse the rewrite directives and permalinks will fail.

If you need Apache status for performance diagnostics, keep `status_module` enabled and restrict access to `/server-status` in the vhost; otherwise it can be disabled when not in use.

## Time synchronization
Accurate time is required for TLS, log correlation, and monitoring. Ubuntu uses systemd-timesyncd by default.

Verify time sync and enable NTP:
```bash
timedatectl status
sudo timedatectl set-ntp true
systemctl status systemd-timesyncd
```

## Avahi (mDNS)
Avahi provides mDNS/Bonjour service discovery on UDP 5353. It is rarely needed on an Internet-facing WordPress origin, so we disable it to reduce background traffic and exposure.

Disable and stop the service (baseline):
```bash
sudo systemctl disable --now avahi-daemon
sudo systemctl disable --now avahi-daemon.socket
```

Verify it is inactive and the port is quiet:
```bash
systemctl status avahi-daemon avahi-daemon.socket
sudo ss -uanp | awk 'NR==1 || /:5353/'
```

If you need to hard-block it, mask the units:
```bash
sudo systemctl mask avahi-daemon
sudo systemctl mask avahi-daemon.socket
```

Remove Avahi only if you are confident no local discovery or multicast name resolution is required:
```bash
sudo apt-get remove --purge avahi-daemon
```

## Logging and retention
Set explicit journald retention so logs are bounded and reviewable.

Check current usage:
```bash
systemctl status systemd-journald
journalctl --disk-usage
```

Set retention with a drop-in file:
```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-retention.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=1G
SystemKeepFree=1G
MaxFileSec=30day
EOF
```

Apply and vacuum:
```bash
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-time=30d
```

For rotation strategy and deeper analysis, use Logs.md.

## Reboot and service restart visibility
Kernel and library updates often require service restarts or a reboot before the fixes take effect. The `needrestart` utility scans running services and reports which daemons should be restarted and whether a kernel reboot is pending. Use it after upgrades so you can complete the update cycle intentionally.

Check for restart requirements:
```bash
sudo needrestart
```

## Kernel TCP tuning note
The commented `net/ipv4/tcp_fin_timeout` and `net/ipv4/tcp_keepalive_intvl` lines in `/etc/ufw/sysctl.conf` (or `/etc/sysctl.conf` on some hosts) are intentionally left disabled. They alter global TCP behavior and should only be enabled when there is a clear operational reason such as socket exhaustion or stale connections, followed by validation. On a typical WordPress origin, the kernel defaults are appropriate and safer.
