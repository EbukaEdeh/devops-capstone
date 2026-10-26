# Worker outage drill: 80 votes delayed, none lost

> This is a **planned drill**, not an unplanned production incident. It exercises
> the same failure path as a worker crash so the runbook and alerting can be
> tested without losing data.

## Metadata

| Field | Value |
| --- | --- |
| Incident title | Worker outage drill — queue growth and stale results |
| Date / time (UTC) | 2026-10-26 21:09–21:10 |
| Duration | 74 seconds (worker stopped 21:09:13, recovered 21:10:27) |
| Severity | Sev-3 (planned exercise, no failed user requests) |
| Author | Capstone team |
| Reviewers | Self-review during the drill |
| Services affected | `worker` (primary), `vote` and `result` (observed) |
| SLO impact | Availability: 0% of budget. Freshness: 80/80 votes written after 60s in this sample |
| Status | Final (drill) |

## Summary

The worker was deliberately stopped for 74 seconds while 80 votes were cast. The
vote page accepted every ballot, Redis held all 80 messages, and the result page
kept showing the old total of 88. Restarting the worker drained the queue in
about one second; PostgreSQL went from 88 to 168 rows with 168 unique IDs. No
vote was lost or counted twice.

## Impact

- **Users:** the result page showed stale totals for about 64 seconds. Voting
  itself was unaffected: 0 of 80 vote requests failed.
- **Duration:** first vote queued during the load at ~21:09:20 UTC; full recovery
  at 21:10:27 UTC.
- **Requests:** 80 `POST /vote` returned `303`; 80 messages waited in Redis;
  80 rows were written after recovery. No 5xx responses.
- **SLO:** the availability SLI did not burn (no failed user-facing requests).
  The freshness SLO (99% of accepted votes written within 60s) was missed for
  the drill sample: 80/80 votes were older than 60s when written. The 30-day
  budget impact depends on total vote volume and excludes this drill.
- **Data:** none lost, duplicated, or exposed. Row count and distinct ID count
  both ended at 168.

## Detection

- **Locally:** the Compose stack has no Prometheus, so there was no alert. The
  drill script recorded queue depth and failed the run if any vote was lost,
  duplicated, or rejected.
- **In production:** `VotingQueueBacklog` (queue > 50 for 5 minutes) and
  `VotingWorkerStalled` (10 minutes) would **not** fire for a 74-second stall.
  The `VotingFreshnessAtRisk` alert added by this drill (oldest queued vote
  > 60s) becomes eligible at ~21:10:20, seven seconds before recovery. With a
  30-second scrape interval, firing was possible but not guaranteed.
- **Detection gap:** a sub-two-minute worker stall is a dashboard event, not a
  paging event. Queue depth alone is a lagging indicator; the age of the oldest
  vote is the leading indicator tied to the freshness SLO.

## Timeline

| Time (UTC) | Event |
| --- | --- |
| 21:09:08 | Drill started. Baseline: queue 0, database 88 rows, result total 88. |
| 21:09:13 | Worker stopped with `docker compose stop worker`. |
| ~21:09:20 | First of 80 votes queued in Redis. |
| 21:09:23 | Load finished. Queue 80, database 88, result total 88, 0 failed requests. |
| 21:09:23–21:10:23 | Worker held down. Queue stayed at 80; result totals stayed at 88. |
| 21:10:23 | Worker restarted. |
| 21:10:26 | Worker connected to PostgreSQL and began draining. |
| 21:10:27 | Queue 0, database 168 rows, result total 168. Drill passed. |
| 21:10:27 | Drill closed. |

## Root cause

The worker process was intentionally stopped. The application's queue-first
design isolated the failure: `vote` writes to Redis and stayed available, while
`result` reads PostgreSQL and therefore showed stale data. There was no code
defect; the drill confirms the expected at-least-once behavior.

## Contributing factors

- **Single worker replica.** With no second worker, stopping the only consumer
  stopped all progress. The Compose restart policy is `unless-stopped`, so an
  explicit `docker compose stop` is not automatically reversed.
- **Alert windows are longer than the freshness target.** A 60-second SLO
  cannot be protected by a 5-minute alert. The new age metric and alert reduce
  this gap, but only for stalls longer than one scrape interval.
- **No local alert evaluation.** The alert rule behavior was reasoned from the
  PromQL and the drill timeline, not observed in a live Alertmanager.
- **Small sample.** 80 votes is enough to prove the data path, not enough to
  measure the monthly error budget.

## What went well

- The vote path stayed up for the whole outage.
- Redis buffered every vote; the result page degraded honestly by showing stale
  totals instead of errors.
- The worker drained the backlog in about one second after reconnecting.
- UUID primary keys and `ON CONFLICT DO NOTHING` prevented duplicates.
- The drill is now automated and asserts the invariants, so it can be repeated
  during the demo.

## What went poorly

- The result freeze was invisible without watching the dashboard.
- No alert would have fired during a 74-second outage.
- The first manual attempt hit two Windows issues: `pwsh` was not installed and
  the execution policy blocked the script. The runbook now documents the
  Windows PowerShell 5.1 fallback.

## Action items

| ID | Action | Owner | Due date | Type | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Add `vote_queue_oldest_age_seconds` and the `VotingFreshnessAtRisk` alert | Capstone team | 2026-10-26 | Detect | Done |
| 2 | Add an “Oldest queued vote” panel to the Grafana dashboard | Capstone team | 2026-10-26 | Observe | Done |
| 3 | Automate the drill with pass/fail assertions | Capstone team | 2026-10-26 | Mitigate | Done |
| 4 | Document the PowerShell 5.1 fallback for all scripts | Capstone team | 2026-10-26 | Prevent | Done |
| 5 | Run a 5+ minute drill with Prometheus and Alertmanager to capture a real firing alert and Slack message | Capstone team | Before submission | Detect | Open |
| 6 | After 30 days of data, decide whether queue age should page or remain a warning | Capstone team | Post-capstone | Detect | Open |
| 7 | Run two worker replicas in the kind/prod demo to show the queue draining with one replica down | Capstone team | Before demo | Prevent | Open |

## Lessons

- Queue depth answers “is there a backlog?”; queue age answers “are users
  affected?” Alert on the SLO symptom, not only the resource.
- An alert whose `for:` window is longer than the SLO window can only report the
  aftermath. For a 60s freshness target, detection must be measured in seconds.
- At-least-once delivery plus an idempotent consumer turned a 74-second outage
  into a delay instead of data loss. That combination is the real safety net.
- A drill is only evidence if it asserts invariants. Counting votes by hand is
  weaker than a script that fails when the numbers do not reconcile.

## Appendix

- Drill evidence: [worker-outage-drill.md](../evidence/worker-outage-drill.md)
- Reproduce:

```powershell
powershell -ExecutionPolicy Bypass -File ./scripts/drill-worker-outage.ps1 `
  -Votes 80 -OutageSeconds 60 -EvidencePath docs/evidence/worker-outage-drill.md
```

- Worker restart log:

```text
2026-10-26T21:10:26.282Z "message": "worker starting", "metrics_port": 9101
2026-10-26T21:10:26.319Z "message": "database connection ready"
2026-10-26T21:10:26.333Z "message": "vote stored", "vote_id": "5da3cc3c-..."
```

- Verification query (result at drill time):

```sql
select count(*) as rows, count(distinct id) as unique_ids from votes;
-- 168 | 168
```

- Related documents: [RUNBOOK.md](../RUNBOOK.md#queue-backlog),
  [SLO.md](../SLO.md), [DEMO.md](../DEMO.md#8-incident-drill-35-minutes)

## Blameless statement

This review focuses on system conditions and safeguards. We do not blame
individuals for errors made while acting with good intent and the information
available at the time.
