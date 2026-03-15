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
