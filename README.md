# Voting App — DevOps Capstone

A complete, runnable implementation of the two beginner DevOps capstones:

1. **Ship it** — containerize the Voting App, build a Kubernetes cluster with Terraform, add GitHub Actions CI/CD, and deploy/roll back with Helm.
2. **Keep it running** — instrument the app with Prometheus metrics and OpenTelemetry traces, ship logs to Loki, define an SLO, and practise an incident.

The app itself is intentionally small. The engineering around it is the point.

```
Browser ──► vote (Flask) ──► Redis queue ──► worker (Python) ──► PostgreSQL
                                                                     │
Browser ◄── result (Flask) ◄──────────── live totals ◄───────────────┘

Prometheus ◄── /metrics from vote, result, worker
Fluent Bit ──► Loki (structured JSON logs)
OpenTelemetry SDK ──► Collector ──► Jaeger
```

## What is in the box

| Area | Implementation |
| --- | --- |
| App | `vote`, `result`, `worker`, Redis 7, PostgreSQL 16 |
| Local runtime | Docker Compose, health checks, read-only containers, non-root users |
| Tests | 19 pytest unit tests, fakeredis, no live dependencies required |
| Infrastructure | Terraform module for EKS in the default VPC, ECR repositories |
| Packaging | Helm chart with probes, resources, security contexts, HPA, PDB-free rolling updates, optional ingress and NetworkPolicy |
| CI/CD | GitHub Actions: tests → lint → Trivy → build/push by commit SHA → Helm deploy → rollback workflow |
| Observability | Prometheus metrics (requests, queue depth, oldest-vote age), Grafana dashboard as code, kube-prometheus-stack values, Fluent Bit → Loki, OTel → Jaeger |
| Reliability | SLO, error-budget policy, alert rules, runbook, automated outage drill, blameless postmortem |
| Demo | A deliberate bad release, Helm rollback, local and Kubernetes runbooks |

## Quick start (Docker)

Requirements: Docker Desktop with the **Linux containers** engine running.

```powershell
pwsh ./scripts/run-local.ps1
```

or on Linux/macOS:

```bash
./scripts/run-local.sh
```

The script creates a local `.env` with random credentials (never committed), builds three images, starts the stack, and waits for readiness.

> PowerShell 7 (`pwsh`) is recommended. The scripts also run on Windows PowerShell 5.1:
> `powershell -ExecutionPolicy Bypass -File ./scripts/run-local.ps1`. On Linux/macOS use `./scripts/run-local.sh`.

| URL | What |
| --- | --- |
| http://localhost:8080 | Cast a vote |
| http://localhost:8081 | Live result board |
| http://localhost:3000 | Grafana (with `-WithObservability`) |
| http://localhost:16686 | Jaeger (with `-WithObservability`) |
| http://localhost:9090 | Prometheus; `/alerts` shows local rules (with `-WithObservability`) |
| http://localhost:3100 | Loki API, queried from Grafana Explore (with `-WithObservability`) |

Cast some votes, then open the result page. It refreshes every two seconds.

To run the local observability stack too:

```powershell
pwsh ./scripts/run-local.ps1 -WithObservability
```

Grafana credentials are `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` in `.env`.
The local stack also runs Loki and Promtail so the Compose demo has searchable
structured logs, and Prometheus loads `observability/local/rules.yaml` so the
same freshness and queue alerts can be demonstrated without Kubernetes.

Useful commands:

```powershell
pwsh ./scripts/load-test.ps1 -Votes 100
docker compose ps
docker compose logs -f worker
docker compose exec db psql -U voting -d voting -c "select choice, count(*) from votes group by choice;"
pwsh ./scripts/stop-local.ps1
```

Prove the queue is durable during a worker outage:

```powershell
pwsh ./scripts/drill-worker-outage.ps1 -Votes 80 -OutageSeconds 60
```

The script stops the worker, casts votes, checks that the queue grows while the
database does not, restarts the worker, and verifies that every vote is written
exactly once. See [the drill postmortem](docs/postmortems/2026-10-26-worker-outage-drill.md).

## Capstone 1 — step by step

### 1. Run it locally

```powershell
pwsh ./scripts/run-local.ps1
pwsh ./scripts/load-test.ps1 -Votes 50
```

The vote page writes to Redis. The worker pops messages and writes idempotently to PostgreSQL. The result page reads aggregates.

### 2. Containerize it safely

- Exact base tags in each `Dockerfile`.
- Multi-stage builds; only the virtualenv and app files reach the final image.
- Non-root UID `10001`, read-only root filesystem, `no-new-privileges`, all Linux capabilities dropped.
- Small `.dockerignore`; secrets never enter the build context.
- One gunicorn worker with threads per pod so the Prometheus registry is accurate; scale with replicas instead.

### 3. Create a cluster with Terraform

The Terraform stack creates an EKS cluster in the **default VPC**:

```powershell
cd infra/terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan

# Writes a kubeconfig entry
terraform output -raw configure_kubectl
```

Then run the printed command, for example:

```powershell
aws eks update-kubeconfig --region us-east-1 --name voting-capstone
```

Destroy and rebuild to prove it is code:

```powershell
terraform destroy
terraform apply
```

> EKS is not free. The default node group is two `t3.small` instances. Set a budget alert before applying.

### 4. Automate with GitHub Actions

`.github/workflows/ci-cd.yml` runs on every push and pull request:

1. `pytest`
2. `terraform fmt` / `validate`, `helm lint` / render
3. Trivy secret scan and image scan
4. Build and push all three images to GHCR tagged with the **commit SHA**
5. Deploy to EKS with Helm when the push is on `main`

Configure the repository:

**Variables** (Settings → Secrets and variables → Actions → Variables)

| Name | Example |
| --- | --- |
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-voting-deploy` |
| `AWS_REGION` | `us-east-1` |
| `EKS_CLUSTER_NAME` | `voting-capstone` |
| `APP_URL` | `https://vote.example.com` (optional) |

**Secrets**

| Name | Purpose |
| --- | --- |
| `POSTGRES_PASSWORD` | Password for the in-cluster PostgreSQL secret |
| `GITHUB_TOKEN` | Automatic; used to push to GHCR |

The AWS role must trust GitHub's OIDC provider (`token.actions.githubusercontent.com`) and be allowed to describe the EKS cluster and call `eks:AccessKubernetesApi`. Use an IAM role scoped to this repository and `main` branch.

A manual `workflow_dispatch` can deploy the current `main` SHA or roll back. Empty rollback revision means “previous revision”.

### 5. Deploy and roll back with Helm

Manual deployment after building images:

```powershell
$password = Read-Host -AsSecureString
# Create the secret out-of-band; it is never rendered by the chart.
kubectl create namespace voting --dry-run=client -o yaml | kubectl apply -f -
kubectl -n voting create secret generic voting-db-credentials `
  --from-literal=password="$password"

helm upgrade --install voting-app deploy/helm/voting-app `
  --namespace voting `
  --set images.vote.repository=ghcr.io/YOU/voting-app/vote `
  --set images.vote.tag=sha-abc1234 `
  --set images.result.repository=ghcr.io/YOU/voting-app/result `
  --set images.result.tag=sha-abc1234 `
  --set images.worker.repository=ghcr.io/YOU/voting-app/worker `
  --set images.worker.tag=sha-abc1234 `
  --wait --timeout 5m
```

A local Kubernetes demo without AWS:

```powershell
pwsh ./scripts/stop-local.ps1
pwsh ./scripts/create-kind-cluster.ps1
```

This builds the images, loads them into a kind cluster, creates the DB secret from `.env`, and installs the chart with `values-kind.yaml`. UI: http://localhost:8080 and http://localhost:8081.

Rollback demo:

```powershell
pwsh ./scripts/demo-rollback.ps1
```

The script upgrades to a deliberately broken image tag, waits for failure, runs `helm rollback`, and verifies the rollout. The equivalent manual commands are in [docs/DEMO.md](docs/DEMO.md).

## Capstone 2 — run it, watch it, trust it

The full sequence is in [docs/DEMO.md](docs/DEMO.md). In short:

```powershell
# 1. Namespace and secrets
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability create secret generic grafana-admin-credentials `
  --from-literal=admin-user=admin --from-literal=admin-password='<strong-password>'
kubectl -n observability create secret generic slack-webhook `
  --from-literal=slack_api_url='https://hooks.slack.com/services/...'

# 2. Metrics stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace observability `
  --values observability/kube-prometheus-stack-values.yaml

# 3. Tracing
kubectl apply -f observability/jaeger.yaml
kubectl apply -f observability/otel-collector.yaml

# 4. Logs
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki grafana/loki -n observability `
  --values observability/loki-values.yaml
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit -n observability `
  --values observability/fluent-bit-values.yaml

# 5. Dashboard as code
kubectl -n observability create configmap voting-app-dashboard `
  --from-file=voting-app.json=observability/local/grafana/dashboards/voting-app.json
kubectl -n observability label configmap voting-app-dashboard grafana_dashboard=1

# 6. Redeploy app with tracing, ServiceMonitor, alerts and HPA
helm upgrade voting-app deploy/helm/voting-app -n voting `
  --values deploy/helm/voting-app/values-prod.yaml --reuse-values --wait
```

Port-forward Grafana, Jaeger and Alertmanager:

```powershell
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n observability port-forward svc/jaeger-query 16686:16686
kubectl -n observability port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```

What “done” looks like:

- Grafana shows request rate, 5xx rate, p95 latency, votes written, queue depth, oldest-vote age and scrape health from `observability/local/grafana/dashboards/voting-app.json`.
- Jaeger shows a trace for the `vote` service after one ballot. Logs include `trace_id` and `span_id`.
- Loki query `{namespace="voting", service="vote"} | json | level="error"` returns searchable logs by service and level.
- A worker/database incident produces an alert in Slack.
- [docs/SLO.md](docs/SLO.md), [docs/RUNBOOK.md](docs/RUNBOOK.md) and [docs/POSTMORTEM_TEMPLATE.md](docs/POSTMORTEM_TEMPLATE.md) are complete and linked from the alert annotations.

## Repository layout

```
services/            vote, result and worker source + Dockerfiles
shared/voting_common/ logging, metrics, DB, vote choices
tests/               unit tests
deploy/helm/         one chart, default/kind/prod values
deploy/kind-config.yaml
infra/terraform/     EKS in the default VPC + ECR
observability/       Prometheus, Grafana, Loki, Fluent Bit, OTel, Jaeger; local rules and Promtail
scripts/             local run, kind, load test, rollback, outage drill
docs/                architecture, SLO, runbook, postmortem, demo, checklist
.github/workflows/   CI/CD pipeline
compose.yaml         local app stack
compose.observability.yaml
```

## Security decisions

- No credentials in Git. `.env` is ignored; a Kubernetes Secret is created out-of-band by CI or the operator.
- Containers run as non-root, read-only, with capabilities dropped.
- The Helm chart can enforce NetworkPolicies that only allow `result`/`worker` → PostgreSQL and `vote`/`worker` → Redis.
- Image tags are immutable commit SHAs. ECR can enforce immutability; GHCR tags are unique by SHA.
- Trivy scans the repository for secrets and every image for fixable critical CVEs.
- The app accepts only the two known vote choices; the worker validates message shape and uses a UUID primary key for idempotency.

## Known limitations / good next steps

- Redis is a single AOF-backed StatefulSet and PostgreSQL a single instance. Production would use managed services (ElastiCache, RDS/Aurora) or operators and backups.
- The queue is at-least-once via retry on database failure; a production worker could use Redis Streams consumer groups.
- Grafana dashboard is provisioned as a ConfigMap; Terraform-managed Grafana alerting is a stretch goal.
- Add remote Terraform state, Argo CD, autoscaling policies tuned to real traffic, and Litmus/Chaos Mesh drills.
- Runbook links in alert annotations use a placeholder GitHub org. Replace `your-org` when you fork.
- Slack delivery, a GitHub Actions run, and a real EKS apply need external accounts or paid resources. The local evidence is indexed in [docs/EVIDENCE.md](docs/EVIDENCE.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Demo script](docs/DEMO.md)
- [SLO and error-budget policy](docs/SLO.md)
- [Runbook](docs/RUNBOOK.md)
- [Blameless postmortem template](docs/POSTMORTEM_TEMPLATE.md)
- [Worker outage drill postmortem](docs/postmortems/2026-10-26-worker-outage-drill.md)
- [Evidence index](docs/EVIDENCE.md)
- [Capstone checklist](docs/CAPSTONE_CHECKLIST.md)

## License

The application code in this repository is provided for the capstone exercise. Third-party container images keep their upstream licenses.
