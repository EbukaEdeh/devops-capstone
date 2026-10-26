# Evidence Index

This page collects the proof captured during the capstone run. Everything here
was produced locally on 2026-10-26 (UTC). Items that require an external account
or paid cloud resource are listed separately at the end.

## Capstone 1 — Ship it

| Requirement | Evidence | What it proves |
| --- | --- | --- |
| Working local app | [vote page](evidence/screenshots/vote-page.png), [result page](evidence/screenshots/result-page.png) | The ballot is accepted and the live result board shows non-zero totals (283 ballots at capture time) |
| Local stack health | [docker compose ps](evidence/docker-compose-ps.txt), [final health](evidence/final-health.txt) | Eleven services running, all app health checks green, 283 rows / 283 unique IDs, queue 0, observability endpoints ready |
| Kubernetes deploy | [kind nodes](evidence/kind-nodes.txt), [kind pods](evidence/kind-pods-before-rollback.txt), [services](evidence/kind-services.txt) | A real kind cluster with all app, Redis and PostgreSQL pods running |
| Helm install | [helm history before rollback](evidence/helm-history-before-rollback.txt) | Release `voting-app` installed in namespace `voting`, revision 1 |
| Bad release and rollback | [rollback log](evidence/rollback-demo.log), [helm history after rollback](evidence/helm-history-after-rollback.txt), [pods after rollback](evidence/kind-pods-after-rollback.txt), [result page after rollback](evidence/screenshots/kind-after-rollback.png) | Revision 2 failed on a broken image tag; revision 3 rolled back to revision 1; the app still serves 20 votes |

The kind UI screenshots are from the NodePorts mapped to `localhost:8080` and
`localhost:8081`: [kind vote page](evidence/screenshots/kind-vote-page.png),
[kind result page](evidence/screenshots/kind-result-page.png).

## Capstone 2 — Keep it running

| Requirement | Evidence | What it proves |
| --- | --- | --- |
| Dashboard as code | [Grafana dashboard](evidence/screenshots/grafana-dashboard.png) | Request rate, 5xx, p95 latency, votes by choice, queue depth, queue age, scrape targets and request volume with live data |
| Freshness alert | [Grafana during the outage](evidence/screenshots/grafana-freshness-alert.png) | Queue at 80, worker down, oldest vote at 1.55 minutes, alert threshold crossed |
| Alert firing | [Prometheus alert page](evidence/screenshots/prometheus-alert-firing.png), [alerts JSON](evidence/prometheus-alerts-firing.json) | `VotingFreshnessAtRisk` is `firing`; `VotingQueueBacklog` is pending |
| Recovery | [Grafana after recovery](evidence/screenshots/grafana-recovered.png), [recovered alerts JSON](evidence/prometheus-alerts-recovered.json) | Worker back at 1 replica, queue 0, oldest vote 0s, no active alerts |
| Distributed trace | [Jaeger trace](evidence/screenshots/jaeger-vote-trace.png) | One `POST /vote` request with its child `RPUSH` span, service `vote`, 2.13 ms |
| Structured logs | [Loki query](evidence/screenshots/loki-error-query.png), [query JSON](evidence/loki-error-query.json) | LogQL `{service="vote"} \| json \| level="error"` returns the real Redis-outage error with `trace_id` and `span_id` |
| Metrics snapshot | [Prometheus query snapshot](evidence/prometheus-query-snapshot.json) | Votes cast/processed, queue depth/age, request rate, p95 and scrape health at capture time |
| Incident drill | [drill evidence](evidence/worker-outage-drill.md), [postmortem](postmortems/2026-10-26-worker-outage-drill.md) | 80 votes queued, none lost or duplicated, 64s delay, recovery in 4s |

The local alert rules in `observability/local/rules.yaml` mirror the Helm
`PrometheusRule`. Kubernetes uses the chart rule; the Compose demo uses the
local mirror so the alert can be demonstrated without kube-prometheus-stack.

## Local verification

[`local-ci-checks.txt`](evidence/local-ci-checks.txt) records the commands that
were run:

```text
pytest                          19 passed
helm lint                       0 failed
helm template                   rendered
terraform fmt -check            clean
terraform validate              valid
docker compose config           valid
Grafana dashboard JSON          valid
```

[`secret-scan.txt`](evidence/secret-scan.txt) records the checklist pattern.
Every match is a variable reference or a documentation placeholder; no literal
credential is tracked, and `.env` is ignored.

The submission is committed on `main` and tagged `v1.0.0`; see
[`git-commit.txt`](evidence/git-commit.txt).

## Reproduction

```powershell
# Local app + full observability (Prometheus, Grafana, Jaeger, Loki, Promtail)
powershell -ExecutionPolicy Bypass -File ./scripts/run-local.ps1 -WithObservability

# Incident drill with assertions
powershell -ExecutionPolicy Bypass -File ./scripts/drill-worker-outage.ps1 `
  -Votes 80 -OutageSeconds 60 -EvidencePath docs/evidence/worker-outage-drill.md

# Kind install + rollback
powershell -ExecutionPolicy Bypass -File ./scripts/stop-local.ps1
powershell -ExecutionPolicy Bypass -File ./scripts/create-kind-cluster.ps1
powershell -ExecutionPolicy Bypass -File ./scripts/demo-rollback.ps1
```

## Still requires an external account or paid resource

| Item | Why it is not captured here |
| --- | --- |
| Slack message from Alertmanager | No real Slack incoming-webhook URL was provided. The firing alert and its payload are captured; delivery needs `SLACK_WEBHOOK_URL` |
| GitHub Actions run with SHA-tagged images | The workflow is committed and locally validated, but pushing and running it needs a GitHub repository and credentials |
| EKS `terraform apply` / `terraform destroy` | EKS costs money and needs AWS credentials. The same chart was deployed and rolled back on kind as the local substitute |
| Forked repository URL | A local Git repository is initialized; creating the fork requires the user's GitHub account |

## Notes

- Evidence screenshots were captured with headless Microsoft Edge against a
  temporary local Grafana instance on port 3001. That instance was removed after
  capture; the authenticated Grafana remains on port 3000.
- The kind cluster and local Compose stack are not meant to run at the same
  time because both bind ports 8080/8081.
