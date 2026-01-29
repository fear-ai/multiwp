# Performance and Caching
Date: January 21, 2026

## Introduction
This document consolidates our caching strategy, performance tooling, and benchmarking workflow for WordPress multisite and single-site installs on Ubuntu 24 behind Cloudflare. It is written for operations work and follows the dependency order in `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`): edge first, then origin services, then WordPress. The intent is to make decisions explicit, avoid overlapping caches, and keep a repeatable test plan with commands and validation criteria.

### Challenges
Performance work must reconcile two competing realities: the origin must remain secure and stable, while the user experience depends on latency and cache efficiency that are largely driven by Cloudflare. The problem to solve is not merely “make it faster,” but “make it measurably faster without violating the operational constraints of a shared multisite origin.” This requires a disciplined approach that prevents overlapping caches, preserves correctness under CDN behavior, and produces reproducible measurements that can be compared over time.

Key challenges include:
- **Layered caching effects**: Multiple layers (edge, PHP opcode, object cache, DB buffers) can interact in non-obvious ways and obscure where performance gains actually come from.
- **Operational safety**: Testing and tuning can unintentionally change application behavior, so safety controls, backups, and clear rollback conditions are mandatory.
- **Multi-tenant impact**: A single origin serves multiple domains; tuning must avoid improving one site at the cost of others.
- **Edge vs origin visibility**: Cloudflare absorbs a large portion of requests; origin metrics can mislead if they do not distinguish cached from uncached traffic.

### Methodology
We follow a single-change-at-a-time workflow with explicit measurement targets. Each test or adjustment records both the user-facing effects (latency percentiles, throughput, error rate) and origin pressure (CPU, memory, IO, DB latency). This aligns with `Operations.md` sections 3–5 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`) and prevents “tuning in the dark.”

Methodology steps:
1) **Define baseline**: Capture edge headers, OPcache values, MySQL variables, and any object cache state.
2) **Isolate change**: Make one change at a time, scoped to one site or one layer.
3) **Measure and compare**: Use identical test parameters before and after the change.
4) **Decide and record**: Keep a decision record with explicit rollback triggers.

### Layered architecture and references
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

## Performance metrics
We care about both origin resource pressure and external experience. For each test, record latency percentiles (p50/p95/p99), throughput (requests/sec), and error rate alongside CPU, memory, and IO. That combination tells us whether a change improves actual user experience or simply shifts load around.

## Caching strategy
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

Keep this rule to anonymous traffic only; authenticated sessions should bypass edge cache to avoid serving private content. Use one cache layer for HTML—if edge caching is on, do not enable a disk page cache plugin on WordPress. POST is not cached by Cloudflare and should not be made cache-eligible.

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
Define explicit values up front so you can validate and avoid collisions. The Redis PHP extension expects the database index as an integer; do not quote it. If you source the value from an environment variable, cast it to an integer so Redis `select()` receives a numeric DB index.
- **Multisite**: `WP_REDIS_DATABASE` = `0` (default), `WP_REDIS_PREFIX` = `wpms_` (example), `WP_CACHE_KEY_SALT` = unique per site.
- **Single-site (zero.directory)**: `WP_REDIS_DATABASE` = `1`, `WP_REDIS_PREFIX` = `zero_` (or another unique prefix), `WP_CACHE_KEY_SALT` = unique per site.

#### 2) Update zero.directory wp-config.php
In `/var/www/html/zero.directory/wp-config.php`, add or update:
```
define( 'WP_REDIS_PREFIX', 'zero_' );
define( 'WP_REDIS_DATABASE', 1 );
define( 'WP_CACHE_KEY_SALT', '<unique-string>' );
```
Use a unique `WP_CACHE_KEY_SALT` per site. Keep it stable once set so cache keys remain consistent across restarts. `WP_REDIS_DATABASE` must remain an integer literal (no quotes).

#### 3) Validate zero.directory after change
- Confirm Redis plugin status: `wp redis status`
- Example: `sudo -u www-data wp --path=/var/www/html/zero.directory redis status`
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
- Example: `sudo -u www-data wp --path=/var/www/html/wordpress redis status --url=https://alphaeos.net`
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

### Benchmarking and validation
The goal is to distinguish edge-cached versus origin behavior and record CPU, memory, and database pressure alongside latency and errors.

#### Freeze and backup before testing
Use `back-wp.sh` to freeze WordPress file changes and create backups. By default it writes backups into `/var/www/html/<domain>` so each domain has a predictable default location; override this with `--backup-directory` to keep backups outside the web root and on a dedicated volume.

Use `back-wp.sh` to freeze WordPress file changes and create backups. By default it writes backups into `/var/backups/html/<wp-root-basename>` so the multisite root maps to `/var/backups/html/wordpress` and the single-site root maps to `/var/backups/html/zero.directory`. The script only sets `DISALLOW_FILE_MODS=true` when it is not already true, and it restores `DISALLOW_FILE_MODS=false` after the backup if it changed it. Override the backup location with `--backup-directory` if you want a different layout or a separate volume.

If you use `/var/backups/html`, ensure it exists and is not writable by the web server:
```bash
sudo mkdir -p /var/backups/html
sudo chown root:root /var/backups/html
sudo chmod 750 /var/backups/html
```

Run the script (recommended):
```bash
./scripts/back-wp.sh --domain zero.directory
./scripts/back-wp.sh --domain alphaeos.net
```

Manual equivalent (if you need to run the steps by hand):
```bash
sudo -u www-data wp --path=/var/www/html/wordpress config set DISALLOW_FILE_MODS true --raw
sudo -u www-data wp --path=/var/www/html/zero.directory config set DISALLOW_FILE_MODS true --raw
RUN_ID=$(date +%Y%m%d-%H%M%S)

sudo -u www-data wp --path=/var/www/html/wordpress maintenance-mode activate
sudo -u www-data wp --path=/var/www/html/wordpress db export "/var/backups/html/wordpress/multisite_${RUN_ID}.sql"
sudo tar -czf "/var/backups/html/wordpress/multisite_wp-content_${RUN_ID}.tgz" -C /var/www/html/wordpress wp-content
sudo -u www-data wp --path=/var/www/html/wordpress maintenance-mode deactivate

sudo -u www-data wp --path=/var/www/html/zero.directory maintenance-mode activate
sudo -u www-data wp --path=/var/www/html/zero.directory db export "/var/backups/html/zero.directory/zero_directory_${RUN_ID}.sql"
sudo tar -czf "/var/backups/html/zero.directory/zero_directory_wp-content_${RUN_ID}.tgz" -C /var/www/html/zero.directory wp-content
sudo -u www-data wp --path=/var/www/html/zero.directory maintenance-mode deactivate
```

After testing, restore `DISALLOW_FILE_MODS` to its prior value:
```bash
sudo -u www-data wp --path=/var/www/html/wordpress config set DISALLOW_FILE_MODS false --raw
sudo -u www-data wp --path=/var/www/html/zero.directory config set DISALLOW_FILE_MODS false --raw
```

### Pre-flight checks
Run read-only validations for the test targets.

```bash
./scripts/check-read.sh syn unit
./scripts/check-read.sh server
./scripts/check-read.sh --api --domain zero.directory --wp-root /var/www/html/zero.directory edge dns origin wp
./scripts/check-read.sh --api --wp-root /var/www/html/wordpress --multisite edge dns origin wp \
  alphaeos.net avtranscript.com recomp.one talkdao.org
```

### Baseline capture and verification
Before tuning, capture the current runtime settings so later decisions are anchored to real values rather than assumptions. This reduces the risk of “tuning in the dark” and makes it easier to decide whether documentation should change instead of the runtime configuration.

Create a run directory:
```bash
RUN_ID=$(date +%Y%m%d_%H%M%S)
OUT=/var/tmp/multiwp/perf_${RUN_ID}
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

### Initial tests
These sanity checks confirm the stack responds as expected before sustained load. Use low concurrency and short durations so the tests are non-disruptive. Record results in the same run directory as the baseline headers and telemetry.

`perf-load.sh --init` runs these checks and writes outputs into a run directory. Options:
- `domain` (repeatable, or positional) target domain(s) to test.
- `duration` short `wrk2` duration for the initial run (default is 20s).
- `threads`, `connections` low-load settings for `wrk2`.
- `run-id` identifier for file naming (defaults to `YYYYmmdd_HHMMSS`).
- `out-dir` output directory (defaults to `/var/tmp/multiwp/perf_<run-id>`).
- `cache-bust` query parameter name (defaults to `cache_bust`).
- `cache` selects cached, bust, or both runs (default: `both`).

Example:
```bash
./scripts/perf-load.sh --init --domain zero.directory --domain alphaeos.net --duration 20s --threads 2 --connections 16 --telemetry=none
```

Add `--head` to write header snapshots into the run directory.

Initial tests to run:
1) **Edge header sanity**: confirm `cf-cache-status`, `age`, and `cf-ray` appear for each target domain.
   ```bash
   for d in zero.directory alphaeos.net; do
     curl -I "https://$d/" | rg -n "cf-cache-status|age|cf-ray"
   done
   ```
2) **Cached vs cache-busted single request**: confirm the cache-bust query forces a miss.
   ```bash
   curl -I "https://zero.directory/"
   curl -I "https://zero.directory/?cache_bust=${RUN_ID}"
   ```
3) **Low-load wrk2 sanity**: confirm a short run completes without errors before larger tests.
   ```bash
   DURATION=<set>
   CONCURRENCY=<set>
   THREADS=<set>
   RATE=<set>
   wrk2 -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" -R"$RATE" https://zero.directory/
   wrk2 -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" -R"$RATE" "https://zero.directory/?cache_bust=${RUN_ID}"
   ```
4) **Multisite sanity**: run the same low-load test on a multisite domain.
   ```bash
   wrk2 -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" -R"$RATE" https://alphaeos.net/
   wrk2 -t"$THREADS" -c"$CONCURRENCY" -d"$DURATION" -R"$RATE" "https://alphaeos.net/?cache_bust=${RUN_ID}"
   ```

### Load generation
We use `wrk2` for sustained load testing because it supports a fixed request rate and makes comparisons between configuration changes more reliable. The fixed-rate model avoids unbounded client pressure and makes it easier to attribute changes in latency and CPU to the configuration change rather than to changing load. `wrk` remains useful when you explicitly want to push the origin as fast as it can go, but the default workflow in this repository uses `wrk2`.

`perf-load.sh` prefers a local `wrk2` build at `/home/ubuntu/WP/wrk2/wrk` when present, and falls back to `wrk2` on `PATH`. Override this with `WRK_BIN` if you need a specific binary.

#### wrk2 calibration and short-run latency
`wrk2` performs a calibration step after a fixed warm-up period (`CALIBRATE_DELAY_MS`, currently 10,000ms in the source). During calibration it resets the latency histograms and starts the periodic rate sampler. If the total run duration is at or near the calibration delay (for example, 10s runs), the histogram reset can happen at the end of the run, resulting in `Latency 0.00us` or `NaN` and a `Total count = 0` even when requests completed successfully. Apache logs confirm that the requests completed in this case; the missing latency data is a tool behavior, not an origin failure.

We patched the local `wrk2` source to return `0` (not `NaN`) when the histogram has zero samples. This avoids spurious NaN output but does not solve the underlying measurement gap; a zero-sample histogram still means the latency data is not valid for that run.

We also added a `--warmup <T>` option to the local `wrk2` build and skip calibration when `duration <= warmup`. This prevents the histogram reset from wiping short runs and makes 10s runs usable when a warmup is not desired.

We treat this as a known limitation of short runs and document the following solutions and rationale:
- Prefer longer durations so the post-calibration window is non-trivial. The default run duration is now 20s.
- Reduce `CALIBRATE_DELAY_MS` in the `wrk2` source (for example, 1–2 seconds) and rebuild so short runs still include a measured window.
- Add a CLI option (for example, `--warmup` or `--calibrate-ms`) to make calibration delay configurable per test.
- Patch `wrk2` to skip the histogram reset when the run duration is shorter than the calibration delay so the collected data is retained.

When `--report` is used, the summary falls back to the `Thread calibration: mean lat.` value if the `Latency` line is `NaN` or `0.00us`. This ensures we still emit a consistent value, but it is a fallback and should be interpreted with that limitation in mind.

Install sysstat for telemetry. `wrk2` is not packaged in Ubuntu by default and is typically built from source; `wrk` is available from APT if you want the unbounded variant for quick manual checks.
```bash
sudo apt-get update
sudo apt-get install -y wrk sysstat
```

Use consistent parameters across runs and record them in the results.

`perf-load.sh` runs init or load tests and can collect telemetry. Options:
- `domain` (repeatable, or positional) target domain(s) to test.
- `init`, `load` select the mode (defaults to `init`).
- `duration` load duration per run (for example, `20s` or `2m`). Default is 20s for both init and load.
- `threads`, `connections` for `wrk2`.
- `rate` sets the fixed request rate for `wrk2` (`-R`). `wrk2` is always used; mode defaults are init `threads=1`, `connections=1`, `rate=10` and load `threads=2`, `connections=4`, `rate=20`.
- `run-id` identifier for file naming (defaults to `YYYYmmdd_HHMMSS`).
- `out-dir` output directory (defaults to `/var/tmp/multiwp/perf_<run-id>`).
- `cache-bust` query parameter name (defaults to `cache_bust`).
- `interval` telemetry sampling interval (seconds).
- `telemetry` selects telemetry tools (`sar`, `pidstat`, `vmstat`, `iostat`, `all`, `none`), with comma lists allowed.
- `head` write response headers for cached and cache-busted requests.
- `cache` selects cached, bust, or both runs (default: `both`).
- `report` emit a summary of key wrk2 metrics after each run.

When `--head` is used, cached headers are saved as `${prefix}_head.txt` and cache-busted headers as `${prefix}_head_bust.txt` in the run directory.

When running `perf-load.sh` through an external command runner, use a timeout of at least 60 seconds.

When `--report` is used, the summary always reports `REQ_PER_SEC`, `LATENCY_AVG`, `LATENCY_MAX`, and `NOT_200_PCT`. `LATENCY_AVG` is taken from the `Latency` line; if wrk2 reports NaN or `0.00us` there, the script falls back to the `Thread calibration: mean lat.` value.

When `--report` is used with telemetry enabled, the summary reports `CPU_TOTAL_PCT_MAX`, `CPU_BUSY_CORES_MAX`, and `LOAD_1_MAX` if `sar` is selected. If telemetry includes `sar` plus any other tool, it also reports `MEM_AVAIL_MB_MIN`, `MEM_AVAIL_MB_AVG`, `MEM_USED_PCT_MAX`, `MEM_USED_PCT_AVG`, `CPU_USER_PCT_MAX`, `CPU_SYSTEM_PCT_MAX`, `CPU_IOWAIT_PCT_MAX`, `CPU_STEAL_PCT_MAX`, `CPU_TOTAL_BIN5_AVG`, `CPU_TOTAL_TREND`, and `LOAD_1_AVG`. If telemetry includes `pidstat`, it reports `APACHE_CPU_SUM_AVG`, `APACHE_CPU_SUM_MAX`, `APACHE_CPU_SAMPLES`, `APACHE_CPU_SUM_BIN5_AVG`, and `APACHE_CPU_SUM_TREND`.

### Run metadata file
Each perf run directory should include a `run.param` file per domain with the run parameters and time bounds. This file is intended to make post-processing and correlation reliable without relying on filename conventions. The format is `KEY: value` with one entry per line so it can be parsed by simple tooling. Each `run.param` is named with the same prefix as its corresponding output files.

We use UTC internally for time bounds to match Cloudflare and Apache access logs, and we also record local time and timezone for operator context. Timestamps use second resolution and a trailing `Z` in UTC. A small log padding value is recorded so the same correlation window can be reused later without guessing.

Required fields (all runs):
- `HOSTNAME`, `ORIGIN_IPV4`
- `RUN_ID`, `RUN_DIR`, `KIND` (`idle` or `load`), `DOMAIN`, `MODE`, `CACHE_MODE`
- `UTC_START`, `UTC_END`
- `LOCAL_TZ`, `LOCAL_OFFSET`, `LOCAL_START`, `LOCAL_END`
- `LOG_PAD_SEC`
- `SCRIPT_EXIT`

Load fields (only when load tools run):
- `RATE`, `THREADS`, `CONNECTIONS`, `DURATION`
- `LOAD_TOOL`, `LOAD_CMD`
- `LOAD_EXIT`

Header fields (only when `--head` is used):
- `HEAD_CMD`
- `HEAD_EXIT`

Telemetry fields (only when telemetry runs):
- `TELEMETRY`, `TELEMETRY_SCOPE`, `TELEMETRY_INTERVAL_SEC`
- `SAR_CMD`, `PIDSTAT_CMD`, `VMSTAT_CMD`, `IOSTAT_CMD` (only for the tools that actually ran)

Rationale:
- `SCRIPT_EXIT`, `LOAD_EXIT`, and `HEAD_EXIT` tell us whether the run produced valid output without assuming that every tool was enabled. Telemetry exit status is postponed because those processes are intentionally stopped and report signal-based exits that look like failures.
- Recording both parameter variables and the full command lines makes the metadata self-documenting even when arguments are derived from defaults.
- UTC-first timestamps avoid ambiguous log correlations; local timestamps preserve operator context.

Postponed items (record here but do not implement yet):
- Telemetry exit status and stop signals (`SAR_EXIT`, `PIDSTAT_EXIT`, etc.) because signal-based stops make a raw exit code misleading.
- Sub-run labels for cached/bust runs when `CACHE_MODE=both`; for now we correlate via timestamps only.
- Cache-bust value and parameter name (explicitly omitted unless a future workflow requires it).
- Automated log collection and log slicing with `LOG_PAD_SEC`; this is planned but not active.

Example:
```bash
./scripts/perf-load.sh --load --domain zero.directory --domain alphaeos.net --duration 30s --threads 4 --connections 64
```

Manual runs (if you want to run `wrk2` directly):

### Log Formats
This section captures the log and metadata conventions for performance runs. The goal is to make every run self-contained and reproducible, and to make later correlation possible even if filenames are copied elsewhere. The conventions apply to scripted runs and to manual runs that follow the same layout.

#### Run directory layout
Each run writes to a directory named by the run identifier. Output files are written into that run directory using a per-domain prefix so multiple domains do not collide.

- Run directory: `/var/tmp/multiwp/perf_<RUN_ID>`
- Metadata: `${prefix}_run.param`
- Raw output: `${prefix}_head*.txt`, `${prefix}_wrk*.txt`, `${prefix}_sar.log`, `${prefix}_pidstat.log`, `${prefix}_vmstat.log`, `${prefix}_iostat.log`, `${prefix}_cgtop.log`
- Summary: `${prefix}_report.txt` (only when `--report` is used)

Avoid embedding cache mode or load type in the directory name. We prefer a single run directory that contains all cached and cache-busted results, and we capture those details in `run.param` instead. This keeps filenames stable and avoids accidental mismatches when runs are copied or compared.

#### File naming rules
Header and load outputs follow a consistent naming pattern inside the run directory so tools can be found without parsing the metadata file.

- `${prefix}_head.txt` and `${prefix}_head_bust.txt` for cached and cache-busted headers.
- `${prefix}_wrk.txt` and `${prefix}_wrk_bust.txt` for cached and cache-busted load runs.
- When `--cache` is not `both`, only the applicable file is written.
- Telemetry logs retain the tool name (for example, `sar.log` and `pidstat.log`) so they remain usable outside the script.

The suffix `_bust` is the only cache-specific marker in filenames. All other mode or run context is captured in `run.param`.

#### Metadata file format
The `run.param` file is the authoritative record of a run. It is intentionally line-oriented so it can be parsed with basic tooling (shell, `awk`, Python) without requiring JSON or YAML parsing.

- Format: `KEY: value`, one entry per line.
- Keys are uppercase with underscores and avoid spaces.
- Values are recorded exactly as used, including derived defaults.

Required fields are listed in the Run metadata file section above and are expected for every run. When a tool does not run, its command and exit fields are omitted so the metadata reflects what actually happened.

#### Time format and log correlation
We use UTC for all time bounds because Cloudflare and Apache logs are recorded in UTC by default, and it simplifies cross-system correlation.

- UTC timestamps end with `Z` and are recorded at second resolution.
- Local time and timezone are recorded for operator context.
- `LOG_PAD_SEC` captures the correlation padding window so log slicing can be repeated later.

This design avoids relying on filesystem timestamps, which can drift when files are copied or rotated.

#### Telemetry selection and reporting
Telemetry selection is driven by `--telemetry`. The metadata file records:

- The selected telemetry list (for example, `sar,pidstat`).
- The sample interval.
- The exact command line for each tool that ran.

The summary report (`${prefix}_report.txt`) is optional and is derived from raw files; it should never replace the raw tool output. The report is intended for quick triage, while the raw logs are the source of truth for deeper analysis.

#### Cache handling and run modes
When `--cache=both` is selected, the script performs two runs and writes two files (`*_bust.txt` and the cached base name). For single-cache modes, only one file is written, and the cache mode is recorded in `run.param`.

This approach keeps the file naming stable while still making cache behavior explicit in metadata. It also ensures the run directory remains the single source of truth for that run, regardless of how many cache variants were executed.

#### Log collection and review design
Use `scripts/slice-logs.sh` to extract Apache and system log slices for a run based on its `run.param` file. This provides a consistent, repeatable log window without relying on filename timestamps. Example:
```bash
./scripts/slice-logs.sh --run-param /var/tmp/multiwp/perf_<run-id>/<prefix>_run.param
```

This design describes how to automate log slicing and review for each perf run. The goal is to keep raw logs intact, use the run metadata as a source of truth, and produce deterministic slices and summaries that can be compared across runs.

##### Inputs and time window
Log slicing is driven by `run.param` for a given domain/run. The script reads:

- `UTC_START` and `UTC_END` for the run time bounds.
- `LOG_PAD_SEC` as a symmetric padding value.
- `DOMAIN` for domain-specific Apache log selection.
- `RUN_ID` and `RUN_DIR` for output naming.

The slice window is computed as:

- `WINDOW_START = UTC_START - LOG_PAD_SEC`
- `WINDOW_END = UTC_END + LOG_PAD_SEC`

The log slicer uses UTC for Apache logs and local time for system logs unless the system timezone is also UTC (as on this host). Time conversion should be explicit and recorded in the outputs to avoid ambiguous correlations.

##### Log sources
The initial implementation targets the following sources and does not modify or rotate any log files:

Apache (domain-specific):
- SSL access log for the domain (`alphaeos_ssl_access.log` pattern)
- SSL error log for the domain (`alphaeos_ssl_error.log` pattern)
- HTTP access/error logs only when a non-SSL origin is expected for the domain

System:
- `/var/log/syslog`
- `/var/log/auth.log`
- `/var/log/kern.log`
- `/var/log/ufw.log` (if enabled)

The log list is explicit to prevent accidental expansion. If no log file exists, record a warning and continue.

##### Output files
Sliced logs are written into the same run directory with a consistent naming convention:

- `${prefix}_apache_access.log`
- `${prefix}_apache_error.log`
- `${prefix}_syslog.log`
- `${prefix}_auth.log`
- `${prefix}_kern.log`
- `${prefix}_ufw.log`
- `${prefix}_log_summary.txt`

Each file preserves the original log order and includes only entries inside the window. No reformatting is performed. The summary file is derived from the slices and is optional.

##### Parsing rules
Apache and system logs use different timestamp formats. The slicer should parse each log with a format-specific matcher:

- Apache access/error: `[%d/%b/%Y:%H:%M:%S %z]`
- Syslog/auth/kern/ufw: `Mon DD HH:MM:SS` (local time, without year)

For syslog-style entries, the current year and local timezone are assumed; the script should record these assumptions in the summary.

##### Summary content
The summary should be concise and focused on diagnosis:

Apache access:
- Request count by status (2xx, 3xx, 4xx, 5xx)
- Top paths (by count)
- Top remote IPs (by count)

Apache error:
- Unique error lines and counts
- Any 5xx error messages, if present

System logs:
- Auth failures and SSH login attempts (auth.log)
- Kernel warnings (kern.log)
- UFW blocks (ufw.log)

The summary does not replace the raw slices; it provides a quick review and highlights anomalies.

##### CLI and integration
Implement log slicing as a standalone script (for example, `scripts/slice-logs.sh`) so it can be used after a run or against historical data. Suggested interface:

```
slice-logs.sh --run-dir /var/tmp/multiwp/perf_<RUN_ID> --domain alphaeos.net
```

The script should locate the matching `${prefix}_run.param`, compute the window, and write the sliced logs alongside the perf outputs. Integrating log slicing into `perf-load.sh` can be deferred until the log slicer stabilizes.

##### Reliability and safety
The log slicer must be read-only and must not edit log files. It should:

- Fail fast if the run metadata is missing or unreadable.
- Warn (not fail) if a log file is missing.
- Record the computed window and any parsing assumptions in the summary.
- Avoid parsing compressed logs in the initial version; add gzip support later if needed.
```bash
wrk2 -t4 -c64 -d<duration> -R<rate> https://zero.directory/
wrk2 -t4 -c64 -d<duration> -R<rate> "https://zero.directory/?cache_bust=${RUN_ID}"
```

```bash
for d in alphaeos.net avtranscript.com recomp.one talkdao.org; do
  wrk2 -t4 -c64 -d<duration> -R<rate> "https://$d/"
  wrk2 -t4 -c64 -d<duration> -R<rate> "https://$d/?cache_bust=${RUN_ID}"
done
```

### Host telemetry during tests
Collect CPU, memory, and IO metrics during each test window so origin pressure can be correlated with latency. When telemetry is enabled, `perf-load.sh` starts and stops telemetry per domain and saves the logs alongside `wrk2` output using the same run identifier.

```bash
vmstat 1 > "$OUT/vmstat.log" &
pidstat -ru -C apache2 1 > "$OUT/pidstat-apache.log" &
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

### Load & Telemetry Tools
The load and telemetry tools we rely on come from distinct projects and they emit different formats. This matters for correlation and post-processing, so we record the origin, scope, and output shape here. All of the tools listed below are open source.

**Load generation**
`wrk` and `wrk2` are C-based HTTP load generators derived from the original `wrk` codebase. `wrk2` adds fixed-rate scheduling to prevent coordinated omission and to keep requests/sec stable across runs. Both tools emit plain-text output with no timestamps, which means that correlation with system logs relies on explicit start/end timestamps recorded by the test harness.

Key arguments:
- `wrk`: `-t` (threads), `-c` (connections), `-d` (duration). It runs as fast as possible.
- `wrk2`: `-t` (threads), `-c` (connections), `-d` (duration), `-R` (rate). It requires an explicit rate. The local build also supports `--warmup <T>` to set the calibration delay; `0` disables calibration.

**Process and system telemetry**
`pidstat` and `sar` are part of the sysstat suite. `pidstat` reports per-process CPU and memory, while `sar` reports system-wide CPU, memory, load, and network. `vmstat` and `iostat` are lightweight system monitors commonly installed with `procps` and `sysstat`; they provide fast, low-overhead summaries of CPU, memory, and storage latency.

Key arguments and format notes:
- `pidstat`: `-u` (CPU), `-r` (memory), `-C <name>` (filter by command). Output is time-stamped and split into CPU and memory sections.
- `sar`: `-u` (CPU), `-r` (memory), `-n DEV` (network), `-q` (load). Output is time-stamped and sectioned by resource type.
- `vmstat`: interval only (for example, `vmstat 1`), no timestamps by default; the interval and line order imply time progression.
- `iostat`: `-xz` (extended stats and utilization), optional `-t` if you need explicit timestamps. Without `-t`, output is block-based with time implied by interval.

Overlap and uniqueness:
- `vmstat` and `sar` both report CPU and memory, but `sar` is easier for time-series parsing and aggregation.
- `pidstat` is the only tool that attributes CPU/memory to a specific process, which is essential for separating Apache from MySQL.
- `iostat` is the only tool that provides queue depth and device latency metrics, which are required to identify storage bottlenecks.

### Test Duration
Use this section to record how long runs actually take and to explain how to estimate or bound them. `wrk2` duration is per run, not total time; a cached + bust run takes roughly 2 × duration plus startup overhead and telemetry shutdown.

Record format:
- Parameters: `cache`, `duration`, `threads`, `connections`, `telemetry`, `head`.
- Observed wall time.
- Notes about delays (for example, DNS, TLS, or slow origin).

Estimation guidance:
- Cached-only or bust-only: expected wall time ≈ duration + overhead.
- Cached + bust: expected wall time ≈ 2 × duration + overhead.
- Overhead grows with telemetry (starting/stopping tools) and with longer domains lists.
### Apache telemetry
Apache status and timing logs explain whether latency is caused by PHP worker saturation, slow upstream responses, or client-side behavior. This is especially important when edge caching is bypassed, because the origin becomes the bottleneck. Use these signals to decide whether the next change should be PHP tuning, database work, or cache rule adjustment.

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
1) Run `wrk2` with fixed parameters for each domain and scenario (cached and cache-busted).
2) Collect host telemetry during each run (`vmstat`, `pidstat`, `iostat`, `sar`) and store it alongside `wrk2` output.
3) Capture edge headers during the run window to validate cache behavior (`cf-cache-status`, `age`, `cf-ray`).
Use the Decision record template in the Decisions section to capture outcomes and next steps.

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
3) Run cached and uncached `wrk2` tests with fixed parameters.
4) Collect host telemetry during each run and save outputs.
5) Review results, compare against baseline, and log the decision.
6) Apply a single change and re-run the same test matrix.
7) Record the final outcome and either proceed to the next phase or stop.

## Decisions and postponed items
This section consolidates decision records, postponed work, future improvements, and tooling alternatives so the execution sections can stay focused on commands and repeatable steps.

### Decision record
For each change or test, record:
- Domain, URL, scenario (cached/uncached), and test parameters.
- Edge headers and any cache analytics snapshot (paid tiers only).
- Latency percentiles (p50/p95/p99), throughput, and error rate.
- Origin pressure: CPU, memory, IO, Apache workers.
- Decision, expected impact, and rollback trigger.
- Re-test delta.

### Postponed items
The following items are acknowledged but intentionally postponed so the execution workflow can stabilize before the tooling and data model are refactored:
- Script design for automated performance runs and baseline comparisons.
- Data model changes for associating performance results with domain inventory.
- Cross-document restructuring of `HardenUbuntu.md` and `MULTI.md` for broader audience partitioning.

### Future improvements
These are not required for the current stack but remain valid upgrade paths:
- Optional microcache at the origin for short-lived anonymous caching. If added, keep TTL in the 1–5 second range, bypass on authenticated cookies and admin paths, and ensure purge hooks fire on publish.
- Stale-while-revalidate at the edge or origin once purge behavior is proven and you want brief resilience during origin blips.
- Cache key normalization when query strings drive the cache-bust behavior for specific templates.

### Alternatives and tooling (CLI-only focus)
Our environment is remote and CLI-only, so prioritize tools that run from the shell without long-lived services.

Applicable in CLI-only sessions:
- Load tools: `wrk2` (primary), `wrk` (unbounded), `hey` (simple reports), `ab` (legacy baseline).
- Telemetry: `vmstat`, `pidstat`, `iostat`, `sar`, plus interactive `top`/`htop`.
- Short-lived profiling: WP-CLI `profile` and Query Monitor (enable briefly only).

Service-style or heavier alternatives (use only if you want long-running daemons or dashboards):
- `k6` for scripted scenarios and complex workflows.
- `atop` for historical snapshots with per-process detail.
- `dstat` for combined CPU/memory/network views.
- `netdata` or `collectd` for continuous dashboards and long-term retention.

## References
These references provide background on the tools and features used above:
- Cloudflare cache response headers: https://developers.cloudflare.com/cache/concepts/cache-responses/
- Cloudflare cache analytics: https://developers.cloudflare.com/cache/analytics/
- Cloudflare APO: https://developers.cloudflare.com/automatic-platform-optimization/
- Cloudflare and Jetpack guidance: https://developers.cloudflare.com/support/third-party-software/content-management-system-cms/wordpress-jetpack-and-cloudflare
- WP-CLI profile command: https://developer.wordpress.org/cli/commands/profile/
- Query Monitor plugin: https://wordpress.org/plugins/query-monitor/
