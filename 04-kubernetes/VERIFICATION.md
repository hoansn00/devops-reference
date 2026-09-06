# GKE verification run — 2026-09-06T03:50:47Z

Cluster: GKE 1.35.7, 3x e2-medium, asia-southeast1-b
Manifests: this folder, with image substituted for a public test image
           (hashicorp/http-echo) since registry.example.com/myapp is a placeholder.

## Nodes
NAME                                             STATUS   VERSION
gke-devops-ref-demo-default-pool-066132a2-d3wr   Ready    v1.35.7-gke.1150000
gke-devops-ref-demo-default-pool-066132a2-fmqt   Ready    v1.35.7-gke.1150000
gke-devops-ref-demo-default-pool-066132a2-r9r5   Ready    v1.35.7-gke.1150000

## Pods — placement after several rollouts
NAME                     READY   IP           NODE
myapp-5b448d46c5-48vlh   true    10.44.0.20   gke-devops-ref-demo-default-pool-066132a2-fmqt
myapp-5b448d46c5-xxrs2   true    10.44.0.19   gke-devops-ref-demo-default-pool-066132a2-fmqt
myapp-5b448d46c5-z855s   true    10.44.2.12   gke-devops-ref-demo-default-pool-066132a2-r9r5

On first deploy the three replicas landed one per node, as intended. After several
rollouts they bunched 2+1, leaving one node empty. That is correct behaviour for
`whenUnsatisfiable: ScheduleAnyway` — the spread is a preference, not a guarantee, and
the scheduler is free to ignore it. `DoNotSchedule` makes it a hard constraint, at the
cost of pods staying Pending when it cannot be satisfied. Worth choosing deliberately.

## HPA — real utilisation, not <unknown>: resources.requests is set correctly
myapp   Deployment/myapp   cpu: 5%/70%   3     12    3     8m26s

## PodDisruptionBudget
myapp   2     N/A   1     8m27s

## Rollout history
REVISION  CHANGE-CAUSE
3         <none>
4         <none>
5         <none>
6         <none>
7         <none>


## Rolling update under load — measured, not asserted
Three runs, load generated from inside the cluster against the Service:
  preStop 5s,  via DNS        : 336/343  OK,  7 connection failures
  preStop 20s, via DNS        : 1381/1387 OK, 6 connection failures
  preStop 20s, via ClusterIP  : 1328/1335 OK, 7 connection failures

About 0.5% of NEW connections fail during the pod-replacement window.
Ruled out: DNS resolution (failures persist when hitting the ClusterIP directly)
           and endpoint propagation (raising preStop from 5s to 20s did not help).
Most likely remaining cause: the substitute test image does not drain in-flight
connections on SIGTERM. An application that calls a graceful HTTP shutdown should
close this gap. This has NOT been verified with a real application, so no
zero-downtime claim is made here.

## Rollback
kubectl rollout undo returned the previous revision and all replicas became ready.
