# Centralized Sandbox Re-architecture Plan

## Goal

Move the repo from the legacy monolithic sandbox model toward a stack-based, centrally managed architecture that works well with Harness IACM workspace templates and future factory-style provisioning.

## Working Branch

- `rearch/centralized-sandbox-management`

## Latest Checkpoints

- `8760356` - `Centralize sandbox workspace context metadata`
- `b7a6284` - `Default helper scripts to stack-based tofu path`
- `4681aaf` - `Add centralized sandbox rearchitecture plan`
- `ff9b535` - `Retire legacy sandbox entrypoint`
- `9dc4496` - `Document control plane factory boundary`
- Current working tree: stack docs migration, EKS helper/output compatibility, and tracked legacy sandbox removal

## Key Direction

- Prefer `tofu/stacks/*` over `tofu/environments/sandbox`
- Treat Harness IACM workspace templates as the forward-looking propagation mechanism
- Keep shared/project-level resources stable and centrally managed
- Keep sandbox-specific resources unique, human-readable, and workspace-tagged
- Avoid depending on GitHub template snapshot behavior for long-term sandbox sync

## Completed Slices

### 1. Shared sandbox context module

Added `tofu/modules/sandbox-context/` to centralize:

- owner title
- name prefix
- delegate selector
- common tags
- workspace-aware tags
- common tag values

### 2. Stack alignment

Wired the shared context into:

- `tofu/stacks/eks/platform.tf`
- `tofu/stacks/asg/main.tf`

### 3. Legacy sandbox metadata alignment

Aligned `tofu/environments/sandbox/*` with the same workspace metadata contract so legacy and stack paths speak a more consistent language while retirement is in progress.

### 4. Helper script default path shift

Updated helper scripts to default to the stack-based EKS path instead of the legacy sandbox path:

- `scripts/build-and-push.sh`
- `scripts/create-har-secret.sh`

### 5. Stack compatibility and docs migration

Aligned the stack-first operator experience by:

- adding stack-friendly outputs to `tofu/stacks/eks/outputs.tf`
- deriving AWS account identity for registry outputs in `tofu/stacks/eks/providers.tf`
- correcting HAR fallback URL handling in `scripts/build-and-push.sh`
- making `scripts/test-eks-deployment.sh` derive owner-aware stack defaults from `tofu/stacks/eks/terraform.tfvars`
- migrating `README.md`, `tofu/README.md`, and `docs/EKS_TESTING_GUIDE.md` away from operational use of `tofu/environments/sandbox`

### 6. Tracked legacy sandbox retirement

Removed the tracked legacy sandbox entrypoint files from git:

- `tofu/environments/sandbox/main.tf`
- `tofu/environments/sandbox/variables.tf`
- `tofu/environments/sandbox/outputs.tf`
- `tofu/environments/sandbox/terraform.tfvars.example`
- `tofu/environments/sandbox/tfplan`

Local state, backup, and cache artifacts under that directory were intentionally left alone because they are not part of the tracked repo source of truth.

### 7. First connector factory move

Implemented the first safe factory-oriented extraction as a reuse-first path for project-level connectors:

- `tofu/stacks/eks` now accepts optional shared `aws_connector_ref` and `github_connector_ref`
- `tofu/stacks/asg` now accepts optional shared `aws_connector_ref` and `github_connector_ref`
- both stacks resolve effective connector refs and only create owner-scoped connectors when shared refs are not supplied
- IACM templates and the IDP provisioner now pass those optional connector refs through create, reconcile, and recreate flows
- stack outputs now expose the effective connector refs actually in use

### 8. Project factory bootstrap for shared connectors

Implemented the next safe slice by giving shared project-level connectors a durable home outside workload workspaces:

- added `tofu/stacks/project-factory` to create or reconcile shared AWS and GitHub connectors once per target project
- added `.harness/templates/project_factory_workspace.yaml` as the long-lived IACM template for that layer
- updated `.harness/pipelines/idp_pov_provisioner.yaml` to optionally bootstrap `${project}_factory` before workload provisioning
- resolved workload `aws_connector_ref` and `github_connector_ref` from either explicit shared refs or predictable project-factory connector IDs
- kept the new path opt-in so existing owner-scoped connector behavior remains the default until enabled

## Important Findings

### Legacy sandbox usage

`tofu/environments/sandbox` does not appear to be referenced by live `.harness` pipeline/template/workspace paths.

Remaining references are now intentional architectural mentions only, such as:

- this re-architecture plan
- migration notes in `tofu/stacks/README.md`

Operational docs and helper scripts now point at the stack-based paths, and the tracked legacy sandbox entrypoint has been removed from git.

## Next Planned Slices

### Next slice

- Boundary doc: `docs/control-plane-factory-boundary.md`
- Validate the new `${project}_factory` workspace flow in a target project
- Decide when to flip shared connector creation on by default for specific sandbox profiles or projects
- Keep pushing shared management concerns toward persistent factory-style IACM workspaces and templates while leaving Kubernetes connectors in workload stacks for now

### After that

- Refine the project-factory contract for additional shared project-level resources beyond connectors
- Refine project-governance and workspace-template ownership boundaries
- Expand the factory model for reusable customer/demo project provisioning
- Keep pushing management logic toward stack templates and centrally owned Terraform modules
- Provide a docs menu/index of helpful architecture and deployment concept resources for sales engineers
- Add a live Harness smoke test for `${project}_factory` bootstrap and shared connector reuse once the local validation contract settles

## Resume Prompt

If chat context is lost, paste this:

```text
Resume the re-architecture initiative on branch rearch/centralized-sandbox-management.
Use docs/centralized-sandbox-rearchitecture-plan.md as the source of truth.
Continue the next slice:
1) review docs/centralized-sandbox-rearchitecture-plan.md,
2) review docs/control-plane-factory-boundary.md,
3) validate the `${project}_factory` shared connector bootstrap flow,
4) decide the next shared resource class to move after connectors,
5) implement the next safe slice and commit/push.
```

## Minimal Facts To Mention When Resuming

Include these if possible:

- branch: `rearch/centralized-sandbox-management`
- latest checkpoint commit: `ff9b535`
- forward path: `tofu/stacks/*`
- tracked legacy entrypoint retired from git: `tofu/environments/sandbox`

## Notes

Untracked local files not part of this initiative:

- `package.json`
- `package-lock.json`
