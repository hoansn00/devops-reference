# 04 — Kubernetes manifests for a real service

A small but complete deployment: rolling updates that drop no requests, correct probes,
disruption budget, autoscaling, and a default-deny network policy. Plain YAML rather than Helm
so each decision is visible.

## Apply

```bash
kubectl create secret generic myapp-secrets --from-env-file=.env
kubectl create configmap myapp-config --from-literal=NODE_ENV=production
kubectl apply -f .
kubectl rollout status deploy/myapp
```

## The decisions

| Setting | Why |
|---|---|
| Image tagged by commit SHA | `:latest` makes `kubectl rollout undo` meaningless — the tag resolves to whatever was pushed last |
| `maxUnavailable: 0` | Never drop below `replicas` during a rollout |
| `terminationGracePeriodSeconds: 45` | Must exceed your longest request, or a rollout returns 502s |
| `preStop: sleep 5` | Endpoint removal has to propagate before the process starts exiting |
| Three separate probes | Different jobs — see below |
| No CPU limit, memory limit set | CPU limits cause throttling that presents as a latency bug; a memory leak must not take the node |
| `topologySpreadConstraints` | Otherwise all replicas can land on one node and one node failure is a full outage |
| `PodDisruptionBudget` | Without it, draining a node for a routine upgrade can evict every replica at once |
| `readOnlyRootFilesystem` + dropped caps | Container escape becomes materially harder |
| Default-deny `NetworkPolicy` | Otherwise one compromised pod can reach every database in the cluster |

## Probes: three names, three jobs

Conflating these is the most common Kubernetes misconfiguration.

- **startupProbe** — allows a slow boot. Without it, a liveness probe kills a container that is
  still starting, forever, and the pod never becomes ready.
- **readinessProbe** — removes the pod from Service endpoints while it cannot serve. Does not
  restart anything.
- **livenessProbe** — restarts a genuinely wedged container. Keep it *lenient*. An aggressive
  liveness probe pointed at an endpoint that touches the database turns a slow database into a
  cluster-wide restart storm.

A common mistake is pointing liveness at a `/health` endpoint that checks dependencies. Then a
database blip restarts every pod, which makes the outage worse rather than better. Liveness
should answer "is this process wedged"; readiness answers "can it serve traffic right now".

## Autoscaling caveat

The HPA scales on `resources.requests`. Omit the requests block and CPU-based autoscaling is
silently inert — it reports `<unknown>/70%` and never scales. `metrics-server` must be
installed.

`minReplicas: 3` is deliberately above the PDB's `minAvailable: 2`, so a scale-down cannot
collide with a node drain and block it.

## Verify

```bash
kubectl rollout status deploy/myapp
kubectl get pods -o wide                  # confirm they are on different nodes
kubectl get hpa myapp                     # must show a real percentage, not <unknown>
kubectl describe pdb myapp

# rolling update with no dropped requests — run a load generator against the
# Ingress, then trigger a rollout and watch for non-200s
kubectl set image deploy/myapp app=registry.example.com/myapp:<new-sha>
kubectl rollout status deploy/myapp

kubectl rollout undo deploy/myapp         # and confirm undo works before you need it
```

## When not to use this

A single app on one VPS does not need Kubernetes. Three replicas of a stateless service across
nodes with an ingress controller and cert-manager is a sensible floor for it; below that,
[02-deploy-vps](../02-deploy-vps/) is less to operate, cheaper, and easier to hand over.
Choosing the smaller tool is a real engineering decision, not a lack of ambition.
