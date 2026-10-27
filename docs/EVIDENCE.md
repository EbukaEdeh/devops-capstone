# Evidence Index

This page collects the proof captured during the capstone run. Everything here
was produced locally on 2026-10-26 (UTC). Items that require an external account
or paid cloud resource are listed separately at the end.

## Grader quick path

Both capstones are in this one repository: Capstone 1 at the repository root,
Capstone 2 under [`../capstone2`](../capstone2). The implementation is tagged
`v1.1.0`. Start with the row that matches the requirement.

| What to check | Open this |
| --- | --- |
| Capstone 1 works and accepts votes | [vote page](evidence/screenshots/vote-page.png), [result page](evidence/screenshots/result-page.png), [final health](evidence/final-health.txt) |
| Containers are safe | `services/*/Dockerfile`, [`compose.yaml`](../compose.yaml), [`.dockerignore`](../.dockerignore) |
| EKS infrastructure as code | [`infra/terraform/`](../infra/terraform/) - validates; apply needs AWS credentials |
| CI/CD pipeline | [`.github/workflows/ci-cd.yml`](../.github/workflows/ci-cd.yml) - linted locally; a live run needs a GitHub remote |
| Helm deploy and bad-release rollback | [rollback log](evidence/rollback-demo.log), [Helm history](evidence/helm-history-after-rollback.txt), [pods after rollback](evidence/kind-pods-after-rollback.txt) |
| Robot Shop runs on Kubernetes | [UI](evidence/capstone2/robot-shop-ui.png), [healthy pods](evidence/capstone2/robot-shop-pods-healthy.txt), [Helm releases](evidence/capstone2/helm-releases.txt) |
| Metrics and dashboard | [dashboard JSON](../capstone2/observability/dashboards/robot-shop.json), [live dashboard](evidence/capstone2/robot-shop-dashboard-recovered.png) |
| Logs by service and level | [Loki payment error](evidence/capstone2/loki-payment-error.json) |
| Distributed trace | [Jaeger trace](evidence/capstone2/jaeger-web-trace.png), [trace JSON](evidence/capstone2/jaeger-web-trace.json) |
| Firing alert and incident drill | [alert JSON](evidence/capstone2/robot-shop-alert-firing.json), [drill timestamps](evidence/capstone2/drill-timestamps.txt), [postmortem](../capstone2/docs/POSTMORTEM.md) |
| SLO and error budget | [`SLO.md`](../capstone2/docs/SLO.md), [`ERROR_BUDGET_POLICY.md`](../capstone2/docs/ERROR_BUDGET_POLICY.md) |
| Known gaps | [Still requires an external account or paid resource](#still-requires-an-external-account-or-paid-resource) |

For the same material as a single submission narrative, use
[`GOOGLE_DOC_SUBMISSION.md`](GOOGLE_DOC_SUBMISSION.md). It has one
`REPLACE_REPO_URL` placeholder for the public repository URL.

## Capstone 1 - Ship it

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

## Capstone 2 - Keep it running (Robot Shop on kind)

Robot Shop is a separate application from the Voting App. It is deployed from
the vendored chart in [`../capstone2/robot-shop`](../capstone2/robot-shop) on the
same kind cluster, with the observability stack in namespace `observability`.

| Requirement | Evidence | What it proves |
| --- | --- | --- |
| Working system | [Robot Shop UI](evidence/capstone2/robot-shop-ui.png), [healthy pods](evidence/capstone2/robot-shop-pods-healthy.txt), [Helm releases](evidence/capstone2/helm-releases.txt) | Stan's Robot Shop is running at `localhost:8090`; app pods are Ready; chart released as `robot-shop` |
| Observability stack | [observability pods](evidence/capstone2/observability-pods.txt) | kube-prometheus-stack, Loki, Fluent Bit, Jaeger and the OTel Collector are running |
| Dashboard as code | [dashboard JSON](../capstone2/observability/dashboards/robot-shop.json), [dashboard recovery screenshot](evidence/capstone2/robot-shop-dashboard-recovered.png) | Request rate, 5xx ratio, p95 latency, deployment readiness and Loki logs, with live data |
| Alert firing | [Prometheus alerts page](evidence/capstone2/robot-shop-prometheus-alerts.png), [alert JSON](evidence/capstone2/robot-shop-alert-firing.json) | `RobotShopServiceDown` is `firing` for `payment`; labels, annotations and `activeAt` are captured |
| Incident drill | [timestamps](evidence/capstone2/drill-timestamps.txt), [postmortem](../capstone2/docs/POSTMORTEM.md), [drill plan](../capstone2/docs/DRILL.md) | 4m52s payment outage; alert firing; mitigation in one scale command; 11s to Ready |
| During outage | [dashboard during outage](evidence/capstone2/robot-shop-dashboard-firing.png), [pods during drill](evidence/capstone2/robot-shop-pods-during-drill.txt), [scaled deployment](evidence/capstone2/payment-deployment-scaled-zero.yaml) | `payment` has 0 ready replicas; total ready deployments fall from 12 to 11 |
| Recovery | [dashboard recovered](evidence/capstone2/robot-shop-dashboard-recovered.png), [recovered alerts](evidence/capstone2/robot-shop-alerts-recovered.json) | `payment` is back at 1/1, 12 deployments Ready, no `RobotShop*` alert active |
| Structured logs | [Loki query result](evidence/capstone2/loki-payment-error.json) | LogQL `{namespace="robot-shop",service="payment"} |= "StreamLostError"` returns the payment error with `service=payment` and `level=error` |
| Distributed trace | [Jaeger trace list](evidence/capstone2/jaeger-web-trace.png), [trace JSON](evidence/capstone2/jaeger-web-trace.json) | `web.robot-shop`, `catalogue.robot-shop`, `cart.robot-shop` and `payment.robot-shop` traces exist; a `web` trace includes downstream spans |
| SLO and error budget | [`SLO.md`](../capstone2/docs/SLO.md), [`ERROR_BUDGET_POLICY.md`](../capstone2/docs/ERROR_BUDGET_POLICY.md) | 99.5% availability target, 216-minute monthly budget, SLI queries and budget states |
| Runbook linked from alert | [`RUNBOOK.md`](../capstone2/docs/RUNBOOK.md), [PrometheusRule](../capstone2/observability/robot-shop-alerts.yaml) | The alert annotation contains a `runbook_url`; the runbook names the deployment, dashboard and recovery command |

The alert and dashboard paths are code, not only screenshots:
[`robot-shop-alerts.yaml`](../capstone2/observability/robot-shop-alerts.yaml),
[`robot-shop-dashboard.yaml`](../capstone2/observability/robot-shop-dashboard.yaml),
[`kube-prometheus-stack-values.yaml`](../capstone2/observability/kube-prometheus-stack-values.yaml),
[`fluent-bit-values.yaml`](../capstone2/observability/fluent-bit-values.yaml),
[`loki-values.yaml`](../capstone2/observability/loki-values.yaml),
[`istio-values.yaml`](../capstone2/observability/istio-values.yaml),
[`jaeger.yaml`](../capstone2/observability/jaeger.yaml),
[`otel-collector.yaml`](../capstone2/observability/otel-collector.yaml), and the
[`alertmanager-slack.example.yaml`](../capstone2/observability/alertmanager-slack.example.yaml)
route that is ready to apply once a real webhook exists.

## Supplementary - Voting App observability on Docker Compose

These captures are from the earlier Compose run. They remain useful for
Capstone 1 and for showing the queue/worker SLO, but they are **not** the
Capstone 2 cluster evidence.

| Requirement | Evidence | What it proves |
| --- | --- | --- |
| Dashboard as code | [Grafana dashboard](evidence/screenshots/grafana-dashboard.png) | Request rate, 5xx, p95 latency, votes by choice, queue depth, queue age and scrape targets with live data |
| Freshness alert | [Grafana during the outage](evidence/screenshots/grafana-freshness-alert.png) | Queue at 80, worker down, oldest vote at 1.55 minutes, alert threshold crossed |
| Alert firing | [Prometheus alert page](evidence/screenshots/prometheus-alert-firing.png), [alerts JSON](evidence/prometheus-alerts-firing.json) | `VotingFreshnessAtRisk` is `firing`; `VotingQueueBacklog` is pending |
| Recovery | [Grafana after recovery](evidence/screenshots/grafana-recovered.png), [recovered alerts JSON](evidence/prometheus-alerts-recovered.json) | Worker back at 1 replica, queue 0, oldest vote 0s, no active alerts |
| Distributed trace | [Jaeger trace](evidence/screenshots/jaeger-vote-trace.png) | One `POST /vote` request with its child `RPUSH` span, service `vote`, 2.13 ms |
| Structured logs | [Loki query](evidence/screenshots/loki-error-query.png), [query JSON](evidence/loki-error-query.json) | LogQL `{service="vote"} \| json \| level="error"` returns the Redis-outage error with `trace_id` and `span_id` |
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

The submission is committed on `main` and tagged `v1.0.0` (Capstone 1) and
`v1.1.0` (Capstone 2); see [`git-commit.txt`](evidence/git-commit.txt).

## Reproduction

```powershell
# Capstone 1: local app and full local observability
powershell -ExecutionPolicy Bypass -File ./scripts/run-local.ps1 -WithObservability

# Capstone 1: incident drill with assertions
powershell -ExecutionPolicy Bypass -File ./scripts/drill-worker-outage.ps1 `
  -Votes 80 -OutageSeconds 60 -EvidencePath docs/evidence/worker-outage-drill.md

# Capstone 2: kind cluster, Robot Shop, Istio and observability
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-capstone2.ps1

# Capstone 2: payment outage drill
kubectl -n robot-shop scale deployment/payment --replicas=0
# after the alert fires:
kubectl -n robot-shop scale deployment/payment --replicas=1
```

The Capstone 2 script was re-run with `-SkipKindCreate` on 2026-10-26. It
upgraded every Helm release cleanly and all 13 Robot Shop pods plus the
observability pods were Ready afterwards. The command log is
[`run-capstone2.log`](evidence/capstone2/run-capstone2.log).

## Still requires an external account or paid resource

| Item | Why it is not captured here |
| --- | --- |
| Slack message from Alertmanager | No real Slack incoming-webhook URL was provided. The firing alert and its payload are captured; delivery needs `SLACK_WEBHOOK_URL` |
| GitHub Actions run with SHA-tagged images | The workflow is committed and locally validated, but pushing and running it needs a GitHub repository and credentials |
| EKS `terraform apply` / `terraform destroy` | EKS costs money and needs AWS credentials. The same chart was deployed and rolled back on kind as the local substitute |
| Forked repository URL | A local Git repository is initialized; creating the fork requires the user's GitHub account |
| Instructor-led incident | The instructor-led break was not available; the payment outage drill is the self-run substitute |

## Notes

- Capstone 2 screenshots were captured with headless Microsoft Edge against the
  Grafana instance port-forwarded from the kind cluster. Grafana anonymous
  Viewer access was enabled temporarily for evidence capture.
- The kind cluster owns ports 8080, 8081 and 8090. Stop Docker Compose before
  starting kind; do not run both stacks at the same time.
- Jaeger receives Istio mesh traces through the Zipkin endpoint (`9411`). The
  OTel Collector remains installed for application-level instrumentation, but
  the Envoy OTel gRPC exporter in this Istio version sent HTTP/1.1 to the gRPC
  receiver, so the mesh path uses Zipkin.
