# Control-Plane / Factory Boundary

## Purpose

Define the next architectural boundary for the centralized sandbox re-architecture so future changes move toward a persistent factory model instead of rebuilding shared management concerns inside every sandbox workspace.

## Current Signals in the Repo

The current repo already points toward a layered model:

- `tofu/stacks/project-governance/` manages project-scoped policy assets
- `tofu/stacks/eks/` provisions shared-EKS delivery resources for a single owner/workspace
- `tofu/stacks/asg/` provisions customer-AWS delivery resources for a single owner/workspace
- `.harness/templates/Project_Governance` points at `tofu/stacks/project-governance`
- `.harness/templates/POV_Provisioner` points at `tofu/stacks/eks`
- `.harness/templates/Sandbox_Provisioner_ASG` points at `tofu/stacks/asg`
- `.harness/pipelines/idp_pov_provisioner.yaml` already creates and links governance and sandbox workspaces separately

That means the repo is no longer missing the pieces. What is missing is an explicit ownership model.

## Proposed Lifecycle Layers

### 1. Bootstrap Layer

Scope:

- account or platform bootstrap
- backend/state setup
- base credentials/connectors required before factory flows run

Characteristics:

- long-lived
- changed rarely
- should not be tied to any one customer sandbox lifecycle

Examples:

- `tofu/bootstrap/`
- foundational account-level prerequisites for IACM execution

### 2. Control Plane Layer

Scope:

- persistent orchestration surface for provisioning and governance
- shared pipeline, template, janitor, and workflow entry points
- shared cluster/delegate substrate used to run provisioning for many sandboxes

Characteristics:

- stable and centrally owned
- should survive the destruction of any individual sandbox
- should be updated intentionally, not recreated per customer

Current examples:

- `.harness/pipelines/idp_pov_provisioner.yaml`
- `.harness/pipelines/idp_pov_destroyer_v2.yaml`
- `.harness/workflows/*`
- `.harness/templates/*`
- shared EKS/delegate substrate referenced by `tofu/stacks/eks`

Recommended rule:

The control plane should own orchestration and template linkage, but not own customer-specific workload state.

### 3. Project Governance Layer

Scope:

- project-scoped policies and policy sets
- long-lived guardrails reused by many sandboxes in the same target project
- change governance defaults that should not disappear when one sandbox is destroyed

Current implementation:

- `tofu/stacks/project-governance/`
- `Project_Governance` workspace template
- governance workspace `{project}_governance` created by the IDP provisioner

Recommended rule:

If a resource protects or governs multiple sandboxes in the same target project, it belongs here instead of inside a per-owner workload workspace.

Examples that belong here:

- OPA policies
- policy sets
- project-level approval/governance defaults
- reusable guardrail tags and conventions

### 4. Customer Project Factory Layer

Scope:

- creation or reconciliation of a customer project as a productized onboarding flow
- project-level resources needed for a demo/customer environment, but not tied to a single app deployment instance
- reusable project wiring that should be consistent across many customer environments

Examples that may move here over time:

- project-level connectors that should be shared across multiple owner workspaces
- repo wiring or Harness Code import defaults
- freeze windows
- RBAC/resource groups
- project-level pipeline templates or reusable triggers
- project-wide artifact registry or registry policy defaults when they are intentionally shared

Recommended rule:

If deleting one owner workspace would break another owner workspace in the same project, the resource should be evaluated for factory ownership instead of per-workspace ownership.

### 5. Workload Workspace Layer

Scope:

- owner-scoped, workspace-scoped runtime resources
- resources safe to create, update, and destroy with a single owner sandbox
- stack-specific delivery resources

Current implementation:

- `tofu/stacks/eks/`
- `tofu/stacks/asg/`
- linked workspaces like `{owner}_pov`

Examples that belong here:

- owner namespace
- owner service/environment/infrastructure
- owner delegate when intentionally isolated per sandbox
- owner DNS records
- owner ASG/VPC resources
- owner-specific delivery pipelines
- owner-specific file store artifacts

Recommended rule:

A workload workspace should be disposable. Destroying it should not remove shared governance or shared control-plane capability.

## Ownership Test

Use this test for any resource under review:

### Put it in Control Plane / Governance / Factory when:

- more than one sandbox depends on it
- its destruction would break onboarding, governance, or shared orchestration
- it represents a productized default rather than an owner-specific instance
- it is safer to reconcile centrally than per sandbox

### Put it in Workload Workspace when:

- it is clearly owner-scoped
- it should disappear with the sandbox
- its naming/tags are workspace-specific
- recreating it for a single owner is expected and safe

## Recommended Boundary for the Current Repo

## Resource Ownership Matrix

| Resource Class | Current Home | Proposed Home | Why |
|----------------|--------------|---------------|-----|
| IDP provision/destroy/janitor pipelines | `.harness/pipelines/*` | Control plane | Shared orchestration surface for all sandboxes |
| IDP workflows | `.harness/workflows/*` | Control plane | Shared entry points, not owner-specific state |
| Workspace templates | `.harness/templates/*` | Control plane | Productized provisioning contracts reused by many workspaces |
| Governance policies and policy sets | `tofu/stacks/project-governance` | Project governance | Protect multiple workspaces in the same target project |
| Governance workspace `{project}_governance` | IDP-created linked workspace | Project governance | Long-lived project guardrail state |
| Shared EKS orchestration cluster/delegate substrate | external/shared infra | Control plane | Provisioning substrate should outlive owner workspaces |
| Owner namespace | `tofu/stacks/eks` | Workload workspace | Clearly owner-scoped and disposable |
| Owner service/environment/infrastructure | `tofu/stacks/eks`, `tofu/stacks/asg` | Workload workspace | Created for one owner sandbox |
| Owner DNS / ASG / VPC resources | `tofu/stacks/asg` | Workload workspace | Customer-runtime resources tied to one sandbox |
| Owner delivery pipelines | `tofu/stacks/eks`, `tofu/stacks/asg` | Workload workspace | Safe to destroy with owner workspace |
| Project-level connectors | currently created in workload stacks | Candidate: customer-project factory | Likely reusable across multiple owner workspaces in one project |
| Harness Code repo import defaults / repo wiring | mixed in workload stacks and pipeline inputs | Candidate: customer-project factory | Often shared project wiring, not purely owner runtime state |
| Artifact registry defaults and upstream policy | mixed in workload stacks | Candidate: customer-project factory | Could be shared policy/wiring instead of per-owner duplication |

### Persistent shared layers

These should remain stable even if all individual POV workspaces are destroyed:

- IDP workflows and provision/destroy/janitor pipelines under `.harness/`
- workspace templates under `.harness/templates/`
- project governance workspace template and stack
- shared EKS orchestration cluster and delegate substrate
- janitor and cleanup logic

### Customer-project factory candidates

These deserve explicit review next:

- project-level connectors currently recreated inside `tofu/stacks/eks` or `tofu/stacks/asg`
- project-level artifact registry decisions
- project-wide governance toggles currently passed into owner workspaces
- any repo import / Harness Code bootstrapping that should happen once per target project

### Keep owner-scoped for now

These are still reasonable inside `stacks/eks` or `stacks/asg`:

- owner namespace
- owner service/environment/infrastructure
- owner DNS
- owner app delivery pipelines
- owner compute/networking resources for ASG
- owner-specific workspace metadata and tagging

## Tension to Resolve Next

The main unresolved question is connector and project wiring ownership.

Right now, the stack workspaces still create many resources that are arguably project-scoped, while `project-governance` only handles policy assets. The next useful implementation slice is to decide which of the following should move up into a customer-project factory layer:

- Kubernetes connector
- AWS connector
- GitHub connector
- HAR registry defaults
- shared project-level repo wiring
- policy-driven approval defaults beyond OPA policy creation

## Proposed Next Implementation Sequence

### Option A: Minimal next slice

- document a resource ownership matrix
- mark each major Harness resource as `governance`, `factory`, or `workload`
- leave implementation unchanged for one more checkpoint

### Option B: First real factory move

- carve project-level connectors out of `stacks/eks` and/or `stacks/asg`
- create or reconcile them once per target project
- keep owner workspaces focused on service/environment/infrastructure/runtime resources

### Option C: Governance + factory split hardening

- keep `project-governance` for policy assets only
- introduce a separate project-factory stack for shared project wiring
- reduce owner workspaces to strictly disposable workload resources

## Recommended Next Slice

Start with Option C for the first durable shared-resource move:

- keep `project-governance` limited to policy assets and project guardrails
- introduce a separate `project-factory` workspace for reusable project-scoped wiring
- move only the AWS and GitHub connector class first because it has a small blast radius and clear reuse value

## First Implemented Factory Move

The first low-risk factory move is now in place as an opt-in reuse path:

- `tofu/stacks/eks` can reuse shared `aws_connector_ref` and `github_connector_ref`
- `tofu/stacks/asg` can reuse shared `aws_connector_ref` and `github_connector_ref`
- the workload stacks still preserve existing behavior when those refs are left empty
- `.harness/templates/POV_Provisioner` and `.harness/templates/Sandbox_Provisioner_ASG` now accept those optional shared connector refs
- `.harness/pipelines/idp_pov_provisioner.yaml` passes the optional refs through initial create, reconcile, and recreate workspace flows

This is intentionally a reuse-first move and established the connector contract before introducing a permanent factory owner.

## Current Connector Factory Slice

Shared project-level AWS and GitHub connectors now belong in a separate `project-factory` layer, not in `project-governance`:

- `tofu/stacks/project-governance` remains policy-only
- `tofu/stacks/project-factory` owns project-scoped shared AWS and GitHub connectors
- `.harness/templates/project_factory_workspace.yaml` defines the durable IACM workspace template for that layer
- `.harness/pipelines/idp_pov_provisioner.yaml` can now optionally create or reconcile `${project}_factory` before provisioning workload workspaces
- workload workspace create, reconcile, and recreate paths resolve effective shared connector refs from either explicit pipeline inputs or the predictable project-factory connector IDs

The new path is deliberately opt-in so existing owner-scoped connector behavior remains unchanged until the shared factory workflow is enabled for a target project.
