# Robot Shop SLO

## Service and ownership

- **Service:** Robot Shop critical path: `web`, `catalogue`, `cart`, `payment`.
- **Owner:** Capstone 2 team (Ebuka Edeh).
- **Environment:** kind cluster `voting-capstone`, namespace `robot-shop`.
- **Measurement source:** Istio/Envoy metrics scraped by the kube-prometheus-stack
  Prometheus in namespace `observability`.

## Service level indicators

| SLI | Definition | Query |
| --- | --- | --- |
| Availability | Proportion of server-side requests that do **not** return 5xx | `sum(rate(istio_requests_total{reporter="destination",destination_service_namespace="robot-shop",destination_service_name=~"web|catalogue|cart|payment",response_code!~"5.."}[5m])) / sum(rate(istio_requests_total{...}[5m]))` |
| Latency | p95 request duration | `histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{...}[5m])) by (le))` |

The dashboard is **Robot Shop - Service Health** (UID `robot-shop-slo`). It shows
request rate, 5xx ratio, p95 latency, errors by service, status codes, deployment
readiness and recent Loki error logs.

## Service level objectives

| SLO | Target | Window | Error budget |
| --- | --- | --- | --- |
| Availability | **99.5%** of requests succeed | 30 days rolling | **0.5%** = 216 minutes |
| Latency (secondary) | **95%** of requests complete in < 500 ms | 30 days rolling | 5% of requests may exceed 500 ms |

Availability is the primary SLO. Latency is tracked as a secondary objective
because the `payment` service calls an external payment endpoint and is the most
likely source of tail latency.

## Error budget

For a 30-day window:

```
allowed bad requests = 0.5% of total requests
budget in time        = 0.5% x 30 days x 24 hours x 60 minutes = 216 minutes
```

The error budget is consumed by 5xx responses, not by 4xx client errors. A
request that never reaches a service because the pod is down is captured by the
`RobotShopServiceDown` alert and by the availability calculation when traffic
is attempted.

## Alerting

Fast-burn alerts implemented in `capstone2/observability/robot-shop-alerts.yaml`:

| Alert | Condition | For | Severity |
| --- | --- | --- | --- |
| `RobotShopHighErrorRate` | 5xx ratio > 5% across the four services | 5m | critical |
| `RobotShopHighLatency` | aggregate p95 > 500 ms | 5m | warning |
| `RobotShopServiceDown` | a graded deployment has 0 ready replicas | 2m | critical |
| `RobotShopPodRestarting` | a container restarted in the last 15m | 5m | warning |

The 5% fast-burn threshold is deliberately tighter than the 0.5% SLO so the team
is paged before a full month's budget is consumed in a short incident. A longer
window burn-rate alert can be added once the team has a month of baseline data.

## Exclusions and known risks

- 4xx responses caused by the load generator or a client are not SLO failures.
- Planned maintenance must be announced and excluded from the window.
- `payment` depends on an external endpoint. Synthetic load currently exercises
  the sandbox path; a real payment-provider outage will consume latency budget.
- The kind environment is a single node. A node-level failure is a full outage
  and is treated as an incident, not as normal error budget.

## Review cadence

- Review the dashboard weekly during the capstone.
- Review the SLO and error-budget policy monthly.
- Recalculate the budget after any month where the SLO is missed.
