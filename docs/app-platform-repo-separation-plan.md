# App / Platform Repo Separation Plan

## Purpose

Define the first practical split of this repository into:

- a **platform repo** that owns infrastructure, Harness orchestration, and sandbox/project lifecycle
- an **app repo** that owns the demo application payload, manifests, and app-scoped Harness assets

This document is the working migration plan for the first separation iteration.

## Chosen Repo Names

- future app repo: `harness-demo-app`
- future platform repo: `harness-platform-repo`

The current combined repo should be treated as the future platform repo, which means the current repository should eventually be renamed to `harness-platform-repo` as the app payload moves out.

## Key Decisions

### 1. Keep the unified E2E pipeline in the platform repo

The current unified pipeline remains platform-owned:

- `.harness/E2E_Enterprise_Pipeline_Toddfour.yaml`

This pipeline will continue to orchestrate CI/CD, governance, and promotion, even after app code and manifests move to a separate repo.

### 2. Do not use bidirectional sync or repo mirroring as the long-term coupling model

The target model is:

- GitHub as source of truth for both repos
- direct Harness references to the correct repo for each asset
- stable contracts between repos instead of copied YAML or mirror-driven drift

### 3. Start with a prep branch, not a fake nested repo folder

This branch exists to:

- document ownership
- stabilize contracts
- sequence the move safely
- avoid temporary nested-repo layout churn inside the current repo

## Target Ownership Model

### Platform repo owns

- `tofu/**`
- `.harness/E2E_Enterprise_Pipeline_Toddfour.yaml`
- `.harness/pipelines/**`
- `.harness/templates/**`
- `.harness/workflows/**`
- `.harness/triggers/**`
- `.harness/Toddfour_K8s_QA.yaml`
- `.harness/Toddfour_Prod.yaml`
- governance and project/factory assets

### App repo owns

- `src/**`
- `k8s/**`
- `Dockerfile`
- `build.gradle`
- `settings.gradle`
- `pom.xml`
- `package.json`
- `package-lock.json`
- `playwright.config.js`
- `playwright-tests/**`
- `docker/**`
- app-oriented `scripts/**`
- `.harness/toddfour_demo_app.yaml`

### Split by concern

- `.harness/input_sets/**`
  - app-facing defaults belong in the app repo
  - governance/environment-routing input sets belong in the platform repo
- `docs/**`
  - platform/operator architecture docs stay with platform
  - app/runtime docs move with the app repo
- `harness/**`
  - keep only if still useful as reference/example YAML
  - otherwise retire or archive

## Stable Contracts To Preserve

The first split should keep these stable.

### Service contract

- service identifier: `toddfour_demo_app`
- service variables consumed by pipeline stages:
  - `ingressHost`
  - `ingressStageHost`
  - `certArn` if still required in the service definition

### Environment contract

- `Toddfour_K8s_QA`
- `Toddfour_Prod`
- infrastructure identifiers such as `toddfour_k8s_qa`

### Manifest contract

- manifest root remains `k8s/`
- values path remains `k8s/values.yaml`

### Artifact contract

Keep the current artifact naming and pipeline assumptions stable for phase 1.

Current examples in the repo:

- image name: `toddfourdemoapp`
- service ref: `toddfour_demo_app`
- current pipeline-generated tag usage remains unchanged during the first cutover

### Pipeline variable contract

Keep existing app-facing variables stable during phase 1:

- `application_display_name`
- `customer_display_name`
- `dynamic_config_profile`
- `dynamic_config_tenant`
- `dynamic_config_support_contact`

## Current Files By Ownership

### Platform-owned now

- `.harness/E2E_Enterprise_Pipeline_Toddfour.yaml`
- `.harness/Toddfour_K8s_QA.yaml`
- `.harness/Toddfour_Prod.yaml`
- `.harness/pipelines/idp_pov_provisioner.yaml`
- `.harness/pipelines/idp_pov_destroyer_v2.yaml`
- `.harness/pipelines/pov_bulk_update.yaml`
- `.harness/pipelines/pov_destroy.yaml`
- `.harness/pipelines/pov_provisioning.yaml`
- `.harness/pipelines/sandbox_manager.yaml`
- `.harness/pipelines/sandbox_ttl_cleanup.yaml`
- `.harness/templates/cd_ecs_rolling_stage.yaml`
- `.harness/templates/cd_eks_bluegreen_stage.yaml`
- `.harness/templates/cd_eks_canary_stage.yaml`
- `.harness/templates/ci_build_and_push_stage.yaml`
- `.harness/templates/ci_build_stage.yaml`
- `.harness/templates/ci_integration_tests_stage.yaml`
- `.harness/templates/policy_driven_approval_stage.yaml`
- `.harness/templates/pov_provisioner_eks_workspace.yaml`
- `.harness/templates/project_factory_workspace.yaml`
- `.harness/templates/project_governance_workspace.yaml`
- `.harness/templates/sandbox_provisioner_asg_workspace.yaml`
- `.harness/triggers/sandbox_ttl_cleanup_cron.yaml`
- `.harness/triggers/toddfour_live_pr_created.yaml`
- `.harness/workflows/**`
- `tofu/**`

### App-owned now

- `.harness/toddfour_demo_app.yaml`
- `src/**`
- `k8s/**`
- `Dockerfile`
- `build.gradle`
- `settings.gradle`
- `pom.xml`
- `package.json`
- `package-lock.json`
- `playwright.config.js`
- `playwright-tests/**`
- `docker/**`
- likely app-oriented assets in `scripts/**`
- likely app/runtime docs under `docs/`

### Split/review assets

- `.harness/input_sets/toddfour_pr_live_defaults.yaml`
- `.harness/input_sets/toddfour_pr_ti_demo.yaml`
- `harness/pipelines/**`
- `README.md`
- `docs/**`
- `asg/**`
- `scripts/**`

## Target Repo Layouts

### Platform repo

```text
platform-repo/
  .harness/
    pipelines/
      E2E_Enterprise_Pipeline_Toddfour.yaml
      idp_pov_provisioner.yaml
      idp_pov_destroyer_v2.yaml
      pov_*.yaml
      sandbox_*.yaml
    templates/
    triggers/
    workflows/
    environments/
      Toddfour_K8s_QA.yaml
      Toddfour_Prod.yaml
    README.md
  tofu/
    bootstrap/
    modules/
    stacks/
    environments/
  docs/
    platform/
```

### App repo

```text
app-repo/
  src/
  k8s/
  asg/
  docker/
  playwright-tests/
  scripts/
  Dockerfile
  build.gradle
  settings.gradle
  pom.xml
  package.json
  package-lock.json
  playwright.config.js
  README.md
  catalog-info.yaml
  .harness/
    services/
      toddfour_demo_app.yaml
    input_sets/
      toddfour_pr_live_defaults.yaml
      toddfour_pr_ti_demo.yaml
  docs/
    app/
```

## Phase 1: Lowest-Risk Cutover

### Step 1. Keep orchestration where it is

Do not move these yet:

- `.harness/E2E_Enterprise_Pipeline_Toddfour.yaml`
- `.harness/Toddfour_K8s_QA.yaml`
- `.harness/Toddfour_Prod.yaml`
- `tofu/**`

### Step 2. Create the real app repo

Seed it with:

- `src/**`
- `k8s/**`
- `Dockerfile`
- build files
- test assets
- `.harness/toddfour_demo_app.yaml`

### Step 3. Repoint the service definition to the real app repo

The current service definition at `.harness/toddfour_demo_app.yaml` references:

- repo name: `harness-demo-app`
- manifests path: `k8s/`
- values path: `k8s/values.yaml`

Phase 1 should preserve the manifest paths and only change the backing repo reference.

### Step 4. Configure Harness to read both repos directly

Harness should read:

- platform YAML from the platform repo
- service/manifests/input sets from the app repo

This is the point where the current mirror-driven coupling should stop being required for the split.

### Step 5. Move app-owned input sets after the service cutover is stable

Move input sets only after the app repo is a stable source of truth.

## Exact Phase 1 Move List

### First files to move into the new app repo

- `src/**`
- `k8s/**`
- `Dockerfile`
- `build.gradle`
- `settings.gradle`
- `pom.xml`
- `package.json`
- `package-lock.json`
- `playwright.config.js`
- `playwright-tests/**`
- `docker/**`
- `.harness/toddfour_demo_app.yaml`
- app-relevant docs

### Files to leave in this repo for phase 1

- `tofu/**`
- `.harness/E2E_Enterprise_Pipeline_Toddfour.yaml`
- `.harness/Toddfour_K8s_QA.yaml`
- `.harness/Toddfour_Prod.yaml`
- `.harness/pipelines/**`
- `.harness/templates/**`
- `.harness/workflows/**`
- `.harness/triggers/**`

## Open Questions To Resolve Before The First Cutover PR

### 1. Final app repo name

Chosen:

- app repo: `harness-demo-app`
- platform repo: `harness-platform-repo`

Required sequencing:

- rename the current GitHub repo from `harness-demo-app` to `harness-platform-repo`
- create the new app repo as `harness-demo-app`

### 2. Service definition location convention

Recommended target path in the app repo:

- `.harness/services/toddfour_demo_app.yaml`

### 3. Input set split rule

Recommended rule:

- app behavior/demo defaults -> app repo
- governance/promotion/environment targeting -> platform repo

### 4. `asg/` ownership

Needs a final pass to distinguish:

- app payload/runtime startup content
- platform-specific packaging or infra helpers

### 5. `harness/` example YAML retention

Decide whether `harness/pipelines/**` is:

- still useful as sample/reference content
- or ready for archive/removal

## Recommended Next Implementation Slice

After this plan doc is in place, the next concrete action should be:

1. create the new app repo
2. move the first app-owned slice into it
3. update the service definition to reference the new repo directly
4. keep the unified E2E pipeline in the platform repo and validate it against the moved service/manifests
