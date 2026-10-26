# Robot Shop Runbook

This runbook is linked from the `runbook_url` annotation on every Robot Shop
alert. Use the dashboard first, then work down the list.

## Access

```sh
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n observability port-forward svc/jaeger-query 16686:16686
```

- Grafana: http://localhost:3000 (admin / admin in this local demo; use the
  generated secret in a real environment).
- Prometheus: http://localhost:9090
- Jaeger: http://localhost:16686
- Robot Shop web: http://localhost:8090 (kind NodePort 30090)
- Dashboard: **Robot Shop - Service Health**, UID `robot-shop-slo`.

## First five minutes

```sh
kubectl -n robot-shop get pods -o wide
kubectl -n robot-shop get deploy
kubectl -n robot-shop get events --sort-by=.lastTimestamp | tail -40
kubectl -n observability get prometheusrule robot-shop-slo
```

Check the dashboard's request rate, 5xx ratio, p95 and deployment readiness.
Then determine whether the problem is availability, latency or a single service.

## Alert: RobotShopHighErrorRate

**Meaning:** 5xx ratio across web/catalogue/cart/payment is above 5% for 5
minutes.

1. Open the dashboard and identify which service contributes the 5xx.
2. Check the service's logs in Loki:
   ```logql
   {namespace="robot-shop", service="payment"} |= "error"
   ```
   or in the dashboard's **Recent error logs** panel.
3. Check whether the failure is local or a dependency:
   ```sh
   kubectl -n robot-shop logs deploy/payment --tail=100
   kubectl -n robot-shop logs deploy/web --tail=100
   ```
4. Check recent changes:
   ```sh
   helm -n robot-shop history robot-shop
   kubectl -n robot-shop rollout history deploy/payment
   ```
5. If a recent deploy caused it, roll back:
   ```sh
   helm -n robot-shop rollback robot-shop <previous-revision> --wait
   ```
6. If a pod is unhealthy, restart it:
   ```sh
   kubectl -n robot-shop rollout restart deploy/payment
   kubectl -n robot-shop rollout status deploy/payment --timeout=5m
   ```

## Alert: RobotShopHighLatency

**Meaning:** aggregate p95 is above 500 ms for 5 minutes.

1. Use the **p95 latency by service** panel to find the slow service.
2. Trace one slow request in Jaeger: choose service `web.robot-shop`, open a
   trace, and inspect the downstream span with the longest duration.
3. Check `payment` first: it calls an external endpoint and is the usual tail
   latency source. Verify the endpoint is reachable and not rate limiting.
4. Check CPU throttling:
   ```sh
   kubectl -n robot-shop top pods
   kubectl -n robot-shop describe pod -l service=payment
   ```
5. If a single pod is hot, scale the deployment or restart it. If the dependency
   is slow and cannot be fixed, record the impact and consider a temporary
   timeout/fallback.

## Alert: RobotShopServiceDown

**Meaning:** a graded deployment has zero ready replicas for 2 minutes.

```sh
kubectl -n robot-shop describe deploy <service>
kubectl -n robot-shop get pods -l service=<service>
kubectl -n robot-shop describe pod -l service=<service>
kubectl -n robot-shop logs deploy/<service> --tail=150
```

Common causes in this environment:

- OOMKilled: check `kubectl -n robot-shop describe pod` and raise the memory
  limit in the chart values.
- ImagePullBackOff: check the image tag and whether the kind node can pull it.
- CrashLoopBackOff: inspect logs and the previous container log.
- Failed rollout: `helm -n robot-shop rollback robot-shop <revision>`.

After mitigation, confirm readiness:

```sh
kubectl -n robot-shop rollout status deploy/<service> --timeout=5m
kubectl -n robot-shop get pods
```

## Alert: RobotShopPodRestarting

1. Find the restart count and reason:
   ```sh
   kubectl -n robot-shop get pods
   kubectl -n robot-shop describe pod <pod>
   ```
2. Check the previous container logs:
   ```sh
   kubectl -n robot-shop logs <pod> --previous --tail=150
   ```
3. Check node pressure:
   ```sh
   kubectl top nodes
   kubectl -n robot-shop top pods
   ```
4. If the restart is caused by a memory limit, raise it in the chart and upgrade.
   If it is a crash loop, roll back the last change.

## Logs and traces

Loki query examples:

```logql
{namespace="robot-shop"} |= "error"
{namespace="robot-shop", service="web"} |= "Error"
{namespace="robot-shop", service="cart"} | json | level="error"
```

Jaeger: choose `web.robot-shop`, `catalogue.robot-shop`, `cart.robot-shop` or
`payment.robot-shop`; the `load.robot-shop` root span drives the synthetic load.
The trace shows the inbound server span, outbound client spans and the downstream
service spans.

## Rollback

```sh
helm -n robot-shop history robot-shop
helm -n robot-shop rollback robot-shop <revision> --wait --timeout 10m
helm -n robot-shop status robot-shop
```

## Escalation

- If the service is down and the cause is not obvious within 15 minutes, escalate
  to the platform owner.
- If the error budget is exhausted, invoke the error-budget policy: feature
  freeze and reliability work only.
- Record the incident timeline and write a blameless postmortem within two
  business days.
