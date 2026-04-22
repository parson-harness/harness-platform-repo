# Toddfour Dynamic Configuration Demo Talk Track

## Goal

Show that Harness can promote the same immutable artifact across environments while changing configuration at deploy time, separating non-secret and secret values, and leaving an execution audit trail.

## What this demo proves

- The application image is built once and promoted unchanged.
- Non-secret configuration is injected at deploy time.
- Sensitive configuration is injected separately from non-secret values.
- QA and Prod can resolve different configuration from the same pipeline and artifact.
- The resolved configuration is visible in the application and in the Harness execution logs.

## Demo setup

Use the `E2E Enterprise Pipeline - Toddfour` pipeline.

The dynamic configuration demo is implemented with:

- Pipeline variables for shared app-level settings.
- Stage variables for environment-specific settings in `Deploy to QA` and `Deploy to Prod`.
- `k8s/values.yaml` to resolve Harness expressions.
- `k8s/deployment-templated.yaml` to split config into a Kubernetes `ConfigMap` and `Secret`.
- `/api/info` in the app to show the resolved runtime configuration without exposing secret values.
- `Inspect Dynamic Config` steps in the deploy stages to print a configuration snapshot during execution.

## Suggested talk track

### 1. Set the frame

"I want to show dynamic configuration managed natively in Harness. The important idea is that we are not rebuilding the app for QA versus Prod. We promote the same artifact and inject different config at deployment time."

### 2. Point to the artifact immutability model

In the pipeline execution, highlight that the build stage produces the image once.

Say:

"The image is built once, tagged once, and then promoted forward. What changes between environments is configuration, not the binary."

### 3. Show shared versus stage-specific config

Open the pipeline YAML and point out:

- shared pipeline variables:
  - `dynamic_config_profile`
  - `dynamic_config_tenant`
  - `dynamic_config_support_contact`
- QA stage variables:
  - `dynamic_config_banner`
  - `dynamic_config_release_ring`
  - `dynamic_config_version`
  - `dynamic_config_region`
  - `dynamic_config_secret`
- Prod stage variables with different values for the same keys

Say:

"This lets us model multiple layers of configuration. Shared values stay consistent across environments, while the deploy stage injects environment-specific values at runtime."

### 4. Show non-secret versus secret handling

Open `k8s/deployment-templated.yaml` and explain:

- non-secret settings are rendered into a `ConfigMap`
- secret settings are rendered into a separate Kubernetes `Secret`
- the workload consumes both via `envFrom`

Say:

"This is the native separation most teams want. Non-sensitive settings and sensitive settings are handled differently, but both are resolved at deployment time through Harness."

### 5. Show the app view of resolved config

Open the deployed app or call `/api/info`.

Focus on these fields:

- `configProfile`
- `configBanner`
- `configTenant`
- `configReleaseRing`
- `configTarget`
- `configVersion`
- `configSource`
- `secretProvider`
- `dynamicSecretConfigured`

Say:

"The app can prove which configuration was injected for this deployment. Notice that we show whether the secret is present, but we never return the secret value itself."

### 6. Show the pipeline snapshot step

In the QA and Prod deployment stages, open the `Inspect Dynamic Config` step output.

Say:

"Harness captures a configuration snapshot inside the execution itself. That gives us an audit-friendly record of what the app resolved during deployment, not just what we intended to configure."

### 7. Explain the QA-to-Prod contrast

Compare the QA and Prod outputs.

Suggested contrast:

- QA banner: `QA configuration injected by Harness at deploy time`
- Prod banner: `Production configuration injected by Harness at deploy time`
- QA ring: `pre-release`
- Prod ring: `production`
- QA config version: `qa-config-v1`
- Prod config version: `prod-config-v1`

Say:

"This is the same artifact moving forward, but each environment resolves its own configuration at deploy time."

### 8. Close on the business outcome

Say:

"This gives us cleaner promotion, lower rebuild risk, better separation of duties, and a clearer audit trail. We can change deploy-time configuration without changing the artifact itself."

## If you get asked follow-up questions

### How native is this?

"This demo stays inside native Harness CD patterns: pipeline variables, stage variables, Kubernetes values rendering, and execution logs."

### Does this support secrets too?

"Yes. In this demo, secrets are injected separately and the app only reports whether the secret is configured, not the secret value."

### Does this require rebuilding for each environment?

"No. That is the core point of the demo. The artifact stays the same while the configuration changes by environment."

### Does this show pull-based config refresh without redeploy?

"Not in this slice. This demo focuses on the push-based deployment-time model because it is the cleanest native Harness story for Toddfour right now."

## Recommended demo path

1. Run the pipeline.
2. Let QA deploy complete.
3. Open the `Inspect Dynamic Config` step in QA.
4. Show `/api/info` on the stage or QA endpoint.
5. Proceed to Prod.
6. Open the Prod `Inspect Dynamic Config` step.
7. Compare the resolved values.
8. End by reinforcing that the artifact did not change.

## Key takeaway

Harness is acting as the control plane for runtime configuration injection, promotion, and auditability, while the application stays immutable.
