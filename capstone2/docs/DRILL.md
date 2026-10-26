# Incident Drill — Robot Shop payment outage

This drill is a controlled, self-run substitute for the instructor-led incident.
It exercises the same path: detect, mitigate, recover, then write a blameless
postmortem. The drill is run against the kind cluster, not Docker Compose.

## Scenario

The `payment` Deployment in namespace `robot-shop` is scaled to zero. This
removes the payment service from the mesh. Requests that need payment fail
while the rest of Robot Shop remains available.

## Timeline (planned)

| Step | Action | Expected result |
| --- | --- | --- |
| T+0 | Record baseline: pods, alerts, dashboard | All 13 pods Ready; no Robot Shop alert firing |
| T+1m | `kubectl -n robot-shop scale deployment/payment --replicas=0` | `payment` pods terminate; requests fail |
| T+2m | Inspect alerts and logs | `RobotShopServiceDown` fires for `payment`; errors visible in Loki |
| T+3m | Capture evidence | Prometheus alert JSON, Grafana dashboard, Loki query |
| T+4m | Mitigate: scale `payment` back to 1 | New pod starts and becomes Ready |
| T+6m | Verify recovery | Alert resolves; error rate returns to baseline |

## Commands

```powershell
# Baseline
kubectl -n robot-shop get pods
kubectl -n robot-shop get deployment payment -o wide

# Inject
kubectl -n robot-shop scale deployment/payment --replicas=0

# Observe
kubectl -n robot-shop get pods -l service=payment
kubectl -n robot-shop get events --sort-by=.lastTimestamp | Select-Object -Last 20

# Mitigate
kubectl -n robot-shop scale deployment/payment --replicas=1
kubectl -n robot-shop rollout status deployment/payment --timeout=180s

# Confirm
kubectl -n robot-shop get pods -l service=payment
```

Prometheus alert state and dashboard screenshots are captured during the
window. Raw API output is stored under `docs/evidence/capstone2/`.

## What this proves

- The alert is wired to a real symptom (`ready replicas == 0`), not only to
  synthetic traffic.
- The runbook is usable without guessing: it names the deployment, the
  dashboard, and the recovery command.
- Recovery is a deliberate, reversible action, not a restart-everything reflex.
- The postmortem can separate trigger (scale to zero), contributing conditions
  (no PodDisruptionBudget / no automatic failover), and prevention.

## Actual result (2026-10-26)

The drill was run on the kind cluster. `RobotShopServiceDown` entered `pending`
at 23:20:53 UTC and was observed `firing` at 23:23:46 UTC. `payment` was scaled
back to one replica at 23:25:12 UTC; the new pod was Ready 11 seconds later and
the alert cleared by 23:25:58 UTC.

- Payment outage: 4m52s
- Trigger to observed alert: 3m26s
- Mitigation to Ready: 11s
- Data loss: none

The full timeline, root cause, action items, and evidence links are in
[`POSTMORTEM.md`](POSTMORTEM.md). Raw evidence is in
`docs/evidence/capstone2/`.
