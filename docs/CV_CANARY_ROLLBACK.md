# Harness Continuous Verification - Canary Rollback Demo

This document explains how to use the built-in chaos endpoints to demonstrate Harness Continuous Verification (CV) detecting an unhealthy canary deployment and triggering an automatic rollback.

## Overview

The application includes API endpoints that can be triggered by a Harness pipeline to inject chaos (latency, errors) into the canary deployment. This causes Prometheus metrics to degrade, which Harness CV detects and uses to trigger an automatic rollback.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Harness Pipeline                             │
├─────────────────────────────────────────────────────────────────┤
│  1. Deploy Canary (10% traffic)                                  │
│  2. Run CV Verification Step                                     │
│  3. [Optional] Trigger Chaos via HTTP Step                       │
│  4. CV Detects Degraded Metrics                                  │
│  5. Automatic Rollback                                           │
└─────────────────────────────────────────────────────────────────┘
         │                                    ▲
         │ Deploy                             │ Metrics
         ▼                                    │
┌─────────────────┐                  ┌─────────────────┐
│  Canary Pods    │ ──── scrape ──── │   Prometheus    │
│  (chaos active) │                  │                 │
└─────────────────┘                  └─────────────────┘
```

## Chaos Injection Endpoints

### 1. Enable Chaos (Generic)
```bash
curl -X POST "http://<canary-service>/api/chaos/enable?latencyMs=500&errorRate=0.3&durationSeconds=120"
```

**Parameters:**
- `latencyMs` - Latency to inject on each request (default: 500ms)
- `errorRate` - Probability of returning 500 error (default: 0.3 = 30%)
- `durationSeconds` - How long chaos remains active (default: 60s)

### 2. Degrade Canary (Targeted)
```bash
curl -X POST "http://<canary-service>/api/chaos/degrade-canary?durationSeconds=120"
```

This endpoint:
- Only activates if `DEPLOYMENT_VARIANT=canary`
- Injects aggressive chaos (800ms latency, 50% error rate)
- Immediately generates error metrics for CV to detect

### 3. Check Chaos Status
```bash
curl "http://<canary-service>/api/chaos/status"
```

### 4. Disable Chaos
```bash
curl -X POST "http://<canary-service>/api/chaos/disable"
```

## Prometheus Metrics for CV

The following metrics will degrade when chaos is active:

| Metric | Normal | During Chaos | CV Detection |
|--------|--------|--------------|--------------|
| `app_errors_total{type="cv_chaos_injected"}` | 0 | Increasing | Error rate spike |
| `app_chaos_events_total{type="cv_error"}` | 0 | Increasing | Anomaly detection |
| `app_processing_duration_seconds` | ~50ms | ~800ms+ | Latency increase |
| `http_server_requests_seconds` | Low | High | Response time |

## Harness Pipeline Configuration

### Option 1: Shell Script Step (After Canary Deploy)

Add a Shell Script step after your canary deployment to trigger chaos:

```yaml
- step:
    type: ShellScript
    name: Trigger Canary Chaos
    identifier: trigger_canary_chaos
    spec:
      shell: Bash
      source:
        type: Inline
        spec:
          script: |
            # Get canary service endpoint
            CANARY_URL="http://<canary-service-url>"
            
            # Trigger chaos on canary
            curl -X POST "${CANARY_URL}/api/chaos/degrade-canary?durationSeconds=180"
            
            echo "Chaos injected - CV should detect degradation"
      timeout: 30s
```

### Option 2: HTTP Step

```yaml
- step:
    type: Http
    name: Inject Canary Chaos
    identifier: inject_canary_chaos
    spec:
      url: http://<canary-service>/api/chaos/degrade-canary
      method: POST
      headers: []
      requestBody: ""
      assertion: <+httpResponseCode> == 200
      timeout: 30s
```

### Option 3: Harness Chaos Engineering Integration

For more sophisticated chaos, use Harness Chaos Engineering to inject infrastructure-level faults:

```yaml
- step:
    type: ChaosExperiment
    name: Canary Pod Stress
    identifier: canary_pod_stress
    spec:
      experimentRef: canary-cpu-stress
      expectedResilienceScore: 50
```

## Complete Pipeline Example

```yaml
pipeline:
  name: Canary Deployment with CV Rollback Demo
  identifier: canary_cv_rollback_demo
  stages:
    - stage:
        name: Deploy Canary
        identifier: deploy_canary
        type: Deployment
        spec:
          deploymentType: Kubernetes
          service:
            serviceRef: harness_demo_app
          environment:
            environmentRef: production
          execution:
            steps:
              # Deploy canary with 10% traffic
              - step:
                  type: K8sCanaryDeploy
                  name: Canary Deployment
                  identifier: canary_deploy
                  spec:
                    skipDryRun: false
                    instanceSelection:
                      type: Count
                      spec:
                        count: 1
                    
              # Trigger chaos on canary (for demo purposes)
              - step:
                  type: Http
                  name: Trigger Chaos for Demo
                  identifier: trigger_chaos
                  spec:
                    url: http://harness-demo-canary:8080/api/chaos/degrade-canary
                    method: POST
                    timeout: 30s
                    
              # Continuous Verification - will detect degraded metrics
              - step:
                  type: Verify
                  name: Verify Canary Health
                  identifier: verify_canary
                  spec:
                    type: Canary
                    monitoredService:
                      type: Default
                      spec: {}
                    spec:
                      sensitivity: HIGH
                      duration: 5m
                      deploymentTag: <+serviceConfig.artifacts.primary.tag>
                    failureStrategies:
                      - onFailure:
                          errors:
                            - Verification
                          action:
                            type: ManualIntervention
                            spec:
                              timeout: 2h
                              onTimeout:
                                action:
                                  type: Rollback
                                  
              # If CV passes, proceed with full rollout
              - step:
                  type: K8sCanaryDelete
                  name: Delete Canary
                  identifier: delete_canary
                  
              - step:
                  type: K8sRollingDeploy
                  name: Rolling Deployment
                  identifier: rolling_deploy
                  
            rollbackSteps:
              - step:
                  type: K8sCanaryDelete
                  name: Canary Rollback
                  identifier: canary_rollback
```

## Kubernetes Deployment for Canary

Deploy the canary with the appropriate environment variables:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harness-demo-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harness-demo
      variant: canary
  template:
    metadata:
      labels:
        app: harness-demo
        variant: canary
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      containers:
        - name: app
          image: harness-demo-app:2.0.0
          env:
            - name: DEPLOYMENT_VARIANT
              value: "canary"
            - name: VARIANT_COLOR
              value: "#F59E0B"
            - name: APP_VERSION
              value: "2.0.0"
          ports:
            - containerPort: 8080
```

## Prometheus ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harness-demo-monitor
spec:
  selector:
    matchLabels:
      app: harness-demo
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
```

## Expected Demo Flow

1. **Deploy Canary** - Pipeline deploys canary with `DEPLOYMENT_VARIANT=canary`
2. **Trigger Chaos** - HTTP step calls `/api/chaos/degrade-canary`
3. **Metrics Degrade** - Error rate spikes, latency increases
4. **CV Detects** - Harness CV sees anomalies in Prometheus metrics
5. **Rollback Triggered** - CV fails, pipeline executes rollback steps
6. **Canary Deleted** - Traffic returns to stable deployment

---

## How Harness Tracks K8s Deployment State (Under the Hood)

This section is useful for SEs explaining **why** Harness B/G and canary work the way they do, and why switching strategies on the same namespace requires a cleanup step.

### The Release ConfigMap

Every time Harness deploys to a Kubernetes namespace, it creates (or updates) a `ConfigMap` named:

```
release-<releaseName>
```

where `releaseName` is configured in the Harness infrastructure definition (defaults to the service name, e.g., `release-parsondemoapp`).

This ConfigMap acts as Harness's **"source of truth"** for what it owns in that namespace. It records:
- Which Kubernetes resources were deployed (Deployments, Services, ConfigMaps, etc.)
- The **deployment strategy type** used (BlueGreen, Canary, Rolling)
- The previous and current release state for rollback

```bash
# Inspect the release tracking ConfigMap
kubectl get configmap release-<releaseName> -n <namespace> -o yaml
```

### Strategy-Specific "Leave Behinds"

Each deployment strategy leaves a distinct set of K8s resources behind after it completes:

| Strategy | Resources Left in Cluster | Purpose |
|---|---|---|
| **Blue/Green** | `<name>-service` (primary), `<name>-service-stage` (stage), pods labeled `harness.io/color: blue` or `green` | Stage service receives new version traffic before swap; color label tracks which deployment is active |
| **Canary** | `<name>-service` (stable), `<name>-deployment-canary` (canary pods) labeled `harness.io/track: canary` | Canary deployment runs alongside stable; Harness counts pods per track to calculate traffic % |
| **Rolling** | `<name>-service` (standard), updated Deployment | Standard K8s rolling update — no additional Harness-managed resources |

### What Happens When You Switch Strategies

When you run **Strategy A** then switch to **Strategy B** on the same namespace:

1. Strategy A's resources and ConfigMap entry persist in the cluster
2. Strategy B reads the release ConfigMap and sees it was last managed by Strategy A
3. Strategy B tries to create or claim ownership of a Service that already exists under a different strategy type → **conflict**

The most common error:
```
Found conflicting service [<name>-service] in the cluster
```

This means Harness found the primary service but can't reconcile it with the expected strategy ownership in the release ConfigMap.

### The Fix: Reset Strategy State Before Each Deploy

To safely switch between strategies on the same namespace, delete the strategy-owned resources before deploying:

```bash
NAMESPACE="<your-namespace>"
RELEASE="<your-release-name>"   # e.g. parsondemoapp

# 1. Remove Harness release ownership tracking (root cause of all cross-strategy conflicts)
kubectl delete configmap "release-${RELEASE}" -n $NAMESPACE --ignore-not-found=true

# 2. Remove primary service — B/G requires harness.io/color in the selector, which only
#    gets added when Harness creates the service fresh under B/G ownership. A service
#    created by rolling/canary won't have this label and will cause a conflict error.
kubectl delete service "${RELEASE}-service" -n $NAMESPACE --ignore-not-found=true

# 3. Remove B/G stage service (blocks canary/rolling from starting after a B/G run)
kubectl delete service "${RELEASE}-service-stage" -n $NAMESPACE --ignore-not-found=true

# 4. Remove canary deployment (blocks B/G/rolling from starting after a canary run)
kubectl delete deployment "${RELEASE}-deployment-canary" -n $NAMESPACE --ignore-not-found=true
```

All commands use `--ignore-not-found=true` so they are safe to run regardless of what strategy ran previously.

In the `parson_k8s_strategy_deploy` pipeline, this is implemented as a **`Reset Strategy State` ShellScript step** — the first step in each of the three strategy stages — so any strategy can be run after any other without manual cleanup.

### Visual: K8s Resources Per Strategy

```
After Blue/Green:
  parsondemoapp-service          ← primary (points to active color)
  parsondemoapp-service-stage    ← stage (points to inactive color)
  parsondemoapp-deployment       ← labeled harness.io/color=blue (or green)
  release-parsondemoapp (CM)     ← strategy: BlueGreen

After Canary:
  parsondemoapp-service          ← stable service
  parsondemoapp-deployment       ← stable pods (harness.io/track=stable)
  parsondemoapp-deployment-canary← canary pods (harness.io/track=canary)
  release-parsondemoapp (CM)     ← strategy: Canary

After Rolling:
  parsondemoapp-service          ← standard service
  parsondemoapp-deployment       ← all pods on new version
  release-parsondemoapp (CM)     ← strategy: Rolling
```

### Key Expressions in Pipeline

| Harness Expression | Resolves To | Example |
|---|---|---|
| `<+infra.namespace>` | K8s namespace from infra definition | `parson-dev` |
| `<+infra.releaseName>` | Release name from infra definition | `parsondemoapp` |
| `<+artifacts.primary.image>` | Full image URI with tag | `123456.dkr.ecr.us-east-1.amazonaws.com/parsondemoapp:1.2.3` |

---

## Troubleshooting

### Chaos not activating
- Verify `DEPLOYMENT_VARIANT=canary` is set
- Check `/api/chaos/status` endpoint
- Ensure the HTTP step is hitting the canary pods, not stable

### CV not detecting issues
- Verify Prometheus is scraping the canary pods
- Check that the health source is configured correctly
- Ensure CV sensitivity is set to HIGH for demos
- Verify the metrics are being collected: `app_errors_total`, `app_chaos_events_total`

### Metrics to watch in Grafana
```promql
# Error rate
rate(app_errors_total{variant="canary"}[1m])

# Chaos events
rate(app_chaos_events_total{variant="canary"}[1m])

# Response latency
histogram_quantile(0.95, rate(http_server_requests_seconds_bucket{variant="canary"}[1m]))
```
