# Harness Demo App - Kubernetes Manifests

This directory contains Kubernetes manifests with Harness templating for deploying the demo application.

## Files

- **`deployment-templated.yaml`** - Deployment, Service, and Ingress with Harness Go templating
- **`values.yaml`** - Default values for template variables
- **`deployment.yaml`** - Original static manifest (for reference)

## Harness Templating Features

The `deployment-templated.yaml` demonstrates Harness templating capabilities:

### Harness Built-in Expressions

- `<+artifact.image>` - Full container image path from artifact source
- `<+artifact.tag>` - Image tag from artifact source
- `<+service.name>` - Harness service name
- `<+env.name>` - Harness environment name
- `<+pipeline.executionId>` - Unique pipeline execution ID

### Go Template Variables

Variables from `values.yaml` are referenced using Go template syntax:

- `{{.Values.name}}` - Application name
- `{{int .Values.replicas}}` - Number of replicas
- `{{.Values.containerPort}}` - Container port
- `{{.Values.resources.requests.memory}}` - Memory request

## Usage in Harness

1. **Service Configuration**
   - Artifact: ECR image with tag as runtime input
   - Manifests: Git connector pointing to this repo, path `k8s/deployment-templated.yaml`

2. **Service Variables** (override values.yaml)
   ```yaml
   name: harness-demo-app
   replicas: 3
   ingressHost: demo.yourdomain.com
   ```

3. **Pipeline Runtime**
   - Harness automatically resolves `<+artifact.image>` from the selected artifact
   - Go template variables are resolved from service variables or values.yaml
   - Environment-specific values can be set in Harness environment overrides

## Example Deployment

When deployed to environment "prod" with artifact tag "v1.2.3":

```yaml
metadata:
  labels:
    harness.io/service: Parson Demo App
    harness.io/environment: prod
spec:
  containers:
    - name: harness-demo-app
      image: 759984737373.dkr.ecr.us-east-1.amazonaws.com/harness-demo-app-parson:v1.2.3
      env:
        - name: APP_VERSION
          value: v1.2.3
        - name: APP_ENVIRONMENT
          value: prod
```

## References

- [Harness Kubernetes Manifest Templating](https://developer.harness.io/docs/continuous-delivery/deploy-srv-diff-platforms/kubernetes/cd-k8s-ref/example-kubernetes-manifests-using-go-templating/)
- [Harness Built-in Expressions](https://developer.harness.io/docs/platform/variables-and-expressions/harness-variables/)
