# Harness ASG Blue-Green Deployment Reference

## Overview

This document explains how AMIs, ASGs, and Harness Blue-Green deployments with traffic shifting work together.

---

## Key Concepts

### AMI (Amazon Machine Image)

A pre-configured template containing:
- Operating system (Amazon Linux 2)
- Pre-installed software (Java 11)
- Your application (Spring Boot JAR)
- System configuration (systemd service)

**Think of it as**: A "snapshot" of a fully configured server that can launch identical EC2 instances.

### Packer

Tool that automates AMI creation. Defined in code, it:
1. Launches a temporary EC2 instance
2. Runs provisioners (install Java, copy JAR, configure systemd)
3. Creates an AMI from the configured instance
4. Terminates the temporary instance

**Why needed**: Harness ASG deployments require an AMI as the artifact (not a JAR or Docker image).

### ASG (Auto Scaling Group)

Uses a Launch Template (which references an AMI) to:
- Automatically launch identical instances
- Scale up/down based on demand
- Replace unhealthy instances

---

## Harness Blue-Green with Traffic Shifting

### Infrastructure Setup

```
ALB (Application Load Balancer)
 │
 └── Listener Rule (weighted forward)
      │
      ├── prod-tg  (weight: 100) ──► OLD ASG (v1 AMI)
      │
      └── stage-tg (weight: 0)   ──► empty (or NEW ASG during deployment)
```

**Key components**:
- **Two target groups**: `prod-tg` and `stage-tg` (permanent infrastructure)
- **Weighted listener rule**: Distributes traffic between target groups
- **ASGs**: Created/destroyed by Harness during deployments

### Deployment Flow

```
STEP 1: Initial State
─────────────────────────────────────────────────────────
  prod-tg  (100%) ──► OLD ASG (v1 AMI)
  stage-tg (0%)   ──► empty


STEP 2: Deploy New Version
─────────────────────────────────────────────────────────
  Harness creates NEW ASG with v2 AMI, attaches to stage-tg
  
  prod-tg  (100%) ──► OLD ASG (v1 AMI)
  stage-tg (0%)   ──► NEW ASG (v2 AMI) ← just created


STEP 3: Traffic Shift 10%
─────────────────────────────────────────────────────────
  prod-tg  (90%)  ──► OLD ASG (v1 AMI)
  stage-tg (10%)  ──► NEW ASG (v2 AMI)
  
  [APPROVAL GATE - verify new version works]


STEP 4: Traffic Shift 50%
─────────────────────────────────────────────────────────
  prod-tg  (50%)  ──► OLD ASG (v1 AMI)
  stage-tg (50%)  ──► NEW ASG (v2 AMI)
  
  [APPROVAL GATE - verify at higher load]


STEP 5: Traffic Shift 100% + Downsize Old
─────────────────────────────────────────────────────────
  prod-tg  (0%)   ──► OLD ASG terminated
  stage-tg (100%) ──► NEW ASG (v2 AMI)
  
  Deployment complete!
```

### Target Group Role Swapping

The target groups **don't rename** - their roles alternate:

| Deployment | prod-tg | stage-tg |
|------------|---------|----------|
| Initial | v1 (live) | empty |
| After deploy 1 | empty | v2 (live) |
| After deploy 2 | v3 (live) | empty |
| After deploy 3 | empty | v4 (live) |

**Harness tracks** which TG currently has production traffic and deploys to the "other" one.

---

## Rollback on Failure

### When Failure Occurs (during traffic shift)

```
FAILURE STATE (e.g., at 50% traffic):
─────────────────────────────────────────────────────────
  prod-tg  (50%)  ──► OLD ASG (v1 AMI) ✓ healthy
  stage-tg (50%)  ──► NEW ASG (v2 AMI) ✗ errors!

Detected via:
  - Health check failures on /actuator/health
  - Error rate spike
  - Manual observation during approval gate
```

### Rollback Action

```
AFTER ROLLBACK:
─────────────────────────────────────────────────────────
  1. Shift ALL traffic back to prod-tg (100%)
  2. stage-tg goes to 0%
  3. Terminate NEW ASG (v2 AMI)
  4. OLD ASG remains untouched

  prod-tg  (100%) ──► OLD ASG (v1 AMI) ✓
  stage-tg (0%)   ──► NEW ASG terminated
```

### Why Rollback is Safe

| Component | On Failure |
|-----------|------------|
| **Old ASG** | Never touched until 100% cutover - always available |
| **New ASG** | Terminated during rollback |
| **Traffic** | Instantly shifted back (just a weight change) |
| **Old AMI** | Still exists - can redeploy if needed |

---

## Pipeline Configuration

### Key Steps

1. **ASG Blue Green Deploy** - Creates new ASG, attaches to stage TG
2. **ASG Traffic Shift** - Adjusts listener rule weights
3. **Approval** - Manual gate to verify before proceeding
4. **ASG Blue Green Rollback** - Reverts on failure

### Required Harness Inputs

| Input | Source |
|-------|--------|
| AMI ID | Packer build output (artifact) |
| Prod Listener ARN | `terraform output prod_listener_arn` |
| Listener Rule ARN | `terraform output weighted_listener_rule_arn` |
| Load Balancer | `spring-boot-hello-world-alb` |

### Sample Pipeline Flow

```yaml
execution:
  steps:
    - ASG Blue Green Deploy    # Create new ASG with new AMI
    - ASG Traffic Shift (10%)  # Canary test
    - Approval                 # Manual verification
    - ASG Traffic Shift (50%)  # Increase load
    - Approval                 # Manual verification  
    - ASG Traffic Shift (100%) # Full cutover, downsize old
  rollbackSteps:
    - ASG Blue Green Rollback  # Revert traffic, terminate new ASG
```

---

## Full Deployment Lifecycle

```
1. Build JAR (Maven)
       ↓
2. Build AMI (Packer) - bakes JAR into AMI
       ↓
3. Harness detects new AMI (artifact)
       ↓
4. Harness creates new ASG from AMI
       ↓
5. Traffic shifts incrementally (10% → 50% → 100%)
       ↓
6. Old ASG terminated after full cutover
```

---

## Quick Reference

| Term | Definition |
|------|------------|
| **AMI** | Immutable server image with OS + app baked in |
| **Packer** | Tool to automate AMI creation |
| **ASG** | Group of identical EC2 instances from same AMI |
| **Launch Template** | Config that tells ASG which AMI to use |
| **Target Group** | ALB destination that routes to ASG instances |
| **Weighted Rule** | ALB rule that splits traffic by percentage |
| **Blue-Green** | Strategy using two environments for zero-downtime deploys |
| **Traffic Shift** | Gradual movement of traffic from old to new |
