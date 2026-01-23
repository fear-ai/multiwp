# Performance and Caching
Date: January 21, 2026

## Introduction
This document consolidates our caching strategy, performance tooling, and benchmarking workflow for WordPress multisite and single-site installs on Ubuntu 24 behind Cloudflare. It is written for operations work and uses the same dependency order as `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`): edge first, then origin services, then WordPress. The intent is to make decisions explicit, avoid overlapping caches, and keep a repeatable test plan with commands and validation criteria.

## Problem Statement and Challenges
Our performance work must reconcile two competing realities: the origin must remain secure and stable, while the user experience depends on latency and cache efficiency that are largely driven by Cloudflare. The problem to solve is not merely “make it faster,” but “make it measurably faster without violating the operational constraints of a shared multisite origin.” This requires a disciplined approach that prevents overlapping caches, preserves correctness under CDN behavior, and produces reproducible measurements that can be compared over time.

Key challenges:
- **Layered caching effects**: Multiple layers (edge, PHP opcode, object cache, DB buffers) can interact in non-obvious ways and obscure where performance gains actually come from.
- **Operational safety**: Testing and tuning can unintentionally change application behavior, so safety controls, backups, and clear rollback conditions are mandatory.
- **Multi-tenant impact**: A single origin serves multiple domains; tuning must avoid improving one site at the cost of others.
- **Edge vs origin visibility**: Cloudflare absorbs a large portion of requests; origin metrics can mislead if they do not distinguish cached from uncached traffic.

## Methodology
We follow a single-change-at-a-time workflow with explicit measurement targets. Each test or adjustment records both the user-facing effects (latency percentiles, throughput, error rate) and origin pressure (CPU, memory, IO, DB latency). This aligns with `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`) and prevents “tuning in the dark.”

Methodology steps:
1) **Define baseline**: Capture edge headers, OPcache values, MySQL variables, and any object cache state.
2) **Isolate change**: Make one change at a time, scoped to one site or one layer.
3) **Measure and compare**: Use identical test parameters before and after the change.
4) **Decide and record**: Keep a decision record with explicit rollback triggers.

## Architecture of the Performance Approach
Performance decisions must follow the same dependency chain as operational setup. The architecture below is conceptual and links to the canonical operational runbook for exact settings and procedures.

Layered model:
- **Edge** (Cloudflare): HTTPS enforcement, security headers, and edge caching behavior. See `Operations.md` section 3 (`Operations.md#3-cloudflare-edge`) for authoritative settings and the Cloudflare baseline.
- **Origin** (Apache/PHP/MySQL): vhosts, TLS, OPcache, and DB buffers; these are operationally configured before tuning.
- **WordPress**: application-level caching and object caching strategy, especially for logged-in paths.

Canonical references:
- Operations runbook: `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`) for edge settings, origin TLS, Apache, and WordPress structure.
- Multisite architecture: `MULTI.md` sections 2–5 (`MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`, `MULTI.md#4-infrastructure-layers`, `MULTI.md#5-operational-tradeoffs`) for architectural rationale and tradeoffs.
- DNS and TLS terms: `DNSTerms.md` (terminology and vendor references).

## Scope
This applies to:
- Cloudflare proxy on all public zones, with Full (strict), Always Use HTTPS, and managed security headers enabled.
- Multisite root at `/var/www/html/wordpress`.
- Single-site root at `/var/www/html/zero.directory`.

## Dependencies
Before changing caching or running performance tests, confirm:
- DNS is proxied through Cloudflare and is pointing at the origin IP.
- Origin certificates are installed and Apache vhosts are healthy.
- The cache baseline and security settings in `Operations.md` section 3 (`Operations.md#3-cloudflare-edge`) are applied.
- You have a defined test window, a rollback plan, and a place to store raw outputs.

## Baseline capture and verification
Before tuning, capture the current runtime settings so later decisions are anchored to real values rather than assumptions. This reduces the risk of “tuning in the dark” and makes it easier to decide whether documentation should change instead of the runtime configuration.

Create a run directory:
```bash
OUT=/var/tmp/perf-baseline-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
```

Capture edge headers:
```bash
for d in zero.directory alphaeos.net avtranscript.com recomp.one talkdao.org; do
  curl -I "https://$d/" > "$OUT/headers_${d}.txt"
done
```

Capture PHP and MySQL settings:
```bash
php -i | rg -n "opcache.enable|opcache.memory_consumption|opcache.max_accelerated_files|opcache.revalidate_freq" > "$OUT/php_opcache.txt"
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" > "$OUT/mysql_innodb_buffer_pool.txt"
mysql -e "SHOW VARIABLES LIKE 'slow_query_log';" > "$OUT/mysql_slow_query_log.txt"
```

If Redis is in use, record a quick health snapshot:
```bash
redis-cli INFO > "$OUT/redis_info.txt"
```

## Performance metrics focus
We care about both origin resource pressure and external experience. For each test, record latency percentiles (p50/p95/p99), throughput (requests/sec), and error rate alongside CPU, memory, and IO. That combination tells us whether a change improves actual user experience or simply shifts load around.

## Caching Strategy
We use a layered strategy that avoids overlapping page caches and keeps invalidation paths clear. The primary cache is Cloudflare edge caching for anonymous traffic, with Redis object cache for dynamic requests. Apache is used for headers and PHP dispatch, not page caching. This keeps cache responsibility simple and reduces purge complexity.

### Edge reach and POP impact
Cloudflare edge caching delivers the largest latency improvements by serving responses from the point of presence closest to the visitor. Caching HTML at the edge is the highest leverage layer for anonymous traffic because it prevents origin hits entirely and smooths bursts that would otherwise exhaust Apache or PHP workers.

### Caching layers and trade-offs
This summary is provided so each decision is explicit and avoids overlapping caches.

1) Edge HTML and asset caching with Cloudflare
   - Pros: highest offload, global POP coverage, shields origin from bursts.
   - Bypass: admin paths, login, authenticated cookies, and all POST.

2) CDN overlap with Jetpack
   - Jetpack Site Accelerator is compatible but redundant. Keep it off unless its image/CSS transforms are required.
   - If enabled, do not cache `/wp-admin/*` and avoid overlapping page caches.

3) Web server caching
   - Apache: keep `mod_cache` off; use Apache for headers and PHP dispatch.

4) PHP opcode cache
   - OPcache is mandatory; it reduces parse/compile overhead and stabilizes PHP latency.

5) MySQL and data layer
   - No query cache in MySQL 8; rely on InnoDB buffer pool and indexing.

6) Object cache with Redis
   - Reduces repeated DB reads for logged-in and dynamic paths.
   - Requires Redis service and authentication.

7) WordPress disk page cache plugins
   - Examples: WP Super Cache, W3 Total Cache.
   - Do not enable while Cloudflare HTML caching is active; it introduces overlapping caches and ambiguous purge behavior.

### Redis object cache separation
We use Redis for the WordPress object cache, and we need clear separation between the single-site and multisite installs. The two practical patterns are:

Option 1: single Redis DB with distinct prefixes.
- Pros: simplest to run, no Redis DB index configuration, minimal moving parts.
- Cons: flushing affects every site, and prefix mistakes can collide silently.

Option 2: separate Redis DB indices per site, with distinct prefixes.
- Pros: closer to the MySQL pattern of one instance with multiple logical databases; safer per-site flush; clearer boundaries.
- Cons: still shared memory and eviction, and requires per-site DB index config.

This document adopts Option 2 going forward: one Redis instance, distinct DB indices per site, and distinct prefixes as a second layer of protection. This keeps separation explicit while preserving a single Redis service footprint.

### Edge: Cloudflare caching
Cloudflare edge caching is the highest leverage layer for anonymous traffic. We cache HTML for GET/HEAD requests and bypass all authenticated or admin paths.

Baseline approach:
- Cache eligible: anonymous GET/HEAD.
- Bypass: `/wp-admin/*`, `/wp-login.php`, and authenticated cookies (`wordpress_logged_in_*`, `wp-settings-*`).
- Purge: single URL or host-level when content is published; avoid full purges.

Example Cache Rule (Cloudflare UI, Rules -> Cache Rules):
```
Expression:
(http.request.method in {"GET" "HEAD"})
and (http.request.uri.path ne "/wp-login.php")
and not starts_with(http.request.uri.path, "/wp-admin/")
and not any(http.request.cookies.names[*] matches "(?i)wordpress_logged_in_.*")
and not any(http.request.cookies.names[*] matches "(?i)wp-settings-.*")

Action:
Cache eligibility: Eligible
Edge Cache TTL: <set to your tested value>
Origin Cache Control: Bypass
```

Notes:
- Keep this rule to anonymous traffic only. Authenticated sessions should bypass edge cache to avoid serving private content.
- Use one cache layer for HTML. If edge caching is on, do not enable a disk page cache plugin on WordPress.
- POST is not cached by Cloudflare and should not be made cache-eligible.

Cache analytics and paid options:
Cloudflare Cache Analytics is not available on the Free tier. On Free, rely on response headers (`cf-cache-status`, `age`, `cf-ray`) and origin-side metrics to validate cache effectiveness. On paid plans (Pro/Business), Cache Analytics provides hit ratio and cache-served bytes and is useful for trend validation. APO (Automatic Platform Optimization) is also a paid option and can replace custom HTML caching rules if you decide to use it.

### Apache caching
Apache does not cache pages in this design. Keep `mod_cache` disabled. Use Apache for headers and PHP dispatch only.

### PHP OPcache
OPcache is required to reduce PHP parse/compile overhead. Validate that it is enabled and sized appropriately for the current plugin and theme set.

Check OPcache:
```bash
php -i | rg -n "opcache.enable|opcache.memory_consumption|opcache.max_accelerated_files|opcache.revalidate_freq"
```

Recommended baseline (adjust after measurement):
- `opcache.memory_consumption`: 128-256
- `opcache.validate_timestamps`: 1
- `opcache.revalidate_freq`: 60
- `opcache.max_accelerated_files`: sized to themes and plugins

### MySQL
MySQL query cache is removed in MySQL 8. Use the InnoDB buffer pool and indexes instead. Keep the slow query log enabled for diagnosis and tune buffer pool to match available RAM.

Check buffer pool size:
```bash
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
```

Check slow query logging:
```bash
mysql -e "SHOW VARIABLES LIKE 'slow_query_log';"
mysql -e "SHOW VARIABLES LIKE 'long_query_time';"
```

### WordPress
WordPress should not run a disk page cache while edge HTML caching is enabled. Use a Redis object cache to reduce database reads for dynamic pages and logged-in sessions.

Recommended baseline:
- Page cache plugin: off when edge caching is active.
- Object cache: Redis Object Cache plugin with Redis bound to 127.0.0.1 and protected by a password.
- Keep `wp-content/cache` writable but block PHP execution in writable paths.
- Set `WP_REDIS_PASSWORD` in `wp-config.php` when Redis requires authentication.

## Execution
This section is the canonical, command-level runbook for performance baselining, changes, and validation. It is intentionally detailed so repeated measurement cycles are consistent, while upstream configuration details remain in `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`).

### Configuration steps
Apply caching and performance settings in dependency order to avoid ambiguous behavior.

### 1) Cloudflare edge settings
Confirm the HTTPS baseline first (Full strict, Always Use HTTPS, managed security headers) before caching HTML. Then apply a Cache Rule like the one above for anonymous GET/HEAD traffic.

### 2) Apache configuration
Confirm no page caching modules are enabled, and keep `.htaccess` rewrite rules active (AllowOverride All). Do not add Apache-level HTTPS redirects when Cloudflare handles edge redirects.
This stack runs mod_php (not PHP-FPM), so PHP settings are read from the Apache SAPI config (for example, `/etc/php/8.3/apache2/php.ini`).

### 3) PHP OPcache
Enable OPcache and confirm values. If tuning is needed, document the change and re-test.

### 4) MySQL buffer pool and slow logs
Confirm buffer pool size and enable slow query logs for investigation when uncached traffic is slow.

### 5) WordPress object cache
Enable Redis Object Cache in WordPress and validate that it is active. Keep page cache plugins off if edge caching is in use.

### Redis Option 2 deployment
This sequence implements Redis DB separation starting with the single-site zero.directory install, then extending to multisite. It keeps the multisite on the default Redis DB to reduce disruption, and moves zero.directory to a dedicated DB index.

#### 1) Decide DB indices and prefixes
Define explicit values up front so you can validate and avoid collisions.
- **Multisite**: `WP_REDIS_DATABASE` = `0` (default), `WP_REDIS_PREFIX` = `wpms_` (example), `WP_CACHE_KEY_SALT` = unique per site.
- **Single-site (zero.directory)**: `WP_REDIS_DATABASE` = `1`, `WP_REDIS_PREFIX` = `zero_` (or another unique prefix), `WP_CACHE_KEY_SALT` = unique per site.

#### 2) Update zero.directory wp-config.php
In `/var/www/html/zero.directory/wp-config.php`, add or update:
```
define( 'WP_REDIS_PREFIX', 'zero_' );
define( 'WP_REDIS_DATABASE', 1 );
define( 'WP_CACHE_KEY_SALT', '<unique-string>' );
```
Use a unique `WP_CACHE_KEY_SALT` per site. Keep it stable once set so cache keys remain consistent across restarts.

#### 3) Validate zero.directory after change
- Confirm Redis plugin status: `wp redis status`
- Confirm Redis keyspace for DB 1: `redis-cli -n 1 --scan | head`
- Confirm no unexpected keys in DB 0 for zero.directory after a warm browse.

#### 4) Extend to multisite (wordpress root)
In `/var/www/html/wordpress/wp-config.php`, add or update:
```
define( 'WP_REDIS_PREFIX', 'wpms_' );
define( 'WP_REDIS_DATABASE', 0 );
define( 'WP_CACHE_KEY_SALT', '<unique-string>' );
```
Use a distinct prefix and salt from the single-site to prevent any cross-site overlap.

#### 5) Validate multisite after change
- Confirm Redis plugin status: `wp redis status` (with multisite context).
- Confirm DB 0 keyspace: `redis-cli -n 0 --scan | head`
- Confirm multisite pages warm correctly and do not degrade.

#### 6) Update templates to match the new Redis model
Propagate the DB index and prefix to templates so future deployments stay aligned:
- `templates/wp-config-singlesite.php`
  - Ensure `WP_REDIS_PREFIX` and `WP_REDIS_DATABASE` placeholders exist.
- `templates/wp-config-multisite.php`
  - Ensure `WP_REDIS_PREFIX` and `WP_REDIS_DATABASE` placeholders exist.

The template placeholders now expect:
```
define( 'WP_REDIS_PREFIX', '{{WP_REDIS_PREFIX}}' );
define( 'WP_REDIS_DATABASE', {{WP_REDIS_DATABASE}} );
define( 'WP_CACHE_KEY_SALT', '{{WP_CACHE_KEY_SALT}}' );
```

#### 7) Record the chosen values
Record the selected Redis DB and prefix per site in your operational notes so future operators do not reuse values accidentally. If you track these values in `domains.csv`, treat them as configuration hints, not secrets.

### Test methodology
We use a single-change-at-a-time workflow with explicit safety and decision recording so results can be attributed to specific configuration changes.

#### Operational cautions
- One HTML cache layer at a time. Do not run a WordPress page cache plugin alongside Cloudflare edge HTML caching.
- If a zone is set to DNS-only temporarily, enable an origin page cache only for the duration of the DNS-only window and disable it when the proxy returns.
- Purge at the active cache layer; avoid full purges unless you have no narrower option.

#### Decision record
For each change or test, record:
- Domain, URL, scenario (cached/uncached), and test parameters.
- Edge headers and any cache analytics snapshot (paid tiers only).
- Latency percentiles (p50/p95/p99), throughput, and error rate.
- Origin pressure: CPU, memory, IO, Apache workers.
- Decision, expected impact, and rollback trigger.
- Re-test delta.

### Benchmarking and validation
The goal is to distinguish edge-cached versus origin behavior and record CPU, memory, and database pressure alongside latency and errors.

#### Freeze and backup before testing
Announce a change freeze for the test window and disable file modifications at the WordPress layer:
```bash
sudo -u www-data wp --path=/var/www/html/wordpress config set DISALLOW_FILE_MODS true --raw
sudo -u www-data wp --path=/var/www/html/zero.directory config set DISALLOW_FILE_MODS true --raw
```

Set a run identifier:
```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)
```

Back up multisite:
```bash
sudo -u www-data wp --path=/var/www/html/wordpress maintenance-mode activate
sudo -u www-data wp --path=/var/www/html/wordpress db export "/var/backups/wp/multisite_${RUN_ID}.sql"
sudo tar -czf "/var/backups/wp/multisite_wp-content_${RUN_ID}.tgz" -C /var/www/html/wordpress wp-content
sudo -u www-data wp --path=/var/www/html/wordpress maintenance-mode deactivate
```

Back up zero.directory:
```bash
sudo -u www-data wp --path=/var/www/html/zero.directory maintenance-mode activate
sudo -u www-data wp --path=/var/www/html/zero.directory db export "/var/backups/wp/zero_directory_${RUN_ID}.sql"
sudo tar -czf "/var/backups/wp/zero_directory_wp-content_${RUN_ID}.tgz" -C /var/www/html/zero.directory wp-content
sudo -u www-data wp --path=/var/www/html/zero.directory maintenance-mode deactivate
```

## Deferred topics
The following items are acknowledged but intentionally postponed so the execution workflow can stabilize before the tooling and data model are refactored:
- Script design for automated performance runs and baseline comparisons.
- Data model changes for associating performance results with domain inventory.
- Cross-document restructuring of `HardenUbuntu.md` and `MULTI.md` for broader audience partitioning.

After testing, restore `DISALLOW_FILE_MODS` to its prior value:
```bash
sudo -u www-data wp --path=/var/www/html/wordpress config set DISALLOW_FILE_MODS false --raw
sudo -u www-data wp --path=/var/www/html/zero.directory config set DISALLOW_FILE_MODS false --raw
```

### Pre-flight checks
Run read-only validations and capture edge headers for the test targets.

```bash
./scripts/check-read.sh syn unit
./scripts/check-read.sh --api --domain zero.directory --wp-root /var/www/html/zero.directory edge dns origin wp
./scripts/check-read.sh --api --wp-root /var/www/html/wordpress --multisite edge dns origin wp \
  alphaeos.net avtranscript.com recomp.one talkdao.org
```

Capture headers:
```bash
OUT=/var/tmp/perf-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
for d in zero.directory alphaeos.net avtranscript.com recomp.one talkdao.org; do
  curl -I "https://$d/" > "$OUT/headers_${d}.txt"
done
```

### Load generation
We use `wrk` for sustained load testing because it delivers stable latency distributions and high throughput with low overhead. It is a simple tool for GET/HEAD traffic and is ideal for repeated comparisons across configurations.

Install `wrk` and the sysstat tooling for telemetry:
```bash
sudo apt-get update
sudo apt-get install -y wrk sysstat
```

Alternatives and tradeoffs:
- `hey`: simpler output with JSON and percentile summaries; good for quick reports, but less flexible under very high concurrency.
- `ab` (ApacheBench): widely available, but limited in reporting and less representative under modern HTTP patterns.
- `k6`: best for scripted scenarios and complex workflows; heavier setup and requires more scripting.

Use consistent parameters across runs and record them in the results.

Example runs (replace values with your chosen duration and concurrency):
```bash
wrk -t4 -c64 -d<duration> https://zero.directory/
wrk -t4 -c64 -d<duration> "https://zero.directory/?cache_bust=${RUN_ID}"
```

```bash
for d in alphaeos.net avtranscript.com recomp.one talkdao.org; do
  wrk -t4 -c64 -d<duration> "https://$d/"
  wrk -t4 -c64 -d<duration> "https://$d/?cache_bust=${RUN_ID}"
done
```

### Host telemetry during tests
Collect CPU, memory, and IO metrics during each test window so origin pressure can be correlated with latency.

```bash
vmstat 1 > "$OUT/vmstat.log" &
pidstat -ru -p $(pgrep -d, -x apache2) 1 > "$OUT/pidstat-apache.log" &
iostat -xz 1 > "$OUT/iostat.log" &
sar -u -r -n DEV 1 > "$OUT/sar.log" &
```

Stop telemetry after the run:
```bash
pkill -f "vmstat 1"
pkill -f "pidstat -ru"
pkill -f "iostat -xz"
pkill -f "sar -u"
```

What each tool provides:
- `vmstat`: overall CPU, memory, and run queue pressure (quick health signal).
- `pidstat`: per-process CPU and memory, useful to confirm Apache or MySQL saturation.
- `iostat`: disk IO latency and queue depth for storage bottlenecks.
- `sar`: time-series summary across CPU, memory, and network for post-run analysis.

Alternatives and integrated tooling:
- `top` or `htop` for interactive diagnosis during short tests.
- `atop` for historical system snapshots with per-process detail.
- `dstat` for combined CPU/memory/network graphs (if installed).
- `netdata` or `collectd` when you want continuous dashboards and long-term retention.

If you need repeatable collections, wrap the telemetry start/stop commands in a small script and write outputs into a run directory alongside `wrk` results. This makes re-runs consistent and simplifies comparisons.

### Apache telemetry
If you need deeper visibility during tests, use Apache modules with restricted access:
- `mod_status` for `/server-status` (restrict to trusted IPs).
- Timing fields in `CustomLog` to capture request duration in logs.

Enable `mod_status`:
```bash
sudo a2enmod status
sudo systemctl reload apache2
```

Example timing log format (apply to a test vhost only):
```apache
LogFormat "%h %l %u %t \"%r\" %>s %b %D" timed
CustomLog ${APACHE_LOG_DIR}/access.log timed
```

Why Apache visibility matters:
Apache’s status and timing logs explain whether latency is caused by PHP worker saturation, slow upstream responses, or client-side behavior. This is especially important when edge caching is bypassed, because the origin becomes the bottleneck. Use these signals to decide whether the next change should be PHP tuning, database work, or cache rule adjustment.

### Cloudflare analytics
Cache Analytics is not available on the Free tier. If you are on a paid tier, use it during the same window as load tests to confirm hit ratio and cache-served bytes, and record the snapshot or export results so they can be compared across changes. On Free, rely on edge headers and origin telemetry instead.

### Edge cache validation
For each run, record:
- `cf-cache-status`
- `age`
- `cf-ray`

These confirm whether a response was served from edge cache or fetched from origin. Cached runs should show HIT or REVALIDATED with a non-zero age, while uncached runs should show MISS, BYPASS, or DYNAMIC.

### WordPress diagnostics
Use short, targeted profiling windows:
- Query Monitor for DB and object cache activity.
- `wp profile` for hook and component timing.

Do not leave these enabled during sustained load runs.

Query Monitor usage:
Query Monitor reports database query counts and time, hooks, HTTP requests, and object cache activity. Use it to confirm Redis reduces DB reads and to identify slow plugins or theme code. It adds overhead, so enable it only for short diagnostics and disable it before load testing.

Install the WP-CLI profile package if needed:
```bash
sudo -u www-data wp package install wp-cli/profile-command
```

Example profile run:
```bash
sudo -u www-data wp --path=/var/www/html/wordpress profile stage --url=https://alphaeos.net --all
```

WP-CLI profile capabilities:
- `profile stage` to see time spent in core load stages.
- `profile hook` to identify slow hooks and plugin entry points.
- `profile eval` to profile a specific code path or function call.

## Stage-specific guidance
Multisite and zero.directory are at different stages of caching maturity and should be treated separately.

Multisite:
- Prioritize edge cache stability for anonymous traffic.
- Validate Redis object cache for dynamic paths.
- Lengthen edge TTL only after purge behavior is proven.

zero.directory:
- Favor correctness over aggressive caching until plugins and cache behavior stabilize.
- Start with conservative edge cache eligibility for HTML and focus on asset caching first.

## Future improvements
These are not required for the current stack but remain valid upgrade paths:
- Optional microcache at the origin for short-lived anonymous caching. If added, keep TTL in the 1–5 second range, bypass on authenticated cookies and admin paths, and ensure purge hooks fire on publish.
- Stale-while-revalidate at the edge or origin once purge behavior is proven and you want brief resilience during origin blips.
- Cache key normalization when query strings drive the cache-bust behavior for specific templates.

## Plan
This plan consolidates the methodology and tooling into a single, ordered workflow so each test produces comparable data and a clear decision. It is intentionally staged so that you can stop after any phase with a usable outcome.

### Baseline capture
The baseline phase captures the current runtime state and initial performance profile before any tuning. This prevents “tuning in the dark” and makes it clear whether documentation should change instead of the configuration.

Baseline tasks:
1) Confirm prerequisites from the Dependencies section (proxy, certs, vhosts, and a defined window).
2) Capture edge headers and current runtime settings (PHP OPcache, MySQL buffer pool, slow query log, Redis info).
3) Store all baseline outputs in a single run directory so comparisons remain traceable.

### Benchmarking execution
The benchmarking phase runs reproducible tests against cached and uncached scenarios while capturing host telemetry. The intent is to measure both external experience (latency/throughput/errors) and origin pressure (CPU, memory, IO).

Benchmarking tasks:
1) Run `wrk` with fixed parameters for each domain and scenario (cached and cache-busted).
2) Collect host telemetry during each run (`vmstat`, `pidstat`, `iostat`, `sar`) and store it alongside `wrk` output.
3) Capture edge headers during the run window to validate cache behavior (`cf-cache-status`, `age`, `cf-ray`).

### Decision record
The decision record is the “why” behind each change and is required before applying new tuning. It keeps the plan safe and reversible.

Decision tasks:
1) Compare baseline vs. post-change results for p50/p95/p99, throughput, and error rate.
2) Record the observed bottleneck (edge cache misses, PHP, DB, IO, or worker saturation).
3) Decide: keep, roll back, or refine. Document the decision and the next step.

### Phases
These phases align to the dependency order (edge → origin → WordPress) and allow targeted improvements without overlapping caches.

Phase 1: Edge cache policy
- Validate edge cache behavior for anonymous traffic.
- Adjust cache eligibility and TTL only after baseline is captured.

Phase 2: Origin efficiency
- Confirm OPcache sizing and revalidate frequency.
- Enable slow query logging when diagnosis is needed.

Phase 3: WordPress object caching
- Validate Redis object cache effectiveness and ensure page caches remain off when edge HTML caching is enabled.

### Steps and items
Use this list as a repeatable checklist for each test window:
1) Freeze changes and record a backup (multisite and zero.directory).
2) Create a run directory and capture baseline settings and headers.
3) Run cached and uncached `wrk` tests with fixed parameters.
4) Collect host telemetry during each run and save outputs.
5) Review results, compare against baseline, and log the decision.
6) Apply a single change and re-run the same test matrix.
7) Record the final outcome and either proceed to the next phase or stop.

## References
These references provide background on the tools and features used above:
- Cloudflare cache response headers: https://developers.cloudflare.com/cache/concepts/cache-responses/
- Cloudflare cache analytics: https://developers.cloudflare.com/cache/analytics/
- Cloudflare APO: https://developers.cloudflare.com/automatic-platform-optimization/
- Cloudflare and Jetpack guidance: https://developers.cloudflare.com/support/third-party-software/content-management-system-cms/wordpress-jetpack-and-cloudflare
- WP-CLI profile command: https://developer.wordpress.org/cli/commands/profile/
- Query Monitor plugin: https://wordpress.org/plugins/query-monitor/
