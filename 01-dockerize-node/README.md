# 01 — Production Dockerfile and compose stack

A Node.js app, but the decisions apply to any runtime. The point is not that it runs — it is
that it stays small, restarts cleanly, and cannot take the host down.

## What this shows

| Decision | Why |
|---|---|
| Exact base tag `node:20.18-alpine` | An unpinned base means today's working build breaks next month |
| Multi-stage build | Build tools never reach production — typically 1.2 GB → ~150 MB |
| Manifests copied before source | Keeps the dependency layer cached; 40 s builds instead of 6 min |
| `USER node` | A breached root container owns the host through any mounted volume |
| `tini` as entrypoint | Node as PID 1 ignores SIGTERM and gets SIGKILLed, cutting live requests |
| `HEALTHCHECK` | Without it nothing can tell "running" from "hung" |
| `expose` not `ports` for db | `ports: 5432:5432` on a public VPS puts your database on the internet |
| `max-size`/`max-file` logging | Unbounded container logs fill a small VPS in weeks |
| Named volume for data | `docker compose down -v` deletes anonymous volumes with no undo |
| Memory limit on the app | A leak then kills one container instead of the whole host |

## Requirement on the app

The healthcheck needs a `GET /health` endpoint returning 200. If the app has none, add one —
it is a few lines, and every later layer (compose, Kubernetes probes, uptime monitoring)
depends on it.

```js
app.get("/health", (_req, res) => res.status(200).json({ ok: true }));
```

Make it check what actually matters — usually a cheap database query — but keep it fast.
A health endpoint that runs an expensive query becomes its own outage under load.

## Verify before you trust it

```bash
docker build -t myapp:test .
docker images myapp:test --format "{{.Size}}"      # note the number

cp .env.example .env && $EDITOR .env
docker compose up -d
sleep 20 && docker compose ps                       # every service must be "healthy"

curl -f http://localhost:3000/health

# the check most people skip: does it come back?
docker compose down && docker compose up -d && sleep 20 && docker compose ps

# only 80/443 should be publicly bound — the database must not appear
ss -tlnp

# CVEs in the image
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp:test --severity HIGH,CRITICAL
```

If Trivy reports CRITICALs from the base image, bump the base tag and rebuild. Fixing them by
adding `--ignore-unfixed` without reading the findings is how a known-exploitable dependency
ships to production.

## Trade-off worth knowing

`init: true` plus `tini` is belt-and-braces — either alone handles signals. Both are here
because the compose file and the image are often used independently, and a container that
ignores SIGTERM is a bug you only notice during an incident.
