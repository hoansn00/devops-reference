# 03 — CI/CD with a rollback that works

`.gitlab-ci.yml` and `github-actions/deploy.yml` implement the same pipeline:

```
test → build + scan → push → deploy (manual gate) → smoke test → auto-rollback on failure
```

The deploy and rollback scripts they call live in
[../02-deploy-vps](../02-deploy-vps/) — `deploy.sh` and `rollback.sh`.

## The one decision everything else depends on

```
✗  docker push myapp:latest
       the previous build is overwritten — nothing exists to revert to

✓  docker push myapp:9f3c1ab   +   docker push myapp:latest
       every commit stays deployable, indefinitely
```

Rollback is not a script problem, it is an artifact problem. A pipeline that deploys only
`:latest` cannot roll back no matter what tooling sits on top, because the bytes of the previous
version are gone. Tag by commit SHA and rollback becomes three lines.

`deploy.sh` records the previously healthy tag in `.last_good` on the server, so
`./rollback.sh` with no arguments returns to a version that is known to have passed its own
health check — not merely the one before.

## Other decisions worth copying

| Decision | Reason |
|---|---|
| Cache keyed on the lockfile, not the branch | A stale dependency cache is worse than no cache |
| `interruptible` / `cancel-in-progress` | A new push supersedes the old run instead of racing it |
| Trivy fails the build on CRITICAL | With `--ignore-unfixed`, so unpatchable findings don't block forever |
| Production behind a manual gate | GitLab `when: manual`; GitHub an Environment with required reviewers |
| Dedicated deploy key, not a personal one | Revocable on its own, and restricted in `authorized_keys` |
| `known_hosts` pinned | `StrictHostKeyChecking=no` disables MITM protection entirely |
| `--password-stdin` for registry login | A password in argv is visible in process listings |
| Smoke test after deploy | Deploying without verifying is how a broken release survives the night |

Restrict the deploy key on the server side too:

```
# ~deploy/.ssh/authorized_keys
no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAA... ci@runner
```

## Secrets

Store these as **masked and protected** CI variables (GitLab) or repository/environment secrets
(GitHub). Never in the YAML, and never echoed — wrap any command that touches one in `set +x`.

| Variable | Notes |
|---|---|
| `SSH_PRIVATE_KEY` | File-type variable in GitLab. A dedicated deploy key |
| `SSH_KNOWN_HOSTS` | Output of `ssh-keyscan your-host` |
| `DEPLOY_USER`, `PROD_HOST`, `STAGING_HOST` | |
| `CI_REGISTRY_*` | Provided automatically by GitLab; GitHub uses `GITHUB_TOKEN` |

## The three tests to run before you trust it

Most pipelines are only ever tested in the success case. Run all three:

1. **A clean deploy.** Push, approve, confirm the new version is live.
2. **A deliberately failing test.** Break one assertion and push. The pipeline must stop, and
   production must be **untouched**. If it deploys anyway, your gate does not work.
3. **One rollback.** Run the rollback job. Confirm the previous version is serving and healthy.

Until you have done #2 and #3, you do not know whether the safety mechanisms work — only that
they have never been tried.

## Pipeline speed is a safety feature

An eight-minute pipeline gets bypassed by developers under pressure; a ninety-second one gets
used. Dependency caching is not a convenience — it is what keeps the pipeline in the path of
least resistance.
