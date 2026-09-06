# 05 — Self-hosted n8n running a real workflow

n8n on one VPS: PostgreSQL 17, Caddy with automatic Let's Encrypt, daily backups with a
restore that has been run, and a workflow that does something useful — a job radar that
polls three public feeds, scores posts against a DevOps keyword list, and pushes only the
new matches to Telegram. Screenshot: [screenshot.png](screenshot.png) — execution #4,
54 posts in, 10 alerts out, 3.1 s.

## What this shows

| Decision | Why |
|---|---|
| Self-hosted n8n instead of Zapier/Make/n8n Cloud | Unlimited executions for the price of a $60 VM; credentials never leave your box |
| Postgres, not the default SQLite | SQLite locks under concurrent executions and has no `pg_dump` story. n8n 2.x wants Postgres 17+ |
| Caddy in front, nothing else published | TLS renews itself; n8n and Postgres are reachable only on the compose network |
| `N8N_ENCRYPTION_KEY` set explicitly | It encrypts every stored credential. Auto-generated keys live only in the data volume and vanish with it |
| Execution data pruned after 7 days | Execution payloads are the thing that makes an n8n database grow without bound |
| `backup.sh` + systemd timer, restore tested | The Postgres 16→17 upgrade *was* the restore test: dump, new volume, restore, 131 tables |
| Image tag pinned (`n8n:2.37.10`) | `latest` pulled on a restart is an unplanned upgrade with schema migrations |
| Workflow created through the public API from `workflow.json` | Repeatable; the same file imports into any instance |

## The workflow

```
Schedule (15 min) → Feed list → Read RSS → Normalize & score → Keyword match? → Seen before? → Format alert → Telegram
```

| Node | Decision | Why |
|---|---|---|
| Read RSS | `onError: continueRegularOutput` | One dead feed must not kill the run for the other two |
| Normalize & score | Word-boundary regex, title hits count double | Plain `includes()` matched `sre` inside "presence" and `server` inside "observer" — every post scored ≥1 |
| Normalize & score | Strong terms worth 3, weak worth 1, **at least one strong term required**, threshold 4 | A single generic word like `automation` used to be enough. The first post that qualified was an ad-fraud scheme at ₹100–400 |
| Normalize & score | Negative list drops a post outright | Ad viewing, click bots, follower farming. No score is worth reading those |
| Normalize & score | Budget floor, with a rough FX table | The `budget` field was already parsed and then ignored. ₹400 and $400 are not the same offer |
| Normalize & score | Hostname parsed with a regex, not `new URL()` | The n8n task runner sandbox does not expose the `URL` global; the field came back empty |
| Seen before? | Remove Duplicates across executions, keyed by link | Dedupe state is stored in the database, so it survives restarts and never re-alerts |
| Telegram | HTML parse mode, previews off | Titles contain `&` and `<`; escaped in the format step |

Sources are Freelancer.com (all new projects, no keyword filter on their side), We Work
Remotely's DevOps category and Hacker News jobs. Upwork's RSS sits behind a Cloudflare
challenge since 2024 and is deliberately **not** scraped — their API needs an approved app.

## Deploy

```bash
sudo mkdir -p /opt/n8n && sudo chown $USER /opt/n8n && cd /opt/n8n
# copy docker-compose.yml, Caddyfile, backup.sh, .env.example, systemd/ here
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 32)/; s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)/" .env
# N8N_HOST must resolve to this box; <ip>.sslip.io works without a domain
chmod 600 .env && docker compose up -d
curl -fsS https://$N8N_HOST/healthz
sudo cp systemd/n8n-backup.* /etc/systemd/system/ && sudo systemctl enable --now n8n-backup.timer
```

Import the workflow: n8n → Workflows → Import from file → `workflow.json`, or

```bash
curl -H "X-N8N-API-KEY: $KEY" -H 'Content-Type: application/json' -d @workflow.json https://$N8N_HOST/api/v1/workflows
```

Then add a Telegram credential, put your chat ID in the last node, and activate.

If you import through the API rather than the editor, check that the Telegram node still has
`resource: message` and `operation: sendMessage`. Created without them, the node executes,
reports success in about a millisecond, passes its input straight through and sends nothing —
see [VERIFICATION.md](VERIFICATION.md).

## Operate

- Update: change `N8N_IMAGE` in `.env`, run `backup.sh`, `docker compose pull && docker compose up -d`.
- Rollback: previous tag back in `.env`, `docker compose up -d`. If the new version migrated the schema, restore the dump taken before the update.
- Restore: `gunzip -c backups/n8n-db-X.sql.gz | docker compose exec -T postgres psql -U n8n -d n8n`

See [VERIFICATION.md](VERIFICATION.md) for what was actually run and what was not.
