# Demo Script

This is a 12–15 minute demo. It works with Docker Compose or Kubernetes. Pick
one path; do not try to run both on ports 8080/8081 at the same time.

## Before the demo

- [ ] Docker Desktop (Linux engine) or the kind/EKS cluster is running.
- [ ] `.env` exists with generated credentials.
- [ ] `pwsh ./scripts/load-test.ps1 -Votes 30` has already produced some votes.
- [ ] Grafana/Jaeger are reachable if demonstrating Capstone 2.
- [ ] Terminal font is large enough; close unrelated tabs.
- [ ] Have [ARCHITECTURE.md](ARCHITECTURE.md), [SLO.md](SLO.md), and
      [RUNBOOK.md](RUNBOOK.md) open in editor tabs.

## 1. The problem (1 minute)

Show the architecture diagram.

> “A vote goes into Redis, a worker writes it to PostgreSQL, and the result
> page reads the totals. I own the path from code to a safe deployment, and
> then the ability to see when it breaks.”

Name the four things you will prove: **works**, **automated**, **observable**,
**recoverable**.

## 2. Run it (2 minutes)

Local:

```powershell
pwsh ./scripts/run-local.ps1
```

Kubernetes:

```powershell
pwsh ./scripts/stop-local.ps1
pwsh ./scripts/create-kind-cluster.ps1
```

Open http://localhost:8080. Cast a vote for Cats.

Open http://localhost:8081. The total increments within two seconds because the
result page polls `/api/results`.

## 3. Prove the data path (2 minutes)

Docker Compose:

```powershell
docker compose exec redis redis-cli llen votes
docker compose exec db psql -U voting -d voting `
  -c "select choice, count(*) from votes group by choice;"
docker compose logs --tail=20 worker
```

Kubernetes:

```powershell
kubectl -n voting exec -it statefulset/voting-app-redis -- redis-cli llen votes
kubectl -n voting exec -it statefulset/voting-app-postgresql -- `
  psql -U voting -d voting -c "select choice, count(*) from votes group by choice;"
kubectl -n voting logs deploy/voting-app-worker --tail=20
```

Point out the JSON log line with `vote_id`, `choice`, `service`, and
`trace_id` (when tracing is enabled).

## 4. Show the engineering (3 minutes)

Show the repository, not every file:

- `services/*/Dockerfile`: pinned base, multi-stage, non-root, healthcheck.
- `compose.yaml`: health checks, read-only containers, resource boundaries.
- `infra/terraform/main.tf`: EKS in the default VPC, two-node managed group,
  ECR.
- `deploy/helm/voting-app`: one chart, values for kind/prod, probes, HPA,
  ServiceMonitor, PrometheusRule.
- `.github/workflows/ci-cd.yml`: tests → lint → Trivy → build/push SHA →
  Helm deploy → rollback dispatch.

If you have network access, open the latest successful Actions run and show:

- the test job,
- the Trivy scan,
- the three image tags matching the commit SHA,
- the Helm deployment step.

## 5. Ship a bad release and roll back (2 minutes)

On kind:

```powershell
helm -n voting history voting-app
helm -n voting upgrade voting-app deploy/helm/voting-app `
  --reuse-values --set images.vote.tag=broken-demo `
  --wait --timeout 90s
# It fails. Now recover:
helm -n voting rollback voting-app --wait --timeout 5m
kubectl -n voting rollout status deploy/voting-app-vote
```

Or run `pwsh ./scripts/demo-rollback.ps1`.

Narrate:

> “The bad image never becomes ready. Helm records the failed revision and I
> roll back to the last known-good revision. CI uses `--atomic`, so the same
> recovery happens automatically on a failed deploy.”

Refresh the vote page to prove it is healthy again.

## 6. Observe (3 minutes)

Grafana:

- Request rate, 5xx rate, p95 latency.
- Votes written by the worker.
- Queue depth **and the age of the oldest queued vote** (the freshness signal).
- Scrape targets.

Loki:

```logql
{namespace="voting", service="vote"} | json | level="error"
```

On the local Compose stack, open Grafana → Explore → Loki and use the same
query without the `namespace` label:

```logql
{service="vote"} | json | level="error"
```

Prometheus alert rules are loaded from `observability/local/rules.yaml`, so
`http://localhost:9090/alerts` shows them without Kubernetes.

Jaeger:

- Service: `vote`.
- Find a trace from the last few minutes.
- Open the trace and show the HTTP span plus the Redis span.

## 7. Set the SLO (1 minute)

Show [SLO.md](SLO.md):

- 99.5% availability = 3h 36m of budget in 30 days.
- p95 < 300 ms.
- Freeze features at 100% budget.

Open the alert rule in `deploy/helm/voting-app/templates/prometheusrule.yaml`
and show the runbook URL annotation.

## 8. Incident drill (3–5 minutes)

Use worker failure because it is easy to reverse and does not destroy data.

Kubernetes:

```powershell
kubectl -n voting scale deploy/voting-app-worker --replicas=0
pwsh ./scripts/load-test.ps1 -Votes 100
```

Local Compose (automated, with assertions):

```powershell
pwsh ./scripts/drill-worker-outage.ps1 -Votes 80 -OutageSeconds 60
```

While waiting for the queue alert:

- Show the queue depth climbing in Grafana.
- Show the “Oldest queued vote” panel crossing 60 seconds.
- Show result totals no longer moving.
- Explain the user impact: “Votes are accepted but not counted yet; nothing is
  lost.”
- Talk through first response: check worker pods, logs, DB connectivity.
- Mitigate: `kubectl -n voting scale deploy/voting-app-worker --replicas=1`.
- Show the queue draining and totals catching up.

The 60-second age alert is the fast signal; the 5-minute queue-depth alert is
the backup. Say which one actually fired instead of implying both did. On the
local path, open `http://localhost:9090/alerts` and show
`VotingFreshnessAtRisk` in the `firing` state before restarting the worker.

If the alert has not fired yet, open Alertmanager and show the pending alert,
or trigger `VotingAppPodDown` by deleting a pod and waiting. Do not claim an
alert fired if it did not; say “pending” and explain the `for: 5m` window.

## 9. Close (1 minute)

> “The app works, the pipeline ships it, the dashboard and traces explain it,
> and rollback plus the runbook make it recoverable. The postmortem captures
> what the drill taught us.”

Invite questions. Be ready for:

- **Why Redis?** Decouple the web tier from the database and absorb bursts.
- **What happens if the worker dies?** Votes wait in Redis; the alert fires;
  restart/scale the worker; idempotent UUIDs prevent double counting.
- **What happens if PostgreSQL dies?** The result page degrades, the worker
  retries, and the queue grows until the DB returns.
- **Why not directly write to PostgreSQL?** Latency and failure isolation; the
  queue is also a useful teaching boundary.
- **How do you know the SLO?** Prometheus measures requests; the SLO doc maps
  the target to a budget and an action.
- **What is not production-ready?** Single-instance data stores, no auth, no
  backups, in-memory tracing, and in-cluster secrets. Say this before the
  examiner asks.
