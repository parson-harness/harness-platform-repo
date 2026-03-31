# Harness Demo Platform - Project Context

## Mission

Build a **one-click provisioning system** for Harness Sales Engineers to:
1. **SE Sandboxes** - Personal demo environments for learning and customer demos
2. **POV-in-a-Box** - Isolated customer Proof of Value environments

Both use a **shared EKS cluster** with per-user/per-customer isolation.

## Guiding Principles

### 1. Automated & Repeatable
- Everything provisioned via Terraform/OpenTofu through IACM
- No manual steps required after initial setup
- Destroyer pipeline fully cleans up all resources

### 2. Isolated but Cost-Efficient
- Shared EKS cluster (cost savings)
- Per-POV: namespace, delegate, IRSA role, HAR registry, DNS record
- OPA policies scoped to provisioner-created pipelines only (`managed-by:provisioner` tag)

### 3. Self-Documenting
- SEs should understand the architecture to explain it to customers
- Sample app demonstrates real-world patterns, not toy examples
- Pipeline YAML is readable and follows best practices

### 4. Showcase Harness Capabilities
The demo app and pipelines should highlight:
- **CI Intelligence**: Test Intelligence, Cache Intelligence, Docker Layer Caching
- **CD Strategies**: Blue/Green, Canary, Rolling deployments
- **Security**: Gitleaks, SAST, SCA, SBOM generation, SLSA provenance
- **IACM**: Workspace templates, OpenTofu/Terraform management
- **HAR**: Artifact registry with DockerHub upstream proxy
- **OPA Policies**: Governance without blocking unrelated pipelines

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Harness Platform                             │
├─────────────────────────────────────────────────────────────────┤
│  IDP Workflow Form                                               │
│       ↓                                                          │
│  POV Provisioner Pipeline                                        │
│       ↓                                                          │
│  IACM Workspace (from POV_Provisioner template)                  │
│       ↓                                                          │
│  Terraform Apply → Creates all resources below                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     Per-POV Resources                            │
├─────────────────────────────────────────────────────────────────┤
│  Harness:                    │  AWS:                             │
│  - Delegate (per-POV)        │  - IRSA IAM Role                  │
│  - Service                   │  - Route53 DNS Record             │
│  - Environment (dev/prod)    │                                   │
│  - Infrastructure            │  Kubernetes (shared EKS):         │
│  - CI Pipeline (Gradle)      │  - App Namespace                  │
│  - CD Pipeline (Strategy)    │  - Delegate Namespace             │
│  - HAR Registry + Upstream   │  - Ingress → Shared ALB           │
│  - OPA Policies              │                                   │
│  - Harness Code Repo         │                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

### Provisioner Pipeline (`idp_pov_provisioner`)
- Creates IACM workspace from `POV_Provisioner` template
- Template linkage means template updates propagate to all POVs
- Triggers initial CI build after provisioning

### Destroyer Pipeline (`idp_pov_destroyer_v2`)
- Pre-flight: Verify workspace exists
- Unblock: Delete K8s deployments blocking Harness service deletion
- Terraform Destroy: Clean up via IACM
- AWS Cleanup (IACM stage): Delete IRSA role using OIDC credentials
- Cleanup Orphans: API-delete any remaining Harness resources
- Delete Workspace: Remove IACM workspace

### Sample Application
- Spring Boot REST API with `/api/version` endpoint
- Gradle build with Test Intelligence support
- Dockerfile using HAR upstream proxy for base images
- Kubernetes deployment with health checks

### Terraform Modules (`tofu/modules/`)
| Module | Purpose |
|--------|---------|
| `harness-artifact-registry` | HAR virtual registry + DockerHub upstream |
| `harness-code-repo` | Import GitHub repo to Harness Code |
| `harness-connectors` | K8s, Git, AWS connectors |
| `harness-delegate` | Delegate with IRSA annotation |
| `harness-environment` | Environment + infrastructure definitions |
| `harness-opa-policies` | CI/Security/Quality governance policies |
| `harness-org-project` | Optional org/project creation |
| `harness-pipeline` | CI and CD pipelines |
| `harness-service` | Service with artifact source |
| `irsa-delegate-role` | IAM role for delegate AWS access |

## Common Issues & Solutions

### IRSA Role Conflicts
- **Problem**: `EntityAlreadyExists` when provisioning
- **Root Cause**: Destroyer can't delete its own IRSA role (chicken-and-egg)
- **Solution**: AWS Cleanup IACM stage uses OIDC credentials, not delegate IRSA

### HAR Upstream Proxy Missing
- **Problem**: CI fails with `eclipse-temurin:17-jre: not found`
- **Root Cause**: `timestamp()` trigger deleted upstream before creation
- **Solution**: Removed `timestamp()` from cleanup triggers

### OPA Policies Blocking Unrelated Pipelines
- **Problem**: GitHub Mirror pipeline fails policy evaluation
- **Root Cause**: `in_scope` rule was true for ALL pipelines
- **Solution**: Only pipelines with `managed-by:provisioner` tag are evaluated

### Route53 Record Conflicts
- **Problem**: `InvalidChangeBatch: Tried to create resource record set but it already exists`
- **Solution**: `allow_overwrite = true` on Route53 records

### Delegate Token Double Base64
- **Problem**: Delegate CrashLoopBackOff with null token
- **Root Cause**: Token already base64-encoded, then encoded again
- **Solution**: `try(base64decode(token), token)` in delegate module

## Deployment Targets

### EKS (Default)
- Kubernetes deployments to shared EKS cluster
- Per-POV namespace with ingress to shared ALB
- DNS: `{owner}.harness-demo.dev`

### ASG (Optional)
- Packer builds AMI with JAR baked in
- ASG with ALB for blue/green deployments
- DNS: `{owner}-asg.harness-demo.dev`

## CI Pipeline Features (Gradle)

1. **Test Intelligence** - Runs only affected tests
2. **Cache Intelligence** - Auto-caches Gradle dependencies
3. **Docker Layer Caching** - Reuses image layers
4. **Security Scanning** - Gitleaks, SAST, SCA
5. **Supply Chain** - SBOM (Syft), SLSA Provenance
6. **HAR Integration** - Base images via upstream proxy

## Variables Reference

### POV Provisioner Inputs
| Variable | Description | Default |
|----------|-------------|---------|
| `owner` | Unique identifier (e.g., customer name) | Required |
| `create_standard_ci_gradle` | Create Gradle CI pipeline | `true` |
| `create_strategy_pipeline` | Create CD strategy pipeline | `true` |
| `use_harness_code` | Import repo to Harness Code | `true` |
| `create_dockerhub_upstream` | Create HAR upstream proxy | `true` |

### IACM Template Variables
Defined in `POV_Provisioner` template - changes propagate to all linked workspaces.
