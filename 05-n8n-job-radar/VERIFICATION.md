# n8n verification run — 2026-09-06

Host: GCP e2-standard-2 (2 vCPU / 8 GB), asia-southeast1-b, Ubuntu 24.04 Minimal, 4 GB swap
Stack: n8n 2.37.10, postgres:17-alpine, caddy:2-alpine, compose in /opt/n8n
URL:   https://<ip>.sslip.io — Let's Encrypt cert issued on first request, HTTP → 308 → HTTPS

## Stack
- `docker compose ps`: postgres healthy, n8n healthy, caddy up. Only 80/443 published.
- `/healthz` from outside: HTTP 200. HSTS and nosniff headers present.
- Reboot test: VM rebooted, all three containers back healthy, `/healthz` 200 from outside
  in ~80 s without manual action.

## Backup and restore — exercised, not just scheduled
- `backup.sh` via systemd timer (Ubuntu Minimal has no cron): pg_dump 61 KB gz + data
  volume tar. Timer listed with next run at 03:00 UTC.
- Postgres 16 → 17 done as dump → fresh `pg17_data` volume → restore. After restore:
  131 tables, 1 workflow, 4 executions, workflow still active. Old volume kept for rollback.
- n8n's "Postgres 16 is outside the supported range" warning gone after the upgrade.

## Workflow executions (production mode, schedule trigger)
| # | What | Read RSS | Kept by filter | After dedupe | Duration |
|---|---|---|---|---|---|
| 1 | first run, naive `includes()` scoring | 54 | 54 | 14 | 2.4 s |
| 2 | word-boundary scoring, `source` fixed | 54 | 10 (44 discarded) | **0** — all 10 seen in #1 | 1.8 s |
| 3 | Remove Duplicates set to *clear history* | — | — | history cleared | 1.0 s |
| 4 | normal run (the screenshot) | 54 | 10 | 10 → 10 alerts formatted | 3.1 s |
| 5 | first unattended 15-min tick | 54 | — | — | 11.1 s |

Feed breakdown in #4: Freelancer.com 20, We Work Remotely 14, HN Jobs 20. All 10 matches
came from WWR's DevOps category; the 20 newest Freelancer projects had no DevOps keyword in
that window, which is the expected shape of an unfiltered firehose.

Top scores in #4: "DevOps & Security Engineer" 15 (13 keywords), "Senior DevOps Engineer" 8,
"AEM Developer" 5 (devops, ci/cd, jenkins, deployment, automation — a real hit, not noise).

Execution #2 is the dedupe proof: same 10 posts, zero alerts.

## Second run — 2026-09-06, later the same day

Telegram was wired up and the filter was tightened. Both changes came out of things that
only showed up once the thing ran for real.

### The Telegram node succeeded for two hours without sending anything

With the bot token and chat ID in place, every execution reported success and the alert node
showed as executed. Nothing arrived in Telegram. No error, no log line, nothing in the n8n
container logs.

The tell was the timing: `executionTime: 1ms`, and the node's output was byte-for-byte its
own input rather than a Telegram API response. A real `sendMessage` takes a few hundred
milliseconds and returns `{ok: true, result: {message_id, ...}}`.

Cause: the workflow was created through the public API, and the Telegram node was written
without `resource` and `operation`. The editor fills those defaults in when you drag a node
onto the canvas; the API does not. The node ran, matched no operation, and passed its input
through silently.

Isolated it with a throwaway webhook → Telegram workflow using the same credential:

| | before | after adding `resource: message` + `operation: sendMessage` |
|---|---|---|
| executionTime | 1 ms | 720 ms |
| output | input, unchanged | `{ok: true, result: {message_id: 4, ...}}` |
| message delivered | no | yes |

Worth remembering for anything built through the n8n API: set resource and operation
explicitly. A node that silently does nothing while reporting success is the worst failure
mode to have in a pipeline you are not watching.

### The filter was letting through work nobody should bid on

The first job the radar would have sent was an Android ad-fraud scheme — automating a
thousand video ad views a day to farm the payout — with a ₹100–400 budget. It qualified
because the threshold was `score >= 1` and the keyword list contained generic words like
`automation`, `deployment` and `infrastructure`. One incidental hit anywhere in the body was
enough.

Rewritten as: strong terms (kubernetes, terraform, argocd, docker, nginx, sysadmin, …) worth
3 points, weak terms 1, title hits doubled, **at least one strong term required**, threshold
raised to 4, an explicit negative list (ad view, click bot, bot farm, followers, captcha,
airdrop, mining) that drops an item outright, and a budget floor using the `budget` field the
code already parsed but never used — with a rough FX table so a ₹400 project is compared
against the same floor as a $400 one.

Dry-run before deploying:

| Post | Result |
|---|---|
| Automated Android Ad Viewer, ₹100–400 | dropped — negative list |
| Deploy Node.js app on AWS, $20 | dropped — under the budget floor |
| "Need automation for my business", $200 | dropped — no strong term |
| Linux sysadmin, remove Plesk, $20–50/hr | kept, score 29 |
| Kubernetes + ArgoCD + Terraform, $900–1800 | kept, score 26 |

First live run afterwards: 54 posts read, **7 kept** instead of the 54 that used to pass the
old `score >= 1` gate.

## Not verified — no claim made
- Behaviour over a long window. The tightened filter has one live run behind it, not a week.
- Upwork as a source. Its RSS endpoint is gone (HTTP 410) and the job search sits behind a
  Cloudflare challenge that blocks both plain fetches and an automated browser. Not bypassed —
  Upwork's own saved-search alerts are the supported route.
- Behaviour under a feed outage. `continueRegularOutput` is set on the RSS node but no feed
  failed during these runs.
- An end-to-end alert. Telegram delivery is proven and the filter is proven, but the two have
  not yet coincided: since the filter was tightened every kept post had already been seen on an
  earlier run, so no new alert has fired yet.
