# Runbook

**Service:** Voting App
**Namespaces:** `voting` and `observability`
**Escalation:** on-call engineer → team lead → platform owner

All commands assume a kubeconfig for the target cluster. Replace `voting-app` if the Helm release has another name.

## First five minutes

1. Acknowledge the alert in Slack.
2. Open the Grafana dashboard **Voting App — Service Health**.
3. Check the fastest signal:

```bash
kubectl -n voting get pods
kubectl -n voting get events --sort-by=.lastTimestamp | tail -30
kubectl -n voting rollout status deploy/voting-app-vote
kubectl -n voting rollout status deploy/voting-app-result
kubectl -n voting rollout status deploy/voting-app-worker
```

4. Determine whether this is a **new deployment**, a **dependency**, or **traffic**:

```bash
helm -n voting history voting-app
kubectl -n voting describe deploy voting-app-vote
kubectl -n voting logs deploy/voting-app-worker --tail=100
```

5. If the incident started within 30 minutes of a release, roll back first, investigate second:

```bash
helm -n voting rollback voting-app --wait --timeout 5m
```

## Pod down

**Alert:** `VotingAppPodDown`

```bash
kubectl -n voting get pods -o wide
kubectl -n voting describe pod <pod>
kubectl -n voting logs <pod> --previous --tail=100
```

Checks:

- Is the node ready? `kubectl get nodes`
- Is the image pull failing? Look for `ErrImagePull` / `ImagePullBackOff`.
- Is the readiness probe failing? `kubectl -n voting port-forward <pod> 8080:8080` then `curl localhost:8080/readyz`.
- Is it a resource limit? `kubectl -n voting top pods`.

Mitigation: fix the image/tag or configuration, or `helm rollback`. Kubernetes replaces the pod automatically.

## High error rate

**Alert:** `VotingAppHighErrorRate` (5xx > 5% for 5 minutes)

1. Which service? Grafana → “5xx rate by service”.
2. Check dependency health:
   - vote: Redis
   - result: PostgreSQL
   - worker: PostgreSQL / Redis
3. Search logs:

```bash
kubectl -n voting logs deploy/voting-app-vote --tail=200 | grep -i error
```

Loki query:

```logql
{namespace="voting", service="vote"} | json | level="error"
```

4. If error rate started with a release, roll back.
5. If a dependency is down, restore it; the app reconnects without a restart in most cases.

## High latency

**Alert:** `VotingAppHighLatency` (p95 > 500 ms for 10 minutes)

- Check PostgreSQL connections and slow queries:

```bash
kubectl -n voting exec -it statefulset/voting-app-postgresql -- \
  psql -U voting -d voting -c "select count(*), max(created_at) from votes;"
```

- Check Redis latency:

```bash
kubectl -n voting exec -it statefulset/voting-app-redis -- redis-cli --latency
```

- Check CPU throttling: Grafana → Pod CPU / `container_cpu_cfs_throttled_periods_total`.
- HPA should add replicas. If it does not, inspect `kubectl -n voting get hpa`.
- Scale manually as a temporary mitigation:

```bash
kubectl -n voting scale deploy/voting-app-vote --replicas=4
```

## Queue backlog

**Alerts:** `VotingQueueBacklog` (queue > 50 for 5 minutes) and
`VotingFreshnessAtRisk` (oldest vote age > 60 seconds)

```bash
kubectl -n voting logs deploy/voting-app-worker --tail=100
kubectl -n voting get pods -l app.kubernetes.io/component=worker
kubectl -n voting exec -it statefulset/voting-app-redis -- redis-cli llen votes
```

The age alert is the earlier signal: it fires when a vote has waited longer than
the 60-second freshness target, even if the queue is short. Check it in
Prometheus:

```promql
max(vote_queue_oldest_age_seconds{namespace="voting"})
```

Common causes:

- Worker not running / crash loop
- PostgreSQL unavailable, so the worker requeues messages
- Worker CPU limit too low

Mitigation:

```bash
kubectl -n voting scale deploy/voting-app-worker --replicas=2
```

The queue drains automatically. Confirm with `llen votes` trending down and the Grafana “Votes written” panel.

## Worker stalled

**Alert:** `VotingWorkerStalled` (queue > 0, processed rate = 0 for 10 minutes)

1. Inspect worker logs for database authentication or connection errors.
2. Verify the DB secret exists and has the right key:

```bash
kubectl -n voting get secret voting-db-credentials
kubectl -n voting exec deploy/voting-app-worker -- env | grep POSTGRES
```

3. Verify the worker can resolve the database:

```bash
kubectl -n voting exec deploy/voting-app-worker -- \
  python -c "import socket; print(socket.gethostbyname('voting-app-postgresql'))"
```

4. Check the dead-letter queue for malformed messages:

```bash
kubectl -n voting exec -it statefulset/voting-app-redis -- redis-cli lrange votes:dead 0 -1
```

## Database unavailable

Symptoms: result 503, worker retries, `result_db_up=0`.

```bash
kubectl -n voting get statefulset voting-app-postgresql
kubectl -n voting logs statefulset/voting-app-postgresql --tail=100
kubectl -n voting describe pvc data-voting-app-postgresql-0
```

- If the PVC is full, expand it (storage class must allow expansion).
- If PostgreSQL is crash-looping, check disk pressure and the password secret.
- Do not delete the PVC: it contains the votes.

## Bad release / rollback

```bash
helm -n voting history voting-app
helm -n voting rollback voting-app --wait --timeout 5m
kubectl -n voting rollout status deploy/voting-app-vote
```

The CI pipeline uses `helm upgrade --install --atomic`; a failed deploy rolls back automatically. The manual rollback path is still required for a release that passes readiness but behaves incorrectly.

After rollback:

1. Confirm the dashboard is green.
2. Capture the failing image tag and logs for the postmortem.
3. Fix forward on a branch, never by editing production directly.

## Logs and traces

Grafana → Explore → Loki:

```logql
{namespace="voting"} | json | level="error"
{namespace="voting", service="vote"} | json | choice="cats"
{namespace="voting"} | json | trace_id="<id>"
```

Jaeger: select service `vote`, `result` or `worker`, then find the trace. Logs contain `trace_id` and `span_id`, so you can jump from a log line to the trace.

## Incident drill

The instructor (or you) breaks something. The expected sequence is:

1. **Mitigate first**: rollback or scale/restore the broken dependency.
2. **Then diagnose**: logs, metrics, traces, recent changes.
3. **Write the postmortem** within 24 hours using [POSTMORTEM_TEMPLATE.md](POSTMORTEM_TEMPLATE.md).
4. Link the postmortem and the drill evidence in the submission.

A safe drill that does not destroy data:

```bash
kubectl -n voting scale deploy/voting-app-worker --replicas=0
pwsh ./scripts/load-test.ps1 -Votes 100
# Alert fires after the queue backlog persists for 5 minutes.
kubectl -n voting scale deploy/voting-app-worker --replicas=1
```

On the local Compose stack the same drill is automated and asserts that no vote
is lost or duplicated:

```powershell
pwsh ./scripts/drill-worker-outage.ps1 -Votes 80 -OutageSeconds 60
```

It stops the worker, casts votes, verifies that the queue grows while the
database does not, restarts the worker, and checks the final counts. See the
[drill postmortem](postmortems/2026-10-26-worker-outage-drill.md) for measured results.

## Useful queries

```promql
# requests per second by service
sum by (service) (rate(http_requests_total[5m]))

# 5xx ratio
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
clamp_min(sum(rate(http_requests_total[5m])), 0.001)

# p95 by route
histogram_quantile(0.95, sum by (le, service, route) (rate(http_request_duration_seconds_bucket[5m])))

# queue depth
max(vote_queue_depth)

# age of the oldest queued vote (freshness SLO)
max(vote_queue_oldest_age_seconds)

# worker throughput
sum(rate(votes_processed_total[5m]))
```
