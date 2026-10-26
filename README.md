# DevOps Capstone - Voting App and Robot Shop

A complete, runnable implementation of the two beginner DevOps capstones:

1. **Ship it** - containerize the Voting App, build a Kubernetes cluster with
   Terraform, add GitHub Actions CI/CD, and deploy/roll back with Helm.
2. **Keep it running** - deploy Stan's Robot Shop on Kubernetes, add metrics,
   logs, traces, an SLO, alerts, a dashboard and an incident postmortem.

The applications are intentionally small. The engineering around them is the
point.

## What is in the box

| Area | Implementation |
| --- | --- |
| Capstone 1 app | Python Flask `vote`, Flask `result`, Python `worker`, Redis 7, PostgreSQL 16 |
| Capstone 2 app | Vendored Stan's Robot Shop Helm chart in `capstone2/robot-shop`, with Instana removed |
| Local runtime | Docker Compose with health checks, non-root users and read-only containers |
| Kubernetes | kind cluster for Capstone 1 and Capstone 2; Helm charts with probes, resources and security contexts |
| Tests | 19 pytest unit tests; no live services required |
| Infrastructure | Terraform for EKS in the default VPC and ECR repositories, validated locally |
| CI/CD | GitHub Actions: tests, lint, Trivy, build/push by commit SHA, Helm deploy, rollback workflow |
| Metrics | Prometheus, kube-prometheus-stack, Grafana dashboards as code |
| Logs | Fluent Bit to Loki, searchable by namespace, service and level |
| Traces | OpenTelemetry for the Voting App; Istio/Zipkin to Jaeger for Robot Shop |
| Reliability | SLO, error-budget policy, Prometheus alerts, runbook, incident drill, blameless postmortem |
| Demo | Helm bad release and rollback, worker-outage drill, Robot Shop payment-outage drill |

## Quick start - Capstone 1 (Voting App)

Requirements: Docker Desktop with the Linux containers engine running.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local.ps1
```

or on Linux/macOS:

```bash
./scripts/run-local.sh
```

Open:

| URL | What |
| --- | --- |
| http://localhost:8080 | Vote page |
| http://localhost:8081 | Live result board |

Cast some votes, then open the result page. It refreshes every two seconds.

To run the local observability stack too:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local.ps1 -WithObservability
```

That adds Prometheus (9090), Grafana (3000), Jaeger (16686), Loki (3100) and
Promtail. Grafana credentials come from `.env` (`GRAFANA_ADMIN_USER` /
`GRAFANA_ADMIN_PASSWORD`). The local stack also loads
`observability/local/rules.yaml` so the freshness and queue alerts can be
demonstrated without Kubernetes.

Stop it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
```

## Quick start - Capstone 2 (Robot Shop on kind)

Stop the Compose stack first: kind owns ports 8080, 8081 and 8090.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-capstone2.ps1
```

The script creates the kind cluster, installs Istio, deploys Robot Shop,
installs kube-prometheus-stack, Loki, Fluent Bit, Jaeger and the OTel Collector,
and applies the SLO alerts and dashboard. If the cluster already exists:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-capstone2.ps1 -SkipKindCreate
```

Access:

| URL | What |
| --- | --- |
| http://localhost:8090 | Stan's Robot Shop |
| http://localhost:3000 | Grafana, dashboard UID `robot-shop-slo` |
| http://localhost:9090 | Prometheus; `/alerts` shows `robot-shop.slo` |
| http://localhost:16686 | Jaeger |

Port-forward the UIs if they are not already forwarded:

```powershell
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n observability port-forward svc/jaeger-query 16686:16686
```

Grafana uses `admin` / `admin` in the kind demo. The load generator runs
continuously against `http://web:8080/`.

The manual install commands, chart details and limitations are in
[`capstone2/README.md`](capstone2/README.md).

## Architecture

### Capstone 1 - Voting App

```text
Browser -> vote (Flask) -> Redis list "votes" -> worker -> PostgreSQL
Browser -> result (Flask) -> PostgreSQL aggregates

vote/result/worker -> Prometheus /metrics
vote/result/worker -> OpenTelemetry Collector -> Jaeger
all services -> stdout -> Promtail/Fluent Bit -> Loki -> Grafana
```

The Redis queue decouples the web tier from the database. The worker uses
at-least-once processing and the database uses a UUID primary key with
`ON CONFLICT DO NOTHING`, so a re-delivered vote is idempotent.

### Capstone 2 - Robot Shop

```text
Browser -> web -> catalogue / cart / payment / ratings / shipping
cart -> Redis + MongoDB
catalogue -> MongoDB
ratings / shipping / user -> MariaDB
dispatch -> RabbitMQ

Istio sidecars -> Prometheus (Istio request metrics)
Istio sidecars --Zipkin--> Jaeger
all pods --stdout--> Fluent Bit -> Loki -> Grafana
Prometheus -> Alertmanager
```

The graded path is `web -> catalogue/cart/payment`; the other services are kept
running because Robot Shop expects them.

## Observability and reliability

- **Dashboard as code:** [`capstone2/observability/dashboards/robot-shop.json`](capstone2/observability/dashboards/robot-shop.json)
  shows request rate, 5xx ratio, p95 latency, deployment readiness and recent
  Loki error logs.
- **Alerts:** [`capstone2/observability/robot-shop-alerts.yaml`](capstone2/observability/robot-shop-alerts.yaml)
  defines `RobotShopHighErrorRate`, `RobotShopHighLatency`, `RobotShopServiceDown`
  and `RobotShopPodRestarting`.
- **SLO:** [`capstone2/docs/SLO.md`](capstone2/docs/SLO.md) sets 99.5%
  availability over 30 days (216 minutes of error budget) with a secondary
  p95 latency target.
- **Error-budget policy:** [`capstone2/docs/ERROR_BUDGET_POLICY.md`](capstone2/docs/ERROR_BUDGET_POLICY.md).
- **Runbook:** [`capstone2/docs/RUNBOOK.md`](capstone2/docs/RUNBOOK.md); the
  alert annotations link to it.
- **Incident drill:** [`capstone2/docs/DRILL.md`](capstone2/docs/DRILL.md) and
  [`capstone2/docs/POSTMORTEM.md`](capstone2/docs/POSTMORTEM.md). The payment
  service was scaled to zero, the alert fired, and recovery took 11 seconds
  after mitigation.
- **Voting App SLO:** [`docs/SLO.md`](docs/SLO.md),
  [`docs/RUNBOOK.md`](docs/RUNBOOK.md), and the worker-outage postmortem in
  [`docs/postmortems/2026-10-26-worker-outage-drill.md`](docs/postmortems/2026-10-26-worker-outage-drill.md).

## Capstone 1 Kubernetes path

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-kind-cluster.ps1
```

This builds the images, loads them into a kind cluster, creates the database
secret from `.env`, and installs the chart with `values-kind.yaml`. The UI is
at http://localhost:8080 and http://localhost:8081.

Rollback demo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollback.ps1
```

The script upgrades to a deliberately broken image tag, waits for failure, runs
`helm rollback`, and verifies the rollout. The equivalent manual commands are in
[`docs/DEMO.md`](docs/DEMO.md).

## Repository layout

```text
services/                 vote, result and worker source + Dockerfiles
shared/voting_common/     logging, metrics, DB and vote choices
tests/                    unit tests
deploy/helm/voting-app/   Capstone 1 Helm chart with default/kind/prod values
deploy/kind-config.yaml   kind ports 8080, 8081 and 8090
infra/terraform/          EKS in the default VPC + ECR
observability/            Voting App Prometheus/Grafana/Loki/OTel/Jaeger assets
scripts/                  local run, kind, load test, rollback, outage drills
docs/                     architecture, SLO, runbook, demo, evidence, checklist
capstone2/robot-shop/     vendored Robot Shop chart, Instana removed, MariaDB
capstone2/observability/  kube-prometheus-stack, Loki, Fluent Bit, Istio, Jaeger, dashboards
capstone2/docs/           Robot Shop SLO, error budget, runbook, drill, postmortem
docs/evidence/capstone2/  Robot Shop screenshots, alert JSON, logs and traces
.github/workflows/        CI/CD pipeline
compose.yaml              local Voting App stack
compose.observability.yaml
```

## Verification

```powershell
python -m pytest -q
helm lint deploy/helm/voting-app
helm lint capstone2/robot-shop
terraform -chdir=infra/terraform validate
docker compose config --quiet
```

For the live Robot Shop checks:

```powershell
kubectl -n robot-shop get pods
kubectl -n observability get pods
kubectl -n observability get prometheusrule robot-shop-slo
```

The commands that were actually run are recorded in
[`docs/evidence/local-ci-checks.txt`](docs/evidence/local-ci-checks.txt).

## Evidence and hand-in

Start with [`docs/EVIDENCE.md`](docs/EVIDENCE.md), then
[`docs/CAPSTONE_CHECKLIST.md`](docs/CAPSTONE_CHECKLIST.md),
[`capstone2/README.md`](capstone2/README.md) and
[`capstone2/docs/POSTMORTEM.md`](capstone2/docs/POSTMORTEM.md).

The local Git repository is committed on `main` and tagged `v1.0.0`.

## External gaps

These cannot be completed without an external account, paid cloud resource, or
instructor:

- **Slack delivery:** no real incoming-webhook URL. The alert fires locally and
  the payload is captured; add `SLACK_WEBHOOK_URL` and verify one message.
- **GitHub Actions run:** the workflow and actionlint pass, but there is no
  GitHub remote/credentials. Push the repository and set the repository
  variables/secrets before running it.
- **EKS apply/destroy:** Terraform validates, but applying it needs AWS
  credentials and a budget. kind is the local cluster substitute.
- **GitHub fork:** the local repository exists; creating a fork requires the
  user's GitHub account.
- **Instructor-led incident:** the payment outage drill is the self-run
  substitute.

## Limitations

- Robot Shop runs on kind, not EKS. The chart and values are portable, but the
  local cluster is single-node.
- The MySQL 5.7 image from the upstream chart repeatedly OOMKilled on this kind
  node. MariaDB 10.5 with a small seed ConfigMap is used instead. The schema is
  compatible with the app, and `ratings`/`shipping` become Ready.
- Istio mesh traces use the Zipkin provider because Envoy's OTel gRPC exporter
  in this Istio version sent HTTP/1.1 to the gRPC receiver. The OTel Collector
  remains installed for application-level instrumentation.
- The load generator and the existing payment/RabbitMQ `StreamLostError` keep
  the baseline 5xx and p95 above the SLO thresholds. The payment outage drill
  therefore uses `RobotShopServiceDown` as its clean signal.
- Grafana anonymous Viewer access was enabled temporarily for evidence capture;
  disable it for a shared deployment.
