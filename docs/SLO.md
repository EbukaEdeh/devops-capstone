# Service Level Objectives and Error-Budget Policy

**Service:** Voting App (`vote`, `result`, `worker`)
**Owner:** Capstone team
**Review cadence:** monthly, or after any Sev-1/Sev-2 incident
**Window:** rolling 30 days

## 1. Service level indicators

| SLI | Definition | PromQL |
| --- | --- | --- |
| Availability | Non-5xx HTTP responses / all HTTP responses from `vote` and `result` | `1 - sum(rate(http_requests_total{service=~"vote|result",status=~"5.."}[5m])) / clamp_min(sum(rate(http_requests_total{service=~"vote|result"}[5m])), 0.001)` |
| Latency | p95 server-side request duration for `vote` and `result` | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{service=~"vote|result"}[5m])))` |
| Vote freshness | Share of accepted votes written to PostgreSQL within 60 seconds | `sum(rate(votes_processed_total[5m])) / clamp_min(sum(rate(votes_cast_total[5m])), 0.001)` (approximation; queue age is the leading indicator) |
| Queue depth | Votes waiting in Redis | `max(vote_queue_depth{service="vote"})` |
| Queue age | Age of the oldest vote waiting in Redis | `max(vote_queue_oldest_age_seconds{service="vote"})` |

The first two are the user-facing SLOs. Freshness is a supporting indicator. A sustained queue above 50 for five minutes sends a warning; `VotingFreshnessAtRisk` fires as soon as a scrape sees a vote older than 60 seconds, because that is the point where the freshness objective starts to burn. Queue depth alone cannot tell you whether users are waiting; queue age can.

## 2. Objectives

| SLO | Target | Error budget (30 days) |
| --- | --- | --- |
| Availability | **99.5%** of requests succeed | **0.5%** = **3h 36m** |
| Latency | **95%** of requests complete in < **300 ms** | 5% of requests may be slower |
| Freshness | 99% of accepted votes written within 60s | 1% of votes may be delayed |

These are deliberately achievable for a learning service. Do not copy 99.99% into a capstone: it would exhaust the budget during a single deployment.

## 3. Error-budget policy

The budget is **0.5% of monthly requests** for availability. Latency has its own 5% allowance.

| Budget consumed | State | Required action |
| --- | --- | --- |
| 0–50% | Healthy | Ship normally; review weekly trends |
| 50–75% | Caution | Increase deploy verification; no risky migrations on Fridays |
| 75–100% | Critical | Only reliability fixes and rollbacks; freeze feature releases |
| 100% | Exhausted | Feature freeze until the window resets or the SLO is formally revised; incident review required |

**Exceptions:** a security fix or a change that directly restores the SLO may ship during a freeze with owner approval. Record the exception in the incident/postmortem.

**Budget spend examples**

- 5 minutes of complete outage = 0.0116% of a 30-day window (5 / 43,200). About 43 complete-outage minutes consume 1% of the window.
- A 10% error rate for 30 minutes = 0.104%. That is already 21% of the monthly budget.

## 4. Alerting and burn rate

Fast burn (page immediately):

```promql
(
  sum(rate(http_requests_total{service=~"vote|result",status=~"5.."}[1h]))
  /
  clamp_min(sum(rate(http_requests_total{service=~"vote|result"}[1h])), 0.001)
) > (14.4 * 0.005)
```

Slow burn (ticket, not page):

```promql
(
  sum(rate(http_requests_total{service=~"vote|result",status=~"5.."}[6h]))
  /
  clamp_min(sum(rate(http_requests_total{service=~"vote|result"}[6h])), 0.001)
) > (6 * 0.005)
```

The implemented `PrometheusRule` in the Helm chart fires at a fixed 5% 5xx rate for five minutes, plus latency, queue depth, queue age, worker and pod-down alerts. Burn-rate alerts are the documented stretch goal.

## 5. Measurement notes

- Metrics are scraped every 30 seconds from each pod. Aggregate across replicas with `sum by (le)` or `sum(rate(...))`.
- Server-side latency excludes browser rendering and network time.
- `/metrics`, `/healthz` and `/readyz` are excluded from HTTP request metrics.
- A 503 caused by a deliberate dependency outage still counts against availability: the user saw an error.
- Planned maintenance is not excluded in this exercise because the service has no maintenance windows.

## 6. Error-budget review questions

1. Which SLO burned, and by how much?
2. Was the burn caused by a change, a dependency, or traffic?
3. How long did detection take? How long to mitigate?
4. Did alerts link to a useful runbook?
5. What action prevents the same class of failure?
6. Do we need to revise the target rather than the system?
