# EKS Cluster Bootstrap

This directory contains resources that should be applied **once** when setting up the shared EKS cluster for SE sandboxes.

## Sentinel Ingress

The `sentinel-ingress.yaml` creates a persistent ingress that keeps the shared ALB alive even when all sandbox ingresses are deleted.

### Why is this needed?

The AWS Load Balancer Controller creates an ALB when the first ingress in a group is deployed. If all ingresses are deleted, the ALB is destroyed. When a new ingress is created, a **new ALB with a different DNS name** is created.

The sentinel ingress ensures:
1. The shared ALB (`harness-demo` group) always exists
2. The ALB DNS name remains stable
3. New sandboxes can reliably use the `shared_alb_dns_name` variable

### Setup

1. Ensure the EKS cluster is running and `kubectl` is configured
2. Apply the sentinel ingress:
   ```bash
   kubectl apply -f sentinel-ingress.yaml
   ```
3. Get the ALB DNS name:
   ```bash
   kubectl get ingress -n harness-demo-sentinel -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
   ```
4. Update the `shared_alb_dns_name` default in the IDP Provisioner pipeline if needed

### Verification

After applying, you should be able to access:
- https://sentinel.harness-demo.dev/ - Returns a JSON status message

### Resources Created

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| Namespace | `harness-demo-sentinel` | Isolated namespace for sentinel resources |
| Deployment | `harness-demo-sentinel` | Minimal nginx pod for health checks |
| Service | `harness-demo-sentinel` | ClusterIP service for the deployment |
| ConfigMap | `harness-demo-sentinel` | Nginx config returning JSON status |
| Ingress | `harness-demo-sentinel` | Keeps the shared ALB alive |

### Resource Usage

The sentinel deployment uses minimal resources:
- CPU: 10m request, 50m limit
- Memory: 32Mi request, 64Mi limit
- Replicas: 1

### Cleanup

**WARNING**: Only delete this if you're tearing down the entire EKS cluster.

```bash
kubectl delete -f sentinel-ingress.yaml
```

Deleting the sentinel ingress when other sandbox ingresses exist is safe - the ALB will remain. But if it's the last ingress in the `harness-demo` group, the ALB will be destroyed.
