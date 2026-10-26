# Postmortem - Robot Shop payment outage drill

**Date:** 2026-10-26
**Owner:** Capstone operator
**Status:** Final
**Severity:** SEV-2 (one graded service unavailable, no data loss)
**Environment:** kind cluster `voting-capstone`, namespace `robot-shop`

## Summary

The `payment` Deployment was deliberately scaled to zero to simulate loss of
the payment service. `payment` was the only replica, so every request that
needed payment failed until the Deployment was scaled back to one replica.
The failure was detected by the `RobotShopServiceDown` alert, mitigated with a
single scale command, and recovered in under a minute after mitigation.

This was a self-run substitute for the instructor-led incident because the
instructor-led break was not available in this environment. It exercises the
same operational path: detect, mitigate, diagnose, recover, and write a
blameless postmortem.

## Impact

- **Customer impact:** checkout/payment requests failed for **4m52s**
  (23:20:20 to 23:25:12 UTC). Browsing, catalogue, cart and other services
  remained available.
- **Service impact:** ready deployments dropped from 12 to 11; `payment`
  reported 0 ready replicas. The load generator continued to drive traffic, so
  failed payment attempts were visible in the dashboard error panels.
- **Data impact:** none. No payment records are written by this demo flow; the
  failure was availability-only.
- **Error budget:** the Capstone 2 availability SLO is 99.5% over 30 days
  (216 minutes of budget). This incident consumed about **4.9 minutes**, or
  **2.3%** of the monthly budget for the payment path.
- **Alert noise:** `RobotShopHighErrorRate` and `RobotShopHighLatency` were
  already firing before the drill because the load generator and the existing
  payment/RabbitMQ `StreamLostError` condition pushed the baseline above the
  thresholds. They are not counted as drill-specific detections. Both went
  inactive when payment traffic stopped.

## Detection

- `RobotShopServiceDown` entered `pending` at **23:20:53 UTC** and was observed
  `firing` at **23:23:46 UTC**. The rule uses `for: 2m`; the extra delay came
  from Prometheus evaluation/rule-group timing and the time taken to confirm
  the alert in the UI.
- The alert is driven by `kube_deployment_status_replicas_ready{deployment="payment"} == 0`,
  so it tracks the actual symptom (no ready payment replicas), not a synthetic
  probe.
- The Grafana dashboard independently showed `payment` with 0 ready replicas
  and 11 total ready deployments.
- Loki contained the payment application error:
  `ERROR in payment: StreamLostError: ("Stream connection lost: ConnectionResetError(104, 'Connection reset by peer')",)`.
  The log stream carried `service="payment"` and `level="error"` labels.

## Timeline (UTC)

| Time | Event |
| --- | --- |
| 23:12:23 | `RobotShopHighErrorRate` and `RobotShopHighLatency` already firing from the loaded baseline |
| 23:20:19 | Baseline captured: `payment` 1/1; `RobotShopServiceDown` inactive |
| 23:20:20 | **T0** - `kubectl -n robot-shop scale deployment/payment --replicas=0` |
| 23:20:53 | `RobotShopServiceDown` enters `pending` (`activeAt`) |
| 23:23:46 | Alert observed `firing`; dashboard shows `payment` 0 ready, 11 deployments ready |
| 23:23:52 | Firing evidence captured: Prometheus alert JSON and screenshots |
| 23:25:12 | **Mitigation** - `kubectl -n robot-shop scale deployment/payment --replicas=1` |
| 23:25:23 | New `payment` pod Ready (2/2) |
| 23:25:58 | Alert cleared; no `RobotShop*` alerts active |

Local time (America/Chicago, CDT) is UTC-5; the same events are 18:20:19 to
18:25:58 local.

## Root cause

**Direct trigger:** the `payment` Deployment was intentionally scaled to zero
for the drill. This removed the only payment pod and left the Service with no
ready endpoints.

**Why it caused a full outage:** `payment` runs with one replica, has no
PodDisruptionBudget, and has no automatic failover. Any action that removes that
single pod - a scale operation, a node drain, an eviction, or a crash - removes
all payment capacity. The application itself did not crash and the node stayed
healthy.

**Contributing conditions:**

- No PodDisruptionBudget or second replica for a critical path.
- The alert's `for: 2m` window plus evaluation timing produced a 3m26s gap
  between trigger and observed firing. That is acceptable for the 30-day SLO
  but longer than ideal for a payment path.
- Slack delivery was not configured because no real webhook URL was available.
  The alert was visible in Prometheus and Grafana, but no chat notification was
  sent.
- The baseline already had payment `StreamLostError` messages and elevated
  error/latency from the load generator. This made the baseline noisy and means
  the drill must be interpreted from `RobotShopServiceDown`, not from the
  pre-existing error/latency alerts.
- The dashboard's Loki log panel showed "No data" during the drill even though
  Loki returned the payment error through its API. This is a dashboard query or
  datasource issue, not a logging-pipeline outage; the raw Loki query is kept as
  evidence.

## Mitigation and recovery

1. Confirmed the symptom in Prometheus and on the dashboard.
2. Ran `kubectl -n robot-shop scale deployment/payment --replicas=1`.
3. Waited for `kubectl rollout status deployment/payment`; the new pod reached
   2/2 Ready in 11 seconds.
4. Confirmed `RobotShopServiceDown` cleared; the dashboard returned to 12 ready
   deployments and payment traffic resumed.

No restart of the whole cluster, no volume changes, and no data restore were
needed. The recovery action was reversible and matched the runbook.

## What went well

- The alert was tied to a real service symptom, not just CPU or pod restarts.
- The runbook named the exact deployment, dashboard, and recovery command.
- Grafana made the missing replica obvious without reading logs first.
- Loki had the payment error with `service` and `level` labels for diagnosis.
- Recovery was fast and did not require a full redeploy.

## What went poorly

- Detection took 3m26s from trigger to observed firing.
- There was no Slack notification; an operator watching only chat would have
  missed the incident.
- A single replica with no PodDisruptionBudget turned a routine scale action
  into a full payment outage.
- The dashboard's Loki panel did not render the logs that the Loki API returned.
- The baseline was noisy: error and latency alerts were already firing before
  the drill, which makes the incident harder to explain during a demo.

## Action items

| Action | Owner | Priority | Status |
| --- | --- | --- | --- |
| Run `payment` with at least 2 replicas and add a PodDisruptionBudget | Platform | High | Planned |
| Add an HPA or explicit capacity check for graded services | Platform | Medium | Planned |
| Reduce `RobotShopServiceDown` `for` to 1m for critical single-replica paths, or add a faster synthetic check | Observability | High | Planned |
| Add an alert for critical Deployments whose desired replicas equal 1 | Observability | Medium | Planned |
| Investigate and fix the payment/RabbitMQ `StreamLostError` baseline | Application | Medium | Open |
| Fix the dashboard Loki panel query/datasource so it shows the logs the API returns | Observability | Medium | Planned |
| Configure a real Slack incoming webhook and verify one delivered alert | Observability | High | Blocked: no webhook URL |
| Re-run the drill with the instructor-provided failure when available | Course | Medium | External dependency |

## Lessons

1. **Alert on the symptom users feel.** `ready replicas == 0` caught the outage
   even though the pod had not crashed and the node was healthy.
2. **A single replica is a reliability decision.** Without a PDB or a second
   replica, any eviction or scale action is a full outage for that service.
3. **A `for` window is part of the detection budget.** A 2-minute window plus
   evaluation delay is not the same as a 2-minute detection time.
4. **Keep the drill signal separate from baseline noise.** Pre-existing error
   and latency alerts made the story harder to read; the service-down alert was
   the clean signal.
5. **Test the dashboard, not only the data source.** Loki had the log, but the
   panel did not show it. Demo paths need the same verification as APIs.

## Evidence

- `docs/evidence/capstone2/drill-timestamps.txt` - full timeline.
- `docs/evidence/capstone2/robot-shop-alert-firing.json` - Prometheus alert
  payload with labels, annotations, state, `activeAt`, and value.
- `docs/evidence/capstone2/robot-shop-alerts-recovered.json` - cleared state.
- `docs/evidence/capstone2/robot-shop-prometheus-alerts.png` - Prometheus
  `robot-shop.slo` group with `RobotShopServiceDown` firing.
- `docs/evidence/capstone2/robot-shop-dashboard-firing.png` - dashboard during
  the outage: payment 0 ready, 11 ready deployments.
- `docs/evidence/capstone2/robot-shop-dashboard-recovered.png` - payment 1
  ready, 12 ready deployments.
- `docs/evidence/capstone2/robot-shop-pods-during-drill.txt` and
  `payment-deployment-scaled-zero.yaml` - Kubernetes state at capture time.
- `docs/evidence/capstone2/loki-payment-error.json` - Loki query result for the
  payment error with `service` and `level` labels.

## Blameless statement

This was a controlled drill, not a performance review. The outage was caused by
a deliberate scale-to-zero action against a single-replica service with no
PodDisruptionBudget. The operator followed the documented mitigation and
recovered quickly. The action items above are system improvements, not
individual blame.
