# Repository Architecture

## Purpose

This repository is both:

- a demo application codebase
- a provisioning and control-plane codebase for standing up Harness demo, sandbox, and POV environments around that application

The result is a layered repo where application payloads, Harness control-plane definitions, and OpenTofu infrastructure all live together.

## Architectural Summary

At a high level, the repo is organized into five layers:

1. **Application layer**
   - Spring Boot application source under `src/`
   - UI, API, metrics, and deployment behavior for the demo app itself

2. **Deployment payload layer**
   - Kubernetes manifests under `k8s/`
   - ASG-specific startup and packaging assets under `asg/`
   - legacy/example Harness pipeline YAMLs under `harness/`

3. **Control-plane layer**
   - live Harness pipelines, workspace templates, and IDP workflows under `.harness/`
   - this is the main orchestration surface for provisioning and cleanup

4. **Infrastructure composition layer**
   - reusable OpenTofu modules under `tofu/modules/`
   - stack entrypoints under `tofu/stacks/`

5. **Architecture and operator docs layer**
   - design, testing, and migration guidance under `docs/`
   - top-level and `tofu/` READMEs for operator entrypoints

## Top-Level Repo Map

```text
.
├── .harness/                 # Live Harness control-plane definitions
├── asg/                      # ASG-specific payloads (user-data, Harness YAML helpers, Packer)
├── docs/                     # Architecture, migration, testing, and reference docs
├── harness/                  # Legacy/example Harness YAML payloads
├── k8s/                      # Kubernetes manifests and values
├── scripts/                  # Operator helper scripts
├── src/                      # Spring Boot application source
├── tofu/                     # OpenTofu modules, stacks, bootstrap, and shared infra
├── Dockerfile                # Container build for the app
├── catalog-info.yaml         # Backstage/IDP metadata
├── pom.xml                   # Maven build definition
└── build.gradle              # Gradle build definition
```

## Primary Runtime Paths

The repo currently supports two main provisioning/runtime paths.

### Shared-EKS path

This path uses an existing shared EKS cluster and provisions owner-scoped Harness/application resources around it.

Core pieces:

- `.harness/workflows/*provisioner*.yaml`
- `.harness/pipelines/idp_pov_provisioner.yaml`
- `.harness/templates/pov_provisioner_eks_workspace.yaml`
- `tofu/stacks/eks/`
- `k8s/`

Typical use cases:

- SE sandbox in the same Harness account
- POV-in-a-box using shared AWS substrate but customer Harness project/org

### Customer-AWS ASG path

This path provisions a more self-contained AWS footprint for the demo and wires Harness resources to deploy into an Auto Scaling Group model.

Core pieces:

- `.harness/workflows/*provisioner*.yaml`
- `.harness/pipelines/idp_pov_provisioner.yaml`
- `.harness/templates/sandbox_provisioner_asg_workspace.yaml`
- `tofu/stacks/asg/`
- `asg/`

Typical use cases:

- customer-owned AWS environments
- self-contained POV sandboxes where shared EKS is not the target runtime

## The Most Important Distinction: `.harness/` vs `harness/`

This repo contains two different Harness-related directories with different responsibilities.

### `.harness/`

This is the **live control-plane directory**.

It contains:

- project workflows
- provisioning and destroy pipelines
- workspace templates
- janitor/cleanup orchestration

These files describe how Harness itself provisions and manages workspaces and infrastructure in the current stack-based model.

### `harness/`

This is primarily a **payload/example directory**.

It contains:

- legacy or manually importable pipeline YAML examples
- reference pipeline definitions that are useful for inspection or manual import

This directory is not the main source of truth for the new IACM-driven provisioning architecture.

## `.harness/` Control Plane

The `.harness/` directory acts as the durable control plane for this repo.

### Pipelines

Key pipelines include:

- `idp_pov_provisioner.yaml`
  - main orchestration pipeline
  - creates or reconciles project-scoped and owner-scoped workspaces
  - drives OpenTofu execution through IACM

- `idp_pov_destroyer_v2.yaml`
  - state-aware destroy path
  - prefers Terraform/OpenTofu destroy before API cleanup

- `sandbox_ttl_cleanup.yaml`
  - janitor flow for expiring linked sandboxes

- `pov_provisioning.yaml`
  - default plan/apply pipeline used by linked workspaces

- `pov_destroy.yaml`
  - default destroy pipeline used by linked workspaces

### Workspace templates

The most important workspace templates are:

- `pov_provisioner_eks_workspace.yaml`
  - owner-scoped EKS workload workspace template

- `sandbox_provisioner_asg_workspace.yaml`
  - owner-scoped ASG workload workspace template

- `project_governance_workspace.yaml`
  - long-lived project governance workspace template

- `project_factory_workspace.yaml`
  - long-lived project factory workspace template for shared connectors

### Workflows

Workflows provide the user-facing entrypoints into the control plane.

Examples:

- `pov_provisioner_workflow.yaml`
- `se_sandbox_provisioner.yaml`
- `pov_destroyer_workflow.yaml`
- `sandbox_cleanup_workflow.yaml`

These workflows collect user/project inputs and trigger the underlying pipelines.

## OpenTofu Layout

`tofu/` is the infrastructure composition layer.

### `tofu/modules/`

This directory contains reusable building blocks that stacks compose together.

Important modules include:

- `sandbox-context`
  - central naming, tags, owner context, and workspace metadata contract

- `harness-org-project`
  - create or adopt Harness org/project scope

- `harness-connectors`
  - create Harness connectors for Kubernetes, AWS, GitHub, Docker, and Prometheus

- `harness-service`
- `harness-environment`
- `harness-pipeline`
- `harness-artifact-registry`
- `harness-code-repo`
- `harness-opa-policies`
- `harness-delegate`
- `irsa-delegate-role`

The modules directory is where shared conventions should be centralized when behavior must stay consistent across stacks.

### `tofu/stacks/`

This directory contains deployable entrypoints, each representing a lifecycle boundary.

#### `tofu/stacks/eks/`

Owner-scoped workload stack for Kubernetes deployments into an existing EKS cluster.

Responsibilities:

- owner-specific namespace and runtime wiring
- Harness service, environment, infrastructure, and pipelines
- owner-scoped connectors unless shared refs are supplied
- optional delegate creation

#### `tofu/stacks/asg/`

Owner-scoped workload stack for Auto Scaling Group deployments.

Responsibilities:

- AWS network/compute resources for the owner sandbox
- Harness ASG delivery resources
- owner-scoped connectors unless shared refs are supplied
- ASG-specific runtime and delivery wiring

#### `tofu/stacks/project-governance/`

Project-scoped governance layer.

Responsibilities:

- policy assets
- policy sets
- long-lived project guardrails

This stack is intentionally policy-only in the current architecture.

#### `tofu/stacks/project-factory/`

Project-scoped factory layer.

Responsibilities:

- durable shared AWS connector creation/reconciliation
- durable shared GitHub connector creation/reconciliation
- reusable project wiring that should outlive a single owner workspace

This is the current permanent home for shared project-level AWS and GitHub connectors.

### `tofu/bootstrap/`

Bootstrap code for prerequisites such as state/backend or account-level setup.

This layer is foundational and should not be tied to individual sandbox lifecycle.

### `tofu/shared-infra/`

Shared long-lived infrastructure used by multiple sandboxes.

This is where shared substrate belongs when it should survive the destruction of any individual owner workspace.

### `tofu/environments/`

Legacy monolithic environment path.

The repo is actively moving away from this model in favor of `tofu/stacks/*`.

Treat `tofu/environments/sandbox` as legacy/reference material during the migration rather than the forward path.

## Application and Payload Directories

### `src/`

Spring Boot demo application code.

Main concerns:

- UI and API endpoints
- deployment-variant behavior
- metrics and observability hooks
- customer branding/runtime environment behavior

### `k8s/`

Kubernetes deployment payloads.

Contains:

- deployment templates
- ingress
- values
- ServiceMonitor wiring

These are the application-side manifests consumed by the EKS delivery path.

### `asg/`

ASG deployment payloads.

Contains:

- `user-data.sh`
- `packer/`
- ASG-specific Harness payload helpers under `asg/harness/`

These assets support the ASG delivery model, where the application is packaged for EC2/AMI-based deployment rather than Kubernetes.

### `harness/`

Reference/manual-import Harness payloads.

Use this directory for:

- inspecting example pipeline YAMLs
- manual imports
- legacy/reference examples

Do not treat it as the primary orchestration surface for the stack-first provisioning model.

## Scripts

The `scripts/` directory contains operator-focused helpers.

Examples:

- `build-and-push.sh`
- `create-har-secret.sh`
- `test-eks-deployment.sh`
- `demo-test-intelligence.sh`

These scripts are convenience tooling around the stack-based model, not the architectural source of truth.

## Documentation Layout

The `docs/` directory contains design and operational guidance.

Important docs include:

- `centralized-sandbox-rearchitecture-plan.md`
  - current migration plan and checkpoints

- `control-plane-factory-boundary.md`
  - ownership model across control plane, governance, factory, and workload layers

- `EKS_TESTING_GUIDE.md`
  - operator verification guidance

- deployment- and auth-specific references
  - ALB
  - delegate permissions
  - OIDC
  - Lambda
  - ASG deployment references

## Current Layered Ownership Model

The repo currently follows this lifecycle model.

### Bootstrap layer

Owns prerequisites and foundational setup.

Examples:

- `tofu/bootstrap/`

### Control-plane layer

Owns orchestration entrypoints, templates, and cleanup flows.

Examples:

- `.harness/pipelines/*`
- `.harness/templates/*`
- `.harness/workflows/*`

### Project governance layer

Owns shared project guardrails.

Examples:

- `tofu/stacks/project-governance/`
- `${project}_governance` workspace

### Customer project factory layer

Owns shared project-scoped resources that should not be tied to a single owner workspace.

Examples:

- `tofu/stacks/project-factory/`
- `${project}_factory` workspace
- shared AWS and GitHub connectors

### Workload workspace layer

Owns disposable owner-specific runtime resources.

Examples:

- `tofu/stacks/eks/`
- `tofu/stacks/asg/`
- `${owner}_pov` workspaces

## Provisioning Flow

The most important orchestration flow in the repo is:

```text
IDP workflow
  -> .harness/workflows/*provisioner*.yaml
  -> .harness/pipelines/idp_pov_provisioner.yaml
  -> optional ${project}_governance workspace bootstrap
  -> optional ${project}_factory workspace bootstrap
  -> ${owner}_pov workspace create or reconcile
  -> IACM executes tofu/stacks/eks or tofu/stacks/asg
  -> OpenTofu modules create Harness and AWS resources
```

Destroy flow:

```text
IDP/workflow destroy request
  -> .harness/pipelines/idp_pov_destroyer_v2.yaml
  -> unblock runtime dependencies if needed
  -> Terraform/OpenTofu destroy via workspace state
  -> orphan cleanup fallback only when necessary
  -> delete owner workspace
  -> preserve shared governance and project-factory assets
```

## Source-of-Truth Guidance

When you are deciding where to make a change, use this rule of thumb:

- change `.harness/` when you are changing orchestration, workflow inputs, workspace templates, or janitor behavior
- change `tofu/modules/` when you are changing reusable infrastructure building blocks
- change `tofu/stacks/` when you are changing deployable lifecycle boundaries or stack-specific resource composition
- change `src/`, `k8s/`, or `asg/` when you are changing the application or deployment payloads themselves
- change `docs/` when you are documenting architecture, migration, or operational behavior

## Forward Path

The repo is moving toward a stack-first, persistent-factory model.

That means:

- prefer `tofu/stacks/*` over `tofu/environments/sandbox`
- prefer `.harness/` control-plane assets over manual/legacy payload import flows
- keep shared project resources in governance/factory layers when multiple workspaces depend on them
- keep owner workspaces disposable

## Related Documents

- `README.md`
- `tofu/README.md`
- `tofu/stacks/README.md`
- `docs/centralized-sandbox-rearchitecture-plan.md`
- `docs/control-plane-factory-boundary.md`
