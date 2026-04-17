# Centralized Sandbox Re-architecture Plan

## Goal

Move the repo from the legacy monolithic sandbox model toward a stack-based, centrally managed architecture that works well with Harness IACM workspace templates and future factory-style provisioning.

## Working Branch

- `rearch/centralized-sandbox-management`

## Latest Checkpoints

- `8760356` - `Centralize sandbox workspace context metadata`
- `b7a6284` - `Default helper scripts to stack-based tofu path`

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

## Important Findings

### Legacy sandbox usage

`tofu/environments/sandbox` does not appear to be referenced by live `.harness` pipeline/template/workspace paths.

Remaining references are repo-local only:

- `README.md`
- `tofu/README.md`
- `docs/EKS_TESTING_GUIDE.md`
- helper scripts and any remaining docs that still mention the legacy path

This means the legacy sandbox path is likely removable after repo-local references are migrated and any small helper gaps in `tofu/stacks/eks` are addressed.

## Next Planned Slices

### Next slice

- Migrate repo docs and README instructions away from `tofu/environments/sandbox` and toward `tofu/stacks/eks` / `tofu/stacks/asg`
- Verify whether `tofu/stacks/eks` needs additional outputs or helper affordances to fully replace legacy helper assumptions
- Remove `tofu/environments/sandbox` if no remaining references justify keeping it

### After that

- Continue thinning any remaining legacy compatibility paths
- Clarify the control-plane / factory / workload boundaries
- Keep pushing management logic toward stack templates and centrally owned Terraform modules

## Resume Prompt

If chat context is lost, paste this:

```text
Resume the re-architecture initiative on branch rearch/centralized-sandbox-management.
Use docs/centralized-sandbox-rearchitecture-plan.md as the source of truth.
Continue the next slice:
1) migrate remaining docs/readmes off tofu/environments/sandbox to stack-based paths,
2) verify whether stacks/eks needs extra helper outputs for scripts/docs,
3) if no references remain, remove tofu/environments/sandbox,
4) commit and push.
```

## Minimal Facts To Mention When Resuming

Include these if possible:

- branch: `rearch/centralized-sandbox-management`
- latest checkpoint commit: `b7a6284`
- forward path: `tofu/stacks/*`
- legacy path under retirement review: `tofu/environments/sandbox`

## Notes

Untracked local files not part of this initiative:

- `package.json`
- `package-lock.json`
