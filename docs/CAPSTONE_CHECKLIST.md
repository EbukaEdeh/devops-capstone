# Capstone Checklist

## Grading map

| Weight | Criterion | Evidence in this repository |
| --- | --- | --- |
| 50% | Working system | `compose.yaml`, three services, Redis/Postgres, live result page, 19 tests, kind cluster path |
| 30% | Automation and docs | Terraform, Helm, GitHub Actions, README, architecture, SLO, runbook, postmortem template |
| 20% | Demo and Q&A | `docs/DEMO.md`, rollback script, incident drill, alert rules |

## Capstone 1 — Ship it

| Step | Done when | Evidence |
| --- | --- | --- |
| 1. Run locally | You can vote and see totals | `scripts/run-local.ps1`; result page |
| 2. Containerize safely | Images build, non-root, pinned, `.dockerignore` | three Dockerfiles, `docker compose ps` healthy |
| 3. Terraform cluster | Destroy and recreate EKS in the default VPC | `infra/terraform/*`, `terraform validate`, apply/destroy screenshots |
| 4. GitHub Actions | Push runs tests, Trivy, build/push by SHA | `.github/workflows/ci-cd.yml`, Actions run |
| 5. Helm deploy/rollback | One chart, bad release rolled back | chart, `values-prod.yaml`, `scripts/demo-rollback.ps1`, `helm history` |

### Evidence to capture

- [x] Screenshot of vote page and result page with non-zero totals: [vote](evidence/screenshots/vote-page.png), [result](evidence/screenshots/result-page.png), [kind vote](evidence/screenshots/kind-vote-page.png), [kind result](evidence/screenshots/kind-result-page.png).
- [x] `docker compose ps` showing all services healthy: [capture](evidence/docker-compose-ps.txt).
- [x] `kubectl get nodes` from the kind cluster: [capture](evidence/kind-nodes.txt).
- [ ] `terraform output` from a real EKS apply. Not run: EKS costs money and needs AWS credentials; kind is the local substitute.
- [ ] Successful GitHub Actions run with three SHA-tagged images. Workflow is committed and locally validated; the run needs a GitHub remote.
- [x] `helm history voting-app` showing deploy and rollback revisions: [before](evidence/helm-history-before-rollback.txt), [after](evidence/helm-history-after-rollback.txt).
- [x] `kubectl -n voting get pods` after rollback: [capture](evidence/kind-pods-after-rollback.txt), [rollback log](evidence/rollback-demo.log).

## Capstone 2 — Keep it running

| Step | Done when | Evidence |
| --- | --- | --- |
| 1. Deploy and watch | Robot Shop or this app healthy under load | load test, Grafana |
| 2. Metrics | kube-prometheus-stack + one dashboard for requests/errors/latency | `observability/kube-prometheus-stack-values.yaml`, dashboard JSON |
| 3. Logs | Fluent Bit → Loki; search by service and level | `observability/fluent-bit-values.yaml`, LogQL screenshot |
| 4. Trace | One request traced in Jaeger | `observability/otel-collector.yaml`, `jaeger.yaml`, trace screenshot |
| 5. SLO | Availability target, error-budget policy, Slack alert | `docs/SLO.md`, `PrometheusRule`, Slack screenshot |
| 6. Incident drill | Mitigate, diagnose, postmortem | `scripts/drill-worker-outage.ps1`, [drill postmortem](postmortems/2026-10-26-worker-outage-drill.md) |

> The slide deck names Stan's Robot Shop for Capstone 2. This repository keeps
> the Voting App as the observed system so the whole submission is one coherent
> system. If your instructor requires Robot Shop, deploy it with their chart and
> reuse the observability and SLO artifacts here; the SLO queries and runbook
> patterns carry over.

### Evidence to capture

- [x] Grafana dashboard with traffic and a non-zero vote count: [dashboard](evidence/screenshots/grafana-dashboard.png), [during outage](evidence/screenshots/grafana-freshness-alert.png), [recovered](evidence/screenshots/grafana-recovered.png).
- [x] Loki query filtered by `service="vote"` and `level="error"`: [Grafana Explore](evidence/screenshots/loki-error-query.png), [query JSON](evidence/loki-error-query.json).
- [x] Jaeger trace for a single vote: [trace](evidence/screenshots/jaeger-vote-trace.png).
- [x] Prometheus alert in `firing` state: [alerts page](evidence/screenshots/prometheus-alert-firing.png), [alerts JSON](evidence/prometheus-alerts-firing.json).
- [ ] Slack message from Alertmanager. No real webhook URL was available; the firing alert and payload are captured.
- [x] Error-budget calculation in `docs/SLO.md`.
- [x] Completed postmortem in [`docs/postmortems/`](postmortems/2026-10-26-worker-outage-drill.md).
- [x] Automated worker outage drill with pass/fail checks and [captured evidence](evidence/worker-outage-drill.md).

## Hand-in

- [ ] Forked repository with a clear README. A local Git repository is initialized and committed; creating the fork needs the user's GitHub account.
- [x] Terraform code and one Helm chart.
- [ ] Working GitHub Actions pipeline. The workflow exists and passes the same checks locally; the Actions run needs a GitHub remote.
- [x] Architecture diagram (`docs/ARCHITECTURE.md`).
- [ ] One push builds, scans and deploys. Not executed without a GitHub remote.
- [x] Environment rebuilds from code: local Compose and kind both built from the repository; EKS is not applied.
- [x] No secrets in Git (`git grep` for passwords; `.env` ignored): verified before the first commit.
- [x] Rollback shown live: [evidence](evidence/rollback-demo.log).
- [x] Dashboard exported as code.
- [x] Logging and tracing config.
- [x] SLO document with error-budget policy.
- [x] Blameless postmortem.
- [x] Alert fires during the drill.
- [x] Runbook linked from the alert annotations.
- [x] Demo and Q&A prepared.
- [x] Evidence index: [docs/EVIDENCE.md](EVIDENCE.md).

## Final checks

```powershell
# Tests
python -m pytest -q

# No secrets in tracked files
git grep -n -i -E "password\s*=|secret\s*=|slack_api_url\s*=" -- . ':!*.example' ':!docs/*'

# Compose
docker compose config --quiet

# Helm
helm lint deploy/helm/voting-app
helm template voting-app deploy/helm/voting-app `
  -f deploy/helm/voting-app/values-prod.yaml `
  --set postgresql.auth.existingSecret=voting-db-credentials > $null

# Terraform
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
```
