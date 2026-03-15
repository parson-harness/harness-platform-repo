# Harness Delegate & Cloud Connector Permissions Guide

A reference for understanding when permissions issues come from the delegate vs. the connector, and the recommended setup for POVs.

---

## TL;DR - Recommendations

### Best Practice: Workload Identity (GCP) / IRSA (AWS)

**Most secure, recommended for all engagements.** Requires ~15 min upfront setup but provides:
- ✅ No long-lived credentials to rotate or leak
- ✅ Audit trail tied to specific workloads
- ✅ Follows zero-trust / least-privilege principles
- ✅ What security-conscious customers expect

| Cloud | Recommended Setup |
|-------|-------------------|
| **GCP** | Enable Workload Identity → Create GCP SA with roles → Bind K8s SA to GCP SA → Use "Inherit from Delegate" |
| **AWS** | Enable IRSA on cluster → Create IAM Role with policies → Bind K8s SA to IAM Role → Use "Inherit from Delegate" |

### Fallback: Service Account Key / Access Key

**Quick setup when Workload Identity/IRSA isn't feasible** (e.g., VM-based delegate, time constraints):

| Cloud | Fallback Setup |
|-------|----------------|
| **GCP** | Create GCP SA → Download JSON key → Store as Harness File Secret → Use in GCP Connector |
| **AWS** | Create IAM User → Generate Access Key → Store as Harness Secrets → Use in AWS Connector |

This approach:
- ✅ Works regardless of delegate installation method
- ✅ No node pool/instance profile configuration needed
- ⚠️ Long-lived credentials (less secure, requires rotation)

---

## Understanding the Auth Flow

### When Connector is "Inherit from Delegate"

```
Harness Pipeline
    ↓
Delegate Pod (runs the task)
    ↓
Cloud SDK (gcloud/aws cli)
    ↓
Node's Metadata Service (gets credentials)
    ↓
Cloud API
```

**The delegate pod uses whatever credentials the node has.** This means:

| Cloud | What Provides Credentials | What Limits Access |
|-------|---------------------------|-------------------|
| **GKE** | Node's metadata service | Node Pool OAuth Scopes + SA IAM Roles |
| **EKS** | Node's instance metadata | Instance Profile IAM Role |

### The "Scopes vs IAM" Gotcha (GCP)

GCP has **two layers** of permission checks:

1. **OAuth Scopes** (on the node pool) - What APIs the metadata service can access
2. **IAM Roles** (on the service account) - What actions are allowed

**Both must permit the action.** Scopes are a ceiling.

Example failure:
- Service Account has `roles/run.admin` ✅
- Node Pool scope is `compute-rw` only ❌
- Result: `ACCESS_TOKEN_SCOPE_INSUFFICIENT`

### Default Harness Delegate Permissions

When you install a delegate with the default Harness YAML:

| Platform | Default Auth | Default Permissions |
|----------|--------------|---------------------|
| **GKE (default install)** | Node metadata | Whatever the node pool was created with (often just `compute-rw`, `logging-write`) |
| **EKS (default install)** | Node metadata | Whatever the node's instance profile has |
| **VM (Docker delegate)** | Instance metadata | Whatever the VM's service account/instance profile has |

**The delegate itself doesn't request special permissions** - it just uses what the underlying compute has.

---

## Connector Auth Options

### GCP Connector

| Auth Type | How It Works | Delegate Dependency | Recommended For |
|-----------|--------------|---------------------|-----------------|
| **Inherit from Delegate** (with Workload Identity) | K8s SA → GCP SA mapping | Medium - needs WI setup + annotation | **All engagements** ✅ |
| **Service Account Key** | Uses JSON key file directly | Low - just needs network access | Fallback when WI not possible |
| **Inherit from Delegate** (without WI) | Uses node metadata credentials | High - needs node scopes + SA roles | Not recommended |

### AWS Connector

| Auth Type | How It Works | Delegate Dependency | Recommended For |
|-----------|--------------|---------------------|-----------------|
| **Inherit from Delegate (IRSA)** | K8s SA → IAM Role mapping | Medium - needs IRSA setup | **All engagements** ✅ |
| **Access Key / Secret Key** | Uses IAM user credentials | Low - just needs network access | Fallback when IRSA not possible |
| **Assume Role (STS)** | Assumes a role via STS | Medium - needs base role that can assume | Cross-account |

---

## Troubleshooting Decision Tree

```
Permission Error in Pipeline
           │
           ▼
    ┌──────────────────┐
    │ What auth type   │
    │ is the connector │
    │ using?           │
    └────────┬─────────┘
             │
     ┌───────┴───────┐
     ▼               ▼
 "Inherit"      "SA Key" or
                "Access Key"
     │               │
     ▼               ▼
 Check BOTH:     Check ONLY:
 1. Delegate     1. The SA/User
    node perms      IAM permissions
 2. SA/Role
    IAM perms
```

### "Inherit from Delegate" - What to Check

**GCP:**
```bash
# 1. What service account is the node using?
gcloud compute instances describe NODE_NAME --zone=ZONE \
  --format='get(serviceAccounts[0].email)'

# 2. What scopes does the node have?
gcloud compute instances describe NODE_NAME --zone=ZONE \
  --format='get(serviceAccounts[0].scopes)'

# 3. What IAM roles does that SA have?
gcloud projects get-iam-policy PROJECT_ID \
  --filter="bindings.members:SERVICE_ACCOUNT_EMAIL" \
  --flatten="bindings[].members"
```

**AWS:**
```bash
# 1. What instance profile is the node using?
aws ec2 describe-instances --instance-ids INSTANCE_ID \
  --query 'Reservations[].Instances[].IamInstanceProfile.Arn'

# 2. What role is attached to that profile?
aws iam get-instance-profile --instance-profile-name PROFILE_NAME

# 3. What policies are on that role?
aws iam list-attached-role-policies --role-name ROLE_NAME
```

### "Service Account Key" / "Access Key" - What to Check

Just check the IAM permissions on that specific SA/User. Node config doesn't matter.

---

## Setting Up Workload Identity / IRSA (Recommended)

### GCP: Workload Identity

```bash
# 1. Enable Workload Identity on cluster (one-time, may already be enabled)
gcloud container clusters update CLUSTER_NAME \
  --zone=ZONE \
  --workload-pool=PROJECT_ID.svc.id.goog

# 2. Create GCP service account for Harness
gcloud iam service-accounts create harness-delegate-sa \
  --display-name="Harness Delegate SA"

# 3. Grant needed roles (adjust based on what you're deploying)
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-delegate-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-delegate-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-delegate-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# 4. Allow K8s SA to impersonate GCP SA
# Replace NAMESPACE and K8S_SA_NAME with delegate's namespace and service account
gcloud iam service-accounts add-iam-policy-binding \
  harness-delegate-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/K8S_SA_NAME]"

# 5. Annotate the delegate's K8s service account
kubectl annotate serviceaccount K8S_SA_NAME \
  --namespace NAMESPACE \
  iam.gke.io/gcp-service-account=harness-delegate-sa@PROJECT_ID.iam.gserviceaccount.com
```

Then in Harness:
1. **Connectors** → GCP → Auth: **Inherit from Delegate**
2. Select the delegate running in the annotated namespace

### AWS: IRSA (IAM Roles for Service Accounts)

```bash
# 1. Associate OIDC provider with cluster (one-time)
eksctl utils associate-iam-oidc-provider --cluster CLUSTER_NAME --approve

# 2. Create IAM role bound to K8s service account
# This creates both the IAM role and annotates the K8s SA
eksctl create iamserviceaccount \
  --cluster=CLUSTER_NAME \
  --namespace=NAMESPACE \
  --name=harness-delegate-sa \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --attach-policy-arn=arn:aws:iam::aws:policy/AWSLambda_FullAccess \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonS3FullAccess \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess \
  --approve

# If delegate already exists with a different SA, update the delegate to use this SA
# Or annotate the existing SA manually:
kubectl annotate serviceaccount EXISTING_SA_NAME \
  --namespace NAMESPACE \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME
```

Then in Harness:
1. **Connectors** → AWS → Auth: **Use IRSA** (or "Inherit from Delegate")
2. Select the delegate running with the annotated service account

---

## Setting Up SA Key / Access Key Auth (Fallback)

### GCP

```bash
# 1. Create service account
gcloud iam service-accounts create harness-pov-sa \
  --display-name="Harness POV Service Account"

# 2. Grant roles (adjust based on what you're deploying)
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-pov-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-pov-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:harness-pov-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

# 3. Create and download key
gcloud iam service-accounts keys create ~/harness-pov-sa-key.json \
  --iam-account=harness-pov-sa@PROJECT_ID.iam.gserviceaccount.com
```

Then in Harness:
1. **Secrets** → New Secret → **File** → Upload the JSON key
2. **Connectors** → GCP → Auth: **Service Account Key** → Select the secret

### AWS

```bash
# 1. Create IAM user
aws iam create-user --user-name harness-pov-user

# 2. Attach policies (adjust based on what you're deploying)
aws iam attach-user-policy --user-name harness-pov-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam attach-user-policy --user-name harness-pov-user \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess

aws iam attach-user-policy --user-name harness-pov-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# 3. Create access key
aws iam create-access-key --user-name harness-pov-user
```

Then in Harness:
1. **Secrets** → New Secret → **Text** → Store Access Key ID
2. **Secrets** → New Secret → **Text** → Store Secret Access Key
3. **Connectors** → AWS → Auth: **Access Key** → Select both secrets

---

## Common GCP Roles for POVs

| Service | Role | Description |
|---------|------|-------------|
| Cloud Run | `roles/run.admin` | Full Cloud Run access |
| GKE | `roles/container.developer` | Deploy to GKE (not create clusters) |
| GKE | `roles/container.admin` | Full GKE access including cluster creation |
| Artifact Registry | `roles/artifactregistry.writer` | Push images |
| Cloud Storage | `roles/storage.admin` | Full GCS access |
| Compute | `roles/compute.admin` | Full Compute Engine access |

**Broad option:** `roles/editor` gives most permissions (not recommended for prod, fine for POVs)

---

## Common AWS Policies for POVs

| Service | Policy | Description |
|---------|--------|-------------|
| EC2/ASG | `AmazonEC2FullAccess` | Full EC2 and ASG access |
| Lambda | `AWSLambda_FullAccess` | Full Lambda access |
| EKS | `AmazonEKSClusterPolicy` | EKS cluster access |
| ECR | `AmazonEC2ContainerRegistryFullAccess` | Push/pull images |
| S3 | `AmazonS3FullAccess` | Full S3 access |
| IAM (limited) | `IAMReadOnlyAccess` | Read IAM (for some Harness features) |

**Broad option:** `AdministratorAccess` gives everything (not recommended for prod, fine for POVs)

---

## Summary: When to Look Where

| Symptom | Connector Auth | Check |
|---------|----------------|-------|
| `ACCESS_TOKEN_SCOPE_INSUFFICIENT` | Inherit from Delegate | Node pool scopes (GCP) |
| `AccessDenied` / `UnauthorizedAccess` | Inherit from Delegate | Node instance profile (AWS) or SA IAM roles |
| `AccessDenied` / `UnauthorizedAccess` | SA Key / Access Key | The specific SA/User IAM permissions |
| Delegate can't start | N/A | Delegate's own permissions (usually just needs outbound HTTPS) |

---

## Fixing Node-Level Permission Issues (GKE vs EKS)

When using "Inherit from Delegate" without Workload Identity/IRSA, you may hit node-level permission issues. Here's how they differ:

### GKE: OAuth Scopes Are Immutable

**Problem:** Node pool was created without `cloud-platform` scope.

**Can you fix without new nodes?** ❌ **No** - OAuth scopes are set at node pool creation and cannot be changed.

**Options:**
1. **Create new node pool** with correct scopes, migrate delegate:
   ```bash
   # Create new node pool with cloud-platform scope
   gcloud container node-pools create new-pool \
     --cluster=CLUSTER_NAME \
     --zone=ZONE \
     --scopes=cloud-platform
   
   # Delete old node pool (pods will reschedule)
   gcloud container node-pools delete old-pool \
     --cluster=CLUSTER_NAME \
     --zone=ZONE
   ```

2. **Use Workload Identity** (bypasses scopes entirely) - see setup above

3. **Use SA Key in connector** (bypasses scopes entirely)

### EKS: Instance Profile Can Be Updated

**Problem:** Node's IAM instance profile doesn't have required policies.

**Can you fix without new nodes?** ✅ **Yes** - you can add policies to the existing IAM role.

**Fix:**
```bash
# 1. Find the IAM role attached to the node group
ROLE_NAME=$(aws eks describe-nodegroup \
  --cluster-name CLUSTER_NAME \
  --nodegroup-name NODEGROUP_NAME \
  --query 'nodegroup.nodeRole' --output text | cut -d'/' -f2)

# 2. Attach additional policies to that role
aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess

aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Changes take effect immediately - no node restart needed
```

**Or use IRSA** (bypasses instance profile entirely) - see setup above

### Comparison Summary

| Cloud | Issue | Fix Without New Nodes? | Recommended Fix |
|-------|-------|------------------------|-----------------|
| **GKE** | Node pool OAuth scopes too narrow | ❌ No - scopes are immutable | Use Workload Identity |
| **EKS** | Node IAM instance profile missing policies | ✅ Yes - add policies to role | Use IRSA (or update role) |

**Key takeaway:** This is another reason Workload Identity (GKE) and IRSA (EKS) are the recommended approach - they bypass node-level permissions entirely, avoiding these issues.

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│                    PERMISSION TROUBLESHOOTING                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Connector Auth = "Inherit from Delegate" (with WI/IRSA)        │
│  ───────────────────────────────────────────────────────        │
│  Check the GCP SA or IAM Role bound to the K8s service account  │
│  Verify the annotation is correct on the delegate's K8s SA      │
│                                                                 │
│  Connector Auth = "Inherit from Delegate" (without WI/IRSA)     │
│  ───────────────────────────────────────────────────────────    │
│  GCP: Check node pool SCOPES + service account IAM ROLES        │
│  AWS: Check node INSTANCE PROFILE IAM policies                  │
│                                                                 │
│  Connector Auth = "Service Account Key" / "Access Key"          │
│  ─────────────────────────────────────────────────────          │
│  Just check the SA/User IAM permissions directly                │
│  Node config doesn't matter                                     │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RECOMMENDATION: Workload Identity (GCP) / IRSA (AWS)           │
│  - Most secure (no long-lived credentials)                      │
│  - ~15 min setup, professional recommendation                   │
│  - What security-conscious customers expect                     │
│                                                                 │
│  FALLBACK: SA Key / Access Key in connector                     │
│  - When WI/IRSA not feasible (VM delegate, time constraints)    │
│  - Works regardless of delegate setup                           │
│  - Requires credential rotation                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
