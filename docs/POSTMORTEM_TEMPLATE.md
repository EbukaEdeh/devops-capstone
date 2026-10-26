# Blameless Postmortem Template

> Copy this file to `docs/postmortems/YYYY-MM-DD-short-title.md`. Replace every
> placeholder. Blameless means we assume people acted with good intent and the
> system allowed the error; we fix systems and guards, not individuals.

## Metadata

| Field | Value |
| --- | --- |
| Incident title | |
| Date / time (UTC) | |
| Duration | |
| Severity | Sev-1 / Sev-2 / Sev-3 |
| Author | |
| Reviewers | |
| Services affected | vote / result / worker / database / cluster |
| SLO impact | % of monthly error budget |
| Status | Draft / Reviewed |

## Summary

Two or three sentences a non-engineer can understand. State what users saw,
for how long, and how it was fixed. Do not start with the root cause.

## Impact

- **Users:** who was affected and what could they not do?
- **Duration:** first user impact to full recovery (UTC).
- **Requests:** failed requests, slow requests, queued votes, votes not written.
- **SLO:** availability and latency budget consumed.
- **Data:** any lost, duplicated, or exposed data? If none, say so explicitly.

## Detection

- How was the incident detected? Alert, dashboard, user report, deploy failure?
- Time from first impact to detection.
- Was an alert missing or too slow? Link the alert/runbook.

## Timeline

Use UTC. Include both facts and decisions.

| Time | Event |
| --- | --- |
| 00:00 | Change deployed / failure introduced |
| 00:00 | First user impact |
| 00:00 | Alert fired |
| 00:00 | On-call acknowledged |
| 00:00 | Mitigation started |
| 00:00 | Service recovered |
| 00:00 | Incident closed |

## Root cause

The technical cause. Be specific: a configuration value, image tag, dependency
failure, resource limit, or code path. Link the failing commit, manifest, or
query.

## Contributing factors

- What made the failure possible?
- What made detection slow?
- What made recovery slow?
- Which guardrail was missing (test, probe, limit, alert, policy)?

## What went well

- Fast rollback, useful dashboard, clear alert, good communication, etc.

## What went poorly

- Ambiguous ownership, missing metric, noisy alert, undocumented dependency.

## Action items

| ID | Action | Owner | Due date | Type | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Add a regression test for the failing path | | | Prevent | Open |
| 2 | Add/adjust alert and runbook link | | | Detect | Open |
| 3 | Improve rollback or automation | | | Mitigate | Open |
| 4 | Update dashboard/SLO | | | Observe | Open |

Types: Prevent, Detect, Mitigate, Observe. Every action needs an owner and a
date. “Be more careful” is not an action.

## Lessons

What will this team do differently next time? What did we learn about the
system? Keep it short and concrete.

## Appendix

- Grafana snapshot link
- Jaeger trace IDs
- Log queries and excerpts
- CI run / Helm revision
- Related incidents

## Blameless statement

This review focuses on system conditions and safeguards. We do not blame
individuals for errors made while acting with good intent and the information
available at the time.
