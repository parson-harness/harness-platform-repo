# Demo Prep: Capability Gaps & Next Steps

Based on the customer's 12-capability RFP scope. Caching (#2) is confirmed working.
Work these in order — #1 and #4 are asked earliest in the demo.

---

## #1 — Pipeline Orchestration / Governance

**What the customer wants to see:**
- Pipelines standardized via templates, closed for modification but open for configuration
- Template inheritance, approved extension points, guardrails
- Teams retain flexibility while platform standards are enforced

**What's built:** Pipeline YAML exists in `.harness/templates/` (ci_build_stage, ci_build_and_push_stage, etc.)

**Gaps to address:**
- Confirm stage templates have `stableVersion` enforcement wired
- Show OPA policy blocking direct pipeline edits (not just template use)
- Demo the "this pipeline is template-managed, you can't break it" story
- Show `tofu-managed: "true"` tag + workspace provisioning as the governance layer

---

## #2 — Dependency Caching & Build Optimization ✅ CONFIRMED WORKING

**Evidence from pipeline run `LVhQDJCIQu62DVcsXTNoRA`:**
- Cache Intelligence: restored `/harness/.gradle` (241 MB) + `/harness/.m2/repository` (60 MB) in 25s
- Build Intelligence: `:compileJava FROM-CACHE`, state `OPTIMIZED`, savings uploaded to UI
- `--profile` flag added → Intelligence Savings panel should now show data
- Docker layer caching: `caching: true` + `optimize: true` on push step

**Still need for demo:**
- A cold run (first build) to show the before/after time comparison
- Cache invalidation story for zero-day scenario (show how to purge via HAR or pipeline variable)

---

## #3 — Artifact Management (HAR as Native Tool)

**What the customer wants to see:**
- Dependency resolution + artifact publishing through native artifact management
- Secret/credential management for the integration
- Reusable secret pattern for other enterprise tool integrations

**What's built:** Pipeline pushes to `har-toddone`, pulls `gradle:8.5-jdk17` from HAR upstream

**Gaps to address:**
- Confirm HAR has upstream proxy configured for Docker Hub (base images) and Gradle Plugin Portal
- Show `har-toddone` registry connector uses a secret ref (not plaintext) — verify in Harness UI
- Demonstrate the secret reuse pattern: same `registryRef: har-toddone` approach for other connectors

---

## #4 — Policy Enforcement in CI

**What the customer wants to see:**
- OPA policies enforced at enterprise / org / project scope
- Alert-only, warn, and fail/block outcomes configurable
- Example policies: insecure dependency, prohibited base image, missing test threshold, missing approvals

**What's built:** Gitleaks, Harness SAST, Semgrep, Trivy all running in pipeline

**Gaps to address:**
- Harness SCA is hard-disabled (`condition: "true" == "false"`) — need to either enable or explain why it's skipped in demo
- Need at least one OPA policy wired at account or org scope that visibly gates the pipeline
- Show policy scoping hierarchy: account → org → project
- Show a policy violation that produces warn vs. block behavior

---

## #5 — Test Automation

**What the customer wants to see:**
- API test automation (RestAssured for backend service)
- Test result reporting + pipeline gating on test outcomes
- Parallelization / test splitting
- Test Intelligence (already in pipeline)

**What's built:** Test Intelligence with `gradle test --build-cache --profile`, JUnit report upload, code coverage via `hcli cov upload`

**Gaps to address:**
- No RestAssured integration test stage — need to add or demo with existing JUnit tests as proxy
- Test splitting / parallelization not configured — add `parallelism` to Test step or show test splitting config
- Show test result gating: pipeline fails if pass rate < threshold (governance input `TEST_PASS_RATE` is computed but not gated)

---

## #6 — Deployment Capabilities

**What the customer wants to see:**
- Rolling upgrade, blue-green, canary
- Feature flag-based release control
- Rollback + backout to specific version
- ServiceNow / ITSM integration in release workflow

**What's built:** `cd-eks-canary.yaml` and `cd-eks-bluegreen.yaml` exist in `harness/pipelines/`

**Gaps to address:**
- Verify canary and blue-green pipelines are wired and runnable in the sandbox
- Feature flags: Harness FF is native — confirm it's enabled in the sandbox project
- ITSM: confirm ServiceNow connector exists or plan the "requires customization" answer
- Show rollback via the CD pipeline's built-in rollback step

---

## #7 — Dynamic Environment Configuration Injection

**What the customer wants to see:**
- Push-based config injection at deploy time
- Pull-based config updates without redeployment
- Immutable artifact promoted across environments without rebuild
- Secrets vs. non-sensitive config handled separately
- Config audit trail

**What's built:** Pipeline variables injected at runtime, HAR image promoted by tag

**Gaps to address:**
- Show Harness Config-as-Code or runtime overrides as the push model
- Pull-based model: show Harness Config Store or External Secrets Operator if used
- Demonstrate same image tag (`toddonedemoapp:1.0.X`) promoted from dev → staging → prod without rebuild

---

## #8 — DORA / Compliance Metrics / Audit Evidence

**What the customer wants to see:**
- DORA dashboard (deployment freq, lead time, change failure rate, MTTR)
- Pipeline execution trends, failure hotspots, stage duration analysis
- Compliance metrics: policy compliance rate, approval compliance, deployment traceability
- Audit evidence: who approved/deployed what and when, immutable + exportable

**What's built:** Pipeline captures SBOM (SPDX-JSON), SLSA provenance, OCI image labels with commit/execution metadata

**Gaps to address:**
- Enable Harness SEI (Software Engineering Insights) in sandbox or confirm it's available
- Show the Audit Trail UI for the pipeline execution
- SBOM and provenance are generated — show them in the STO / Supply Chain UI
- Confirm compliance evidence is surfaced at account/org/project level

---

## #9 — Schedule-based CI/CD

**What the customer wants to see:**
- Scheduled pipeline (e.g., monthly patching)
- Recurring pipeline governance, approvals, notifications

**What's built:** `sandbox_ttl_cleanup_cron.yaml` trigger exists in `.harness/triggers/`

**Gaps to address:**
- Create a demo-friendly scheduled trigger on the CI pipeline (e.g., nightly build)
- Show approval step + notification wired into a scheduled run

---

## #10 — Event-driven CI/CD

**What the customer wants to see:**
- Event-driven trigger (e.g., zero-day CVE response)
- Platform triggering rebuilds, re-scans, cache invalidation, emergency deployment

**What's built:** Auto-deploy webhook trigger to CD pipeline exists in `Trigger CD Pipeline` step

**Gaps to address:**
- Create a custom webhook trigger that simulates a zero-day response: invalidates cache key + triggers rebuild
- Show how an external security feed (or manual event) fires the pipeline with `--no-build-cache` to force cold rebuild

---

## #11 — AI-enabled IDE Integration ✅ IN PROGRESS

**What the customer wants to see:**
- Developer stays in IDE, opens PR, interacts with Harness without leaving VS Code
- Pipeline status, logs, failed stages surfaced in IDE
- AI helps diagnose and fix build/test/gate/deployment failures

**What's built:** Claude Code + Harness MCP server (`harness-mcp-v2`) configured in `~/.claude/settings.json`; Harness Docs MCP server in `.vscode/mcp.json`

**Gaps to address:**
- Verify Harness MCP server connects after VS Code restart (auth issue being investigated)
- Build a demo script: push a breaking change → CI fails → diagnose in IDE with Claude → fix → repush
- Show pipeline execution lookup, log fetch, and fix suggestion without leaving VS Code

---

## #12 — DR / Regional Failover

**What the customer wants to see:**
- Platform-level DR: what happens when Harness SaaS fails over
- Developer experience during failover (zero or minimal disruption)
- RTO/RPO, in-flight pipeline preservation, audit evidence continuity

**What's built:** N/A — this is a Harness SaaS platform characteristic, not a sandbox config item

**Gaps to address:**
- Prepare talking points on Harness SaaS multi-region architecture (this is a "native" answer)
- For self-managed / on-prem variant: show delegate failover across regions
- Prepare honest answer on in-flight pipeline state during failover

---

## Priority Order

1. **#1** — Template governance / OPA policy story (first 5 min of demo)
2. **#4** — Policy enforcement in CI with visible gate behavior
3. **#11** — AI-IDE loop (Claude Code + Harness MCP) — high differentiator
4. **#6** — Canary/blue-green deploy verification
5. **#5** — Test parallelization + RestAssured gap
6. **#3** — HAR upstream proxy confirmation
7. **#8** — DORA / audit evidence surfacing
8. **#9/#10** — Scheduled + event-driven triggers
9. **#7** — Config injection story
10. **#12** — DR talking points
