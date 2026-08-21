# 02 — VPS deployment, done so it survives

A fixed sequence for putting an app on a fresh VPS. Same order every time, because under time
pressure improvisation is where steps get skipped.

## Order matters

| # | Step | Why this order |
|---|---|---|
| 1 | `harden.sh` | Hardening a live server means downtime. Doing it first costs nothing |
| 2 | Docker + global log rotation | Set once in `daemon.json`, applies to every container ever run |
| 3 | Deploy the app | `docker compose up -d`, database not publicly bound |
| 4 | `nginx/app.conf` + certbot | Reverse proxy, then TLS |
| 5 | `backup.sh` on cron | And then `restore.sh` once, to prove it works |
| 6 | Reboot test | The step that separates "running" from "configured" |

## Scripts

**`harden.sh`** — non-root sudo user with your key, key-only SSH, `ufw` (22/80/443 only),
fail2ban, unattended security upgrades, swap, UTC, Docker with log rotation.

It runs `sshd -t` before reloading, so a config that would lock you out is rejected rather than
applied. Even so: **open a second terminal and confirm you can log in before closing the first.**
Locking yourself out of a machine you cannot physically reach is unrecoverable.

**`backup.sh`** — nightly `pg_dump` + uploads, gzipped, 7-day retention. Writes to `.partial`
and renames, so a truncated file is never mistaken for a good backup, and it verifies the dump
is neither corrupt nor empty before exiting 0.

**`restore.sh`** — the half that most setups are missing. Default mode restores into a scratch
database and prints row counts, so you can prove the backup works **without touching
production**. Run it monthly. `--live` overwrites the real database, takes a safety dump first,
and requires you to type the database name.

**`deploy.sh` / `rollback.sh`** — pull an explicit image tag, wait for health, and roll back
automatically if health never comes. `deploy.sh` records the previously healthy tag in
`.last_good`; that record is the entire reason rollback is possible.

## Nginx: the three lines people leave out

```nginx
client_max_body_size 25m;               # default 1m — every file upload 413s
proxy_set_header X-Forwarded-Proto $scheme;   # or the app builds http:// URLs and loops
proxy_set_header Upgrade $http_upgrade;       # or websockets never connect
```

`$connection_upgrade` comes from the `map` in `nginx/map-upgrade.conf`, which belongs in the
`http{}` block. Hardcoding `Connection "upgrade"` instead breaks keepalive for ordinary requests.

## TLS

```bash
certbot --nginx -d example.com -d www.example.com
systemctl list-timers | grep certbot     # renewal must be armed
certbot renew --dry-run                  # and must actually work
```

Both checks matter. A dead renewal timer is invisible for 89 days and then becomes a total
outage. The `/.well-known/acme-challenge/` location in `app.conf` must stay reachable over plain
HTTP or renewal fails.

## Behind Cloudflare

- SSL/TLS mode **Full (strict)**. "Flexible" causes redirect loops when the origin also
  redirects to HTTPS.
- Set `real_ip_header CF-Connecting-IP`, or every log line and rate limit sees Cloudflare's IP.
- Allow only Cloudflare ranges to reach 443, otherwise an attacker hits the origin IP directly
  and the WAF is decoration.

## Verification — do all of it

```bash
curl -sI https://example.com | head        # 200 + HSTS
curl -sI http://example.com  | head        # 301 to https
ss -tlnp                                   # ONLY 22/80/443 — database must not appear
./restore.sh /opt/backups/db-<latest>.sql.gz   # prove the backup replays
systemctl list-timers | grep certbot

sudo reboot                                 # then re-run everything above
```

The reboot is not optional. Half of all "it broke a week later" reports are services that were
started by hand and never enabled at boot.

## Out of scope here, on purpose

No monitoring or alerting — nothing notifies you if the site goes down. Add UptimeRobot on the
public URL at minimum, and point the alert at whoever is actually responsible for responding.
Backups also stay on the same server, which does not survive losing the server; copy them off
with `rclone` or the provider's object storage.
