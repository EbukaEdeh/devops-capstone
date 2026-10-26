# Capstone Checklist

## Grading map

| Weight | Criterion | Evidence in this repository |
| --- | --- | --- |
| 50% | Working system | Voting App (Compose + kind) and Robot Shop (kind) are running; 19 tests; live UIs |
| 30% | Automation and docs | Terraform, Helm, GitHub Actions, README, architecture, SLO, runbook, postmortem, evidence index |
| 20% | Demo and Q&A | `docs/DEMO.md`, rollback script, payment outage drill, Prometheus/Grafana/Jaeger/Loki evidence |

## Capstone 1 - Ship it

| Step | Done when | Status | Evidence |
| --- | --- | --- | --- |
| 1. Run locally | You can vote and see totals | Done | `scripts/run-local.ps1`; vote and result pages |
| 2. Containerize safely | Images build, non-root, pinned, `.dockerignore` | Done | three Dockerfiles, `docker compose ps` healthy |
| 3. Terraform cluster | Destroy and recreate EKS in the default VPC | Code done; apply blocked | `infra/terraform/*`, `terraform validate`; EKS needs AWS credentials and budget |
| 4. GitHub Actions | Push runs tests, Trivy, build/push by SHA | Workflow done; run blocked | `.github/workflows/ci-cd.yml`, actionlint; needs a GitHub remote |
| 5. Helm deploy/rollback | One chart, bad release rolled back | Done | chart, `values-prod.yaml`, `scripts/demo-rollback.ps1`, `helm history` |

### Capstone 1 evidence

- [x] Vote page and result page with non-zero totals: [vote](evidence/screenshots/vote-page.png), [result](evidence/screenshots/result-page.png), [kind vote](evidence/screenshots/kind-vote-page.png), [kind result](evidence/screenshots/kind-result-page.png).
- [x] `docker compose ps` showing healthy services: [capture](evidence/docker-compose-ps.txt).
- [x] `kubectl get nodes` from the kind cluster: [capture](evidence/kind-nodes.txt).
- [ ] `terraform output` from a real EKS apply. Not run: EKS costs money and needs AWS credentials; kind is the local substitute.
- [ ] Successful GitHub Actions run with three SHA-tagged images. Workflow is committed and locally validated; the run needs a GitHub remote.
- [x] `helm history voting-app` showing deploy and rollback revisions: [before](evidence/helm-history-before-rollback.txt), [after](evidence/helm-history-after-rollback.txt).
- [x] `kubectl -n voting get pods` after rollback: [capture](evidence/kind-pods-after-rollback.txt), [rollback log](evidence/rollback-demo.log).

## Capstone 2 - Keep it running (Robot Shop)

| Step | Done when | Status | Evidence |
| --- | --- | --- | --- |
| 1. Deploy Robot Shop | App healthy under load on the Capstone 1 cluster | Done | `capstone2/robot-shop`, kind `voting-capstone`, `localhost:8090`, load generator |
| 2. Remove Instana | No `INSTANA_*` settings in the chart | Done | `capstone2/robot-shop/templates/*`; `helm template` renders none |
| 3. Metrics | kube-prometheus-stack plus one dashboard for requests, errors, latency | Done | `capstone2/observability/kube-prometheus-stack-values.yaml`, `dashboards/robot-shop.json` |
| 4. Logs | Fluent Bit to Loki; search by service and level | Done | `fluent-bit-values.yaml`, `loki-values.yaml`, `docs/evidence/capstone2/loki-payment-error.json` |
| 5. Tracing | One request traced in Jaeger | Done | Istio Zipkin to Jaeger; `docs/evidence/capstone2/jaeger-web-trace.png`, `jaeger-web-trace.json` |
| 6. SLO | Availability target, error-budget policy | Done | `capstone2/docs/SLO.md`, `ERROR_BUDGET_POLICY.md` |
| 7. Alert to Slack | One alert delivered to Slack | Blocked | Alert fires locally; no real `SLACK_WEBHOOK_URL` was provided |
| 8. Incident drill | Mitigate, diagnose, postmortem | Done (self-run) | `capstone2/docs/DRILL.md`, `POSTMORTEM.md`, `docs/evidence/capstone2/` |
| 9. Runbook | Linked from the alert | Done | `capstone2/docs/RUNBOOK.md`, annotation in `robot-shop-alerts.yaml` |

### Capstone 2 evidence

- [x] Dashboard as code with requests, errors and latency: [dashboard JSON](../capstone2/observability/dashboards/robot-shop.json), [live screenshot](evidence/capstone2/robot-shop-dashboard-recovered.png).
- [x] Robot Shop UI and healthy pods: [UI](evidence/capstone2/robot-shop-ui.png), [pods](evidence/capstone2/robot-shop-pods-healthy.txt).
- [x] Metrics stack and dashboard: [observability pods](evidence/capstone2/observability-pods.txt), [Helm releases](evidence/capstone2/helm-releases.txt).
- [x] Loki query filtered by service and level: [query result](evidence/capstone2/loki-payment-error.json) returns `service=payment`, `level=error`.
- [x] Jaeger trace for a real request: [trace list](evidence/capstone2/jaeger-web-trace.png), [trace JSON](evidence/capstone2/jaeger-web-trace.json).
- [x] Prometheus alert in `firing` state: [alerts page](evidence/capstone2/robot-shop-prometheus-alerts.png), [alerts JSON](evidence/capstone2/robot-shop-alert-firing.json).
- [x] Payment outage drill with real timestamps: [timeline](evidence/capstone2/drill-timestamps.txt), [postmortem](../capstone2/docs/POSTMORTEM.md).
- [x] During-outage and recovery evidence: [firing dashboard](evidence/capstone2/robot-shop-dashboard-firing.png), [recovered dashboard](evidence/capstone2/robot-shop-dashboard-recovered.png), [recovered alerts](evidence/capstone2/robot-shop-alerts-recovered.json).
- [x] Error-budget calculation: [`SLO.md`](../capstone2/docs/SLO.md) and [`ERROR_BUDGET_POLICY.md`](../capstone2/docs/ERROR_BUDGET_POLICY.md).
- [ ] Slack message from Alertmanager. No real webhook URL was available; the firing alert and payload are captured. This is the only Capstone 2 evidence gap.

## Hand-in

- [ ] Forked repository with a clear README. A local Git repository is initialized and committed; creating the fork needs the user's GitHub account.
- [x] Terraform code and one Helm chart.
- [ ] Working GitHub Actions pipeline. The workflow exists and passes the same checks locally; the Actions run needs a GitHub remote.
- [x] Architecture diagram: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) and [`capstone2/README.md`](../capstone2/README.md).
- [ ] One push builds, scans and deploys. Not executed without a GitHub remote.
- [x] Environment rebuilds from code: local Compose and kind both built from the repository; EKS is not applied.
- [x] No secrets in Git (`git grep` for passwords; `.env` ignored).
- [x] Rollback shown live: [evidence](evidence/rollback-demo.log).
- [x] Dashboard exported as code.
- [x] Logging and tracing configuration.
- [x] SLO document with error-budget policy.
- [x] Blameless postmortem.
- [x] Alert fires during the drill.
- [x] Runbook linked from the alert annotations.
- [x] Demo and Q&A prepared.
- [x] Evidence index: [docs/EVIDENCE.md](EVIDENCE.md).

## Known deviations and gaps

| Gap | Why | What is already done |
| --- | --- | --- |
| Capstone 1 is a reimplementation, not a GitHub fork of `dockersamples/example-voting-app` | No GitHub account/remote was available | Same vote/result/worker/Redis/PostgreSQL architecture, Compose and Helm paths, tests and evidence |
| Capstone 2 chart is vendored, not a GitHub fork of `instana/robot-shop` | No GitHub account/remote | Upstream chart copied, Instana removed, MariaDB workaround, kind values and load generator |
| No EKS apply/destroy | AWS credentials and budget are not available | Terraform validates; kind is the local cluster substitute |
| No GitHub Actions run | No GitHub remote/credentials | Workflow committed and actionlint clean; local checks recorded |
| No Slack delivery | No real webhook URL | Alert fires and payload is captured; Alertmanager route is documented |
| Incident was self-run, not instructor-broken | Instructor-led break was not available | Same detect/mitigate/recover/postmortem path, with real timestamps |

## Final checks

```powershell
# Tests
python -m pytest -q

# No secrets in tracked files
& 'C:\Program Files\Git\cmd\git.exe' grep -n -i -E "password\s*=|secret\s*=|slack_api_url\s*=" -- . ':!*.example' ':!docs/*'

# Compose
docker compose config --quiet

# Helm
helm lint deploy/helm/voting-app
helm lint capstone2/robot-shop
helm template voting-app deploy/helm/voting-app `
  -f deploy/helm/voting-app/values-prod.yaml `
  --set postgresql.auth.existingSecret=voting-db-credentials > $null

# Terraform
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate

# Capstone 2 live checks
kubectl -n robot-shop get pods
kubectl -n observability get pods
kubectl -n observability get prometheusrule robot-shop-slo
```
