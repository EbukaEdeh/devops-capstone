# Error Budget Policy — Robot Shop

**One page. Owner: Capstone 2 team. Review: monthly or after an incident.**

## Policy

Robot Shop targets **99.5% availability** over a rolling 30-day window. The
remaining **0.5%** is the error budget: about **216 minutes** of failed requests.
The budget exists to make reliability trade-offs explicit, not to punish the
team for every error.

## Budget states and required actions

| Budget consumed | State | Required action |
| --- | --- | --- |
| 0–25% | Healthy | Normal delivery. Keep the dashboard and alerts green. |
| 25–50% | Watch | Review the top error source at the next team sync. Add a ticket for the largest contributor. |
| 50–75% | At risk | Freeze risky production changes. Only reliability fixes, rollbacks and small, well-tested changes are allowed. |
| 75–100% | Critical | Incident review required. The team writes an action plan with owners and dates before resuming feature work. |
| 100% | Exhausted | Feature freeze. All engineering time goes to restoring the SLO. Resume only after a full week inside budget. |

## Incident triggers

The following automatically start an incident review:

- `RobotShopHighErrorRate` fires for more than 10 minutes.
- `RobotShopServiceDown` fires at all.
- The 30-day availability SLO is projected to miss before the end of the window.
- A single change consumes more than 25% of the monthly budget.

## Incident process

1. **Mitigate first.** Roll back, scale up, restart, or fail over before doing
   deep root-cause analysis.
2. **Record the timeline.** Note detection time, mitigation time, recovery time
   and customer impact.
3. **Write a blameless postmortem** within two business days. Focus on system
   conditions and missing safeguards, not individual blame.
4. **Create owned actions.** Every action has one owner and a due date.
5. **Verify the fix.** Add or update an alert, dashboard panel or test that would
   catch the failure earlier next time.

## Exceptions

Planned maintenance, a cloud/provider outage outside our control, and explicitly
approved load tests are excluded from the budget. Exclusions must be recorded in
the incident or change ticket before the window closes.

## Communication

- Alerts route to the on-call channel through Alertmanager.
- The current status is always visible on the **Robot Shop - Service Health**
  dashboard (UID `robot-shop-slo`).
- The runbook is linked from every alert annotation.
