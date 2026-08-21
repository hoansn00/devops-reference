# DevOps reference setups

Working configurations I use on real deployments — Docker, VPS provisioning, CI/CD with
rollback, and Kubernetes. Each folder runs on its own and explains **why** each decision was
made, not just what to type.

I am a Technical Architect (ex-DevOps) working with Linux, Docker, Kubernetes, GitLab CI,
Jenkins, ArgoCD and Terraform in production.

| Folder | What it demonstrates |
|---|---|
| [01-dockerize-node](01-dockerize-node/) | Multi-stage build, non-root user, healthcheck, correct signal handling, log rotation |
| [02-deploy-vps](02-deploy-vps/) | Server hardening, Nginx reverse proxy, Let's Encrypt, backups with a **tested restore** |
| [03-cicd-rollback](03-cicd-rollback/) | Immutable image tags and a rollback that actually works — GitLab CI and GitHub Actions |
| [04-kubernetes](04-kubernetes/) | Probes, resource limits, PDB, HPA, rolling update with zero dropped requests |

## The four things most setups get wrong

**1. `:latest` makes rollback impossible.** Overwriting one tag destroys the previous artifact,
so when a deploy breaks there is nothing to return to. Every image here is tagged by commit SHA.
→ [03-cicd-rollback](03-cicd-rollback/)

**2. Nothing survives a reboot.** Services started by hand look identical to services configured
to start — until the host restarts. Rebooting is the cheapest verification that exists, and it
catches most "it broke a month later" incidents.
→ [02-deploy-vps](02-deploy-vps/)

**3. Unbounded logs fill the disk.** A container logging a few lines per second fills a small
VPS in weeks, and the outage looks unrelated to logging.
→ [01-dockerize-node](01-dockerize-node/)

**4. An untested backup is not a backup.** Every backup script here has a matching restore
script, and the restore is meant to be run before you need it.
→ [02-deploy-vps/restore.sh](02-deploy-vps/restore.sh)

## Using these

The configs are deliberately generic — replace the app name, domain and registry path. Read the
README in each folder first; several files have deliberate trade-offs noted inline.

MIT licensed. If something here is wrong or could be better, open an issue.
