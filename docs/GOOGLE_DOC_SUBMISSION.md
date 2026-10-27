# DevOps Capstone Submission - Voting App and Robot Shop

| Field | Value |
| --- | --- |
| Name | Ebuka Edeh |
| Cohort | TS Academy DevOps (Hajime 2026) |
| Submission date | October 2026 |
| Repository | REPLACE_REPO_URL |
| Implementation tag | `v1.1.0` |
| Demo environment | local kind cluster `voting-capstone` (single node) |

> One repository contains both capstones. Capstone 1 is at the repository root;
> Capstone 2 is in `capstone2/`. Replace `REPLACE_REPO_URL` in this file with the
> public repository URL **before pasting** so every hyperlink target is correct.

## 1. Summary

I built and ran both capstone projects end to end:

- **Capstone 1 - Ship it:** a containerized Voting App (Flask vote, Flask result,
  Python worker, Redis and PostgreSQL), a Helm chart with probes and security
  contexts, Terraform for EKS and ECR, a GitHub Actions pipeline, and a
  demonstrated bad-release rollback.
- **Capstone 2 - Keep it running:** Stan's Robot Shop on Kubernetes with Instana
  removed, Prometheus and Grafana metrics, Fluent Bit to Loki logs, Istio to
  Jaeger traces, an SLO and error-budget policy, Prometheus alerts, a runbook,
  and a payment-outage incident drill with a blameless postmortem.

The applications are intentionally small. The engineering around them -
containers, infrastructure as code, CI/CD, release management, observability,
SLOs and incident response - is the deliverable.

The implementation is committed on `main` and tagged `v1.1.0`. The evidence was
captured locally on 26 October 2026 (UTC) and is indexed in
[`docs/EVIDENCE.md`](REPLACE_REPO_URL/blob/main/docs/EVIDENCE.md).

## 2. Repository map

| Part | Location | What is there |
| --- | --- | --- |
| Capstone 1 app | `services/` | `vote`, `result` and `worker` source plus Dockerfiles |
| Capstone 1 chart | `deploy/helm/voting-app/` | Helm chart with default, kind and prod values |
| Capstone 1 infrastructure | `infra/terraform/` | EKS in the default VPC and ECR repositories |
| Capstone 1 CI/CD | `.github/workflows/ci-cd.yml` | Tests, lint, Trivy, build/push by commit SHA, Helm deploy and rollback |
| Capstone 2 | `capstone2/` | Vendored Robot Shop chart, observability values, dashboards and docs |
| Capstone 2 guide | `capstone2/README.md` | One-command bring-up, access URLs and demo script |
| Evidence | `docs/EVIDENCE.md` | Screenshots, command output, alert JSON, logs and traces |
| Grading status | `docs/CAPSTONE_CHECKLIST.md` | Requirement-by-requirement status and known deviations |

Useful links:

- Repository: REPLACE_REPO_URL
- Root README: REPLACE_REPO_URL/blob/main/README.md
- Evidence index: REPLACE_REPO_URL/blob/main/docs/EVIDENCE.md
- Grading checklist: REPLACE_REPO_URL/blob/main/docs/CAPSTONE_CHECKLIST.md
- Capstone 2 guide: REPLACE_REPO_URL/tree/main/capstone2
- Incident postmortem: REPLACE_REPO_URL/blob/main/capstone2/docs/POSTMORTEM.md

## 3. Capstone 1 - Ship it

### What the app does

A browser casts a vote on the `vote` page. The Flask `vote` service pushes the
choice onto a Redis list named `votes` and returns immediately. A Python
`worker` consumes the list and writes each vote to PostgreSQL. The `result`
service reads aggregate counts from PostgreSQL and refreshes every two seconds.
The worker uses a UUID primary key with `ON CONFLICT DO NOTHING`, so a message
delivered more than once is still counted once.

### Requirement status

| Requirement | Status | Evidence |
| --- | --- | --- |
| Clone the Voting App and run it locally | Done | Vote and result screenshots: `docs/evidence/screenshots/vote-page.png`, `docs/evidence/screenshots/result-page.png`; 283 ballots captured |
| Containerize the application | Done | `services/vote/Dockerfile`, `services/result/Dockerfile`, `services/worker/Dockerfile`, `compose.yaml` |
| Run containers safely | Done | Non-root users, pinned base images, read-only containers, health checks, `.dockerignore` |
| Terraform an EKS cluster in the default VPC | Code complete and validated; apply not run | `infra/terraform/`; `terraform fmt -check` and `terraform validate` pass |
| GitHub Actions pipeline | Workflow complete and linted; live run not executed | `.github/workflows/ci-cd.yml`; `actionlint` reports no issues in `docs/evidence/local-ci-checks.txt` |
| Helm deploy and rollback | Done | `docs/evidence/helm-history-before-rollback.txt`, `docs/evidence/helm-history-after-rollback.txt`, `docs/evidence/rollback-demo.log` |
| Tests | Done | 19 pytest tests pass; see `docs/evidence/local-ci-checks.txt` |

### Release and rollback evidence

The Helm release `voting-app` was installed in namespace `voting` as revision 1.
A deliberately broken image tag produced revision 2, which failed to become
Ready. `helm rollback` created revision 3 pointing back at revision 1, and the
application served votes again. The captured history and pod list are in
`docs/evidence/helm-history-after-rollback.txt` and
`docs/evidence/kind-pods-after-rollback.txt`.

The pipeline is designed to do the same thing automatically: it builds images
tagged with the commit SHA, pushes them to GHCR, deploys with
`helm upgrade --atomic --wait`, and exposes a manual `rollback` action that runs
`helm rollback` and verifies the rollout.

## 4. Capstone 2 - Keep it running

### What was deployed

Stan's Robot Shop runs in namespace `robot-shop` on the same kind cluster. The
chart was vendored from `instana/robot-shop` (`K8s/helm`), and Instana was
removed. The graded request path is:

`web -> catalogue/cart/payment`

Cart uses Redis and MongoDB, catalogue uses MongoDB, and ratings, shipping and
user use MariaDB. Dispatch uses RabbitMQ. Istio sidecars expose request metrics
to Prometheus and send mesh traces to Jaeger through the Zipkin endpoint. Pod
stdout is collected by Fluent Bit and shipped to Loki.

### Requirement status

| Requirement | Status | Evidence |
| --- | --- | --- |
| Deploy Robot Shop to Kubernetes | Done | `docs/evidence/capstone2/robot-shop-ui.png`, `docs/evidence/capstone2/robot-shop-pods-healthy.txt`, `docs/evidence/capstone2/helm-releases.txt` |
| Remove Instana | Done | Vendored chart in `capstone2/robot-shop`; no Instana agent or configuration |
| Metrics and one dashboard | Done | Dashboard JSON in `capstone2/observability/dashboards/robot-shop.json`; live capture in `docs/evidence/capstone2/robot-shop-dashboard-recovered.png` |
| Logs searchable by service and level | Done | `docs/evidence/capstone2/loki-payment-error.json`; LogQL `{namespace="robot-shop",service="payment"} |= "StreamLostError"` returns `service=payment`, `level=error` |
| Trace one request in Jaeger | Done | `docs/evidence/capstone2/jaeger-web-trace.png` and `docs/evidence/capstone2/jaeger-web-trace.json`; `web` trace includes downstream `catalogue`, `cart` and `payment` spans |
| SLO and error-budget policy | Done | `capstone2/docs/SLO.md` and `capstone2/docs/ERROR_BUDGET_POLICY.md`; 99.5% availability over 30 days = 216 minutes |
| Alert delivered to Slack | Alert fires; Slack delivery not executed | `docs/evidence/capstone2/robot-shop-alert-firing.json` shows `RobotShopServiceDown` firing for `payment`; `capstone2/observability/alertmanager-slack.example.yaml` is ready for a real webhook |
| Incident drill and blameless postmortem | Done | `capstone2/docs/POSTMORTEM.md`, `capstone2/docs/DRILL.md`, `docs/evidence/capstone2/drill-timestamps.txt` |
| Runbook linked from the alert | Done | `capstone2/docs/RUNBOOK.md`; the `runbook_url` annotation is in `capstone2/observability/robot-shop-alerts.yaml` |

### Dashboard and alerts

The Grafana dashboard is **Robot Shop - Service Health**, UID `robot-shop-slo`.
It shows request rate, 5xx ratio, p95 latency, errors by service, status codes,
deployment readiness and recent Loki error logs for `web`, `catalogue`, `cart`
and `payment`.

The Prometheus rules are:

- `RobotShopHighErrorRate` - 5xx ratio above 5% for 5 minutes, critical.
- `RobotShopHighLatency` - p95 above 500 ms for 5 minutes, warning.
- `RobotShopServiceDown` - zero ready replicas for 2 minutes, critical.
- `RobotShopPodRestarting` - repeated restarts, warning.

The SLO is 99.5% availability over 30 days, which is 216 minutes of error
budget. The 5% fast-burn alert is deliberately tighter than the 0.5% SLO
threshold so the team is warned before the monthly budget is exhausted.

### Incident drill result

`payment` was scaled to zero at 23:20:20 UTC on 26 October 2026. The
`RobotShopServiceDown` alert fired after the 2-minute `for` window plus
evaluation, the dashboard showed 0 ready payment replicas and 11 of 12
deployments ready, and Loki showed the payment `StreamLostError` messages.
Scaling `payment` back to 1 produced a Ready pod in 11 seconds and the alert
cleared at 23:25:58 UTC. Total customer-visible outage: 4 minutes 52 seconds,
or 2.3% of the monthly error budget.

The postmortem records the timeline, root cause (single replica with no
PodDisruptionBudget), what went well, what went poorly, and action items. It is
blameless: the drill was intentional, and the response is treated as a system
and process learning exercise.

## 5. Architecture in one page

### Voting App

```text
browser -> vote (Flask) -> Redis list "votes" -> worker -> PostgreSQL
browser -> result (Flask) -> PostgreSQL aggregates
```

All three services expose `/metrics`. The Compose observability profile adds
Prometheus, Grafana, Jaeger, Loki and Promtail. In Kubernetes, the chart adds
readiness and liveness probes, resource requests and limits, a HorizontalPodAutoscaler,
a ServiceMonitor and a PrometheusRule. The worker handles SIGTERM gracefully and
keeps Redis as the buffer if PostgreSQL is temporarily unavailable.

### Robot Shop

```text
browser -> web -> catalogue / cart / payment / ratings / shipping
cart -> Redis + MongoDB
catalogue -> MongoDB
ratings / shipping / user -> MariaDB
dispatch -> RabbitMQ
Istio sidecars -> Prometheus + Zipkin -> Jaeger
pod stdout -> Fluent Bit -> Loki -> Grafana
Prometheus -> Alertmanager
```

The dashboard, alert rules and SLO are all stored as code, not created by hand
in the UI.

## 6. How to run it

### Capstone 1 - local Docker Compose

Requirements: Docker Desktop with Linux containers running.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local.ps1
```

Open `http://localhost:8080` to vote and `http://localhost:8081` for results.
To include Prometheus, Grafana, Jaeger, Loki and Promtail:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local.ps1 -WithObservability
```

Grafana credentials come from `.env` (`GRAFANA_ADMIN_USER` and
`GRAFANA_ADMIN_PASSWORD`). Stop the stack with
`.\scripts\stop-local.ps1`.

### Capstone 1 - kind and Helm

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\create-kind-cluster.ps1
```

This builds the images, loads them into kind, creates the database secret from
`.env`, and installs the chart with `values-kind.yaml`. The UI is again at
`http://localhost:8080` and `http://localhost:8081`.

Rollback demo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-rollback.ps1
```

### Capstone 2 - Robot Shop on kind

Stop Docker Compose first, because kind owns ports 8080, 8081 and 8090.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-capstone2.ps1
```

The script creates the kind cluster, installs Istio, Robot Shop,
kube-prometheus-stack, Loki, Fluent Bit, Jaeger and the OTel Collector, then
applies the SLO alerts and dashboard. If the cluster already exists:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-capstone2.ps1 -SkipKindCreate
```

Access:

| URL | What |
| --- | --- |
| `http://localhost:8090` | Robot Shop |
| `http://localhost:3000` | Grafana, dashboard UID `robot-shop-slo` |
| `http://localhost:9090` | Prometheus, `/alerts` |
| `http://localhost:16686` | Jaeger |

In the kind demo the Grafana login is `admin` / `admin`. Stop the cluster with
`kind delete cluster --name voting-capstone`.

## 7. Five-minute demo path

1. Open the vote page, cast a vote, and open the result page. Both are backed by
   Redis, the worker and PostgreSQL.
2. Show `docker compose ps` or `kubectl -n voting get pods`; all services are
   healthy.
3. Show the Helm history: revision 2 failed on a broken image, revision 3 is the
   rollback to revision 1. The app still serves votes.
4. Open the Robot Shop UI on port 8090, then the Grafana dashboard. Point at
   request rate, 5xx ratio, p95 latency, readiness and the Loki log panel.
5. Open the Jaeger trace for `web.robot-shop`, then the firing
   `RobotShopServiceDown` alert and the postmortem. Explain the 4m52s outage,
   the one-command mitigation and the 11-second recovery.

## 8. Verification results

The commands below were run locally and recorded in
`docs/evidence/local-ci-checks.txt`:

| Check | Result |
| --- | --- |
| `python -m pytest -q` | 19 passed |
| `helm lint deploy/helm/voting-app` | 0 failed |
| `helm lint capstone2/robot-shop` | 0 failed |
| `helm template` for both charts | Rendered successfully |
| `terraform fmt -check` and `terraform validate` | Clean and valid |
| `docker compose config --quiet` | Exit 0 |
| `actionlint` on `.github/workflows/ci-cd.yml` | No issues (actionlint 1.7.12) |
| Markdown relative-link check | 9 files checked, 0 broken |
| Capstone 2 bring-up with `-SkipKindCreate` | All Helm releases upgraded; 13 Robot Shop pods and observability pods Ready |

The Robot Shop run log is `docs/evidence/capstone2/run-capstone2.log`.

## 9. Known gaps and honest status

These items are **not** claimed as complete:

1. **EKS apply and destroy were not run.** The Terraform code is complete and
   validates, but applying it needs AWS credentials and a budget. Robot Shop and
   the Voting App were deployed and exercised on kind instead. The chart and
   values are portable to EKS; the cluster-specific values are in
   `deploy/helm/voting-app/values-prod.yaml`.
2. **The GitHub Actions workflow has not run on GitHub.** The workflow is
   committed and passes `actionlint`, but there is no GitHub remote or AWS OIDC
   role in this environment. Pushing the repository and setting
   `AWS_ROLE_ARN`, `AWS_REGION`, `EKS_CLUSTER_NAME`, `POSTGRES_PASSWORD` and the
   optional `APP_URL` is the remaining step.
3. **Slack delivery was not executed.** No real incoming-webhook URL was
   available. The alert fires in Prometheus and the payload is captured; the
   Alertmanager route is in
   `capstone2/observability/alertmanager-slack.example.yaml`. Add
   `SLACK_WEBHOOK_URL` and verify one message.
4. **The repository is an implementation, not a GitHub fork.** The Capstone 1
   app follows the `dockersamples/example-voting-app` architecture, and the
   Capstone 2 chart is vendored from `instana/robot-shop` with Instana removed.
   Creating forks requires the GitHub account; the local repository is the
   submission artifact.
5. **The incident was self-run, not instructor-led.** The payment outage drill is
   the substitute for an instructor breaking the system. The timeline and
   postmortem are real captures from that drill.

These gaps are visible in `docs/CAPSTONE_CHECKLIST.md` rather than being hidden.
The working system, the code, the local verification and the evidence for every
completed requirement are all in the repository.

## 10. What I would do next

- Push the repository to GitHub and run the pipeline against a kind or EKS
  target, capturing the first green run.
- Apply and destroy the Terraform stack in a budgeted AWS account, then repeat
  the same Helm deployment on EKS.
- Add a real Slack webhook and capture the delivered alert.
- Run `payment` with two replicas and a PodDisruptionBudget, and reduce the
  `RobotShopServiceDown` `for` window to one minute.
- Investigate the payment/RabbitMQ `StreamLostError` and remove the load
  generator noise from the baseline so the error-rate alert can be the primary
  drill signal.

## 11. Submission contents

- [x] One repository containing both capstones
- [x] Root README with run instructions and repository map
- [x] Evidence index with screenshots, command output, logs, traces and alerts
- [x] Capstone 1 app, Dockerfiles, Compose stack, Helm chart and rollback proof
- [x] Capstone 1 Terraform for EKS and ECR (validated)
- [x] Capstone 1 GitHub Actions workflow (committed and linted)
- [x] Capstone 2 Robot Shop deployment on kind
- [x] Capstone 2 metrics, dashboard, logs, traces, SLO, alerts, runbook and postmortem
- [x] Local verification results recorded
- [ ] Replace `REPLACE_REPO_URL` with the public repository URL
- [ ] Paste this text into the Google Doc and submit the link
