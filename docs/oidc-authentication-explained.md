# OIDC Authentication Explained

A reference for understanding OIDC (OpenID Connect) and how it differs from other authentication methods in Harness and cloud providers.

---

## TL;DR - Recommendations

| Scenario | Recommendation |
|----------|----------------|
| **IACM on Harness Cloud** | OIDC (no delegate needed) |
| **Delegate in EKS** | IRSA (pod-level identity) |
| **Delegate in GKE** | Workload Identity |
| **Quick POV setup** | Access Keys (less secure, but fast) |
| **VM-based delegate** | Access Keys or Instance Profile |

---

## The Problem OIDC Solves

### Traditional Approach: Long-Lived Credentials

```
┌─────────────────────────────────────────────────────────────────┐
│  The Old Way: Static Access Keys                                │
└─────────────────────────────────────────────────────────────────┘

  1. Create IAM User
  2. Generate Access Key + Secret Key
  3. Store in Harness as secrets
  4. Connector uses these credentials
  
  Problems:
  ❌ Keys never expire (until you rotate them)
  ❌ Keys can be leaked/stolen
  ❌ Hard to audit "who used this key?"
  ❌ Keys work from anywhere (no context)
  ❌ Manual rotation required
```

### Modern Approach: OIDC (Temporary Credentials)

```
┌─────────────────────────────────────────────────────────────────┐
│  The OIDC Way: Short-Lived Tokens                               │
└─────────────────────────────────────────────────────────────────┘

  1. Harness says "I am account XYZ, connector ABC"
  2. AWS says "I trust Harness as an identity provider"
  3. AWS gives Harness a temporary token (15 min - 1 hour)
  4. Harness uses token, then it expires
  
  Benefits:
  ✅ No long-lived secrets to manage
  ✅ Tokens expire automatically
  ✅ Full audit trail (who, what, when, where)
  ✅ Context-aware (only works from Harness)
  ✅ No rotation needed
```

---

## How OIDC Works (Step by Step)

### The Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Harness needs to access AWS                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Harness creates a JWT (JSON Web Token)                      │
│                                                                 │
│  {                                                              │
│    "iss": "https://app.harness.io/ng/api/oidc/account/ABC123", │
│    "sub": "account/ABC123:org/default:project/MyProject",       │
│    "aud": "sts.amazonaws.com",                                  │
│    "exp": 1718132139,  // expires in 1 hour                     │
│    "account_id": "ABC123",                                      │
│    "connector_id": "aws_oidc",                                  │
│    "context": "PIPELINE_EXECUTION"                              │
│  }                                                              │
│                                                                 │
│  Signed with Harness's private key                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Harness calls AWS STS (Security Token Service)              │
│                                                                 │
│  "Hey AWS, here's my JWT. I want to assume role                 │
│   arn:aws:iam::123456789:role/HarnessOIDCRole"                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. AWS validates the JWT                                       │
│                                                                 │
│  a) Fetches Harness's public key from OIDC endpoint             │
│  b) Verifies JWT signature (proves it came from Harness)        │
│  c) Checks JWT claims match role's trust policy                 │
│  d) Checks JWT hasn't expired                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. AWS returns temporary credentials                           │
│                                                                 │
│  {                                                              │
│    "AccessKeyId": "ASIA...",                                    │
│    "SecretAccessKey": "wJalr...",                               │
│    "SessionToken": "FwoGZX...",                                 │
│    "Expiration": "2024-06-11T20:00:00Z"  // 1 hour              │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. Harness uses these temp credentials for AWS API calls       │
│     (credentials auto-expire, no cleanup needed)                │
└─────────────────────────────────────────────────────────────────┘
```

### The Trust Relationship

For OIDC to work, AWS must trust Harness as an identity provider:

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Account                                                    │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  IAM Identity Provider                                     │ │
│  │                                                            │ │
│  │  Provider URL: https://app.harness.io/ng/api/oidc/        │ │
│  │                account/EeRjnXTnS4GrLG5VNNJZUw             │ │
│  │  Audience: sts.amazonaws.com                               │ │
│  │  Thumbprint: df3c24f9bfd666761b268073fe06d1cc8d4f82a4     │ │
│  │                                                            │ │
│  │  "I trust JWTs signed by Harness for this account"         │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  IAM Role: HarnessOIDCRole                                 │ │
│  │                                                            │ │
│  │  Trust Policy:                                             │ │
│  │  {                                                         │ │
│  │    "Effect": "Allow",                                      │ │
│  │    "Principal": {                                          │ │
│  │      "Federated": "arn:aws:iam::123:oidc-provider/..."    │ │
│  │    },                                                      │ │
│  │    "Action": "sts:AssumeRoleWithWebIdentity",              │ │
│  │    "Condition": {                                          │ │
│  │      "StringEquals": {                                     │ │
│  │        "...:aud": "sts.amazonaws.com"                      │ │
│  │      }                                                     │ │
│  │    }                                                       │ │
│  │  }                                                         │ │
│  │                                                            │ │
│  │  Permissions: AmazonEKSClusterPolicy, etc.                 │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Comparison: OIDC vs IRSA vs Access Keys

### Authentication Methods at a Glance

| Method | Where It Runs | Credentials | Security | Setup Complexity |
|--------|---------------|-------------|----------|------------------|
| **OIDC** | Harness Cloud | Temporary tokens | ⭐⭐⭐⭐⭐ | Medium |
| **IRSA** | Delegate in EKS | Temporary tokens | ⭐⭐⭐⭐⭐ | Medium |
| **Access Keys** | Anywhere | Static keys | ⭐⭐ | Easy |
| **Instance Profile** | EC2/EKS nodes | Temporary tokens | ⭐⭐⭐⭐ | Easy |

### OIDC (OpenID Connect)

```
┌─────────────────────────────────────────────────────────────────┐
│  OIDC: For Harness Cloud (no delegate)                          │
└─────────────────────────────────────────────────────────────────┘

  Harness Platform ──JWT──▶ AWS STS ──temp creds──▶ AWS APIs
  
  ✅ No delegate required
  ✅ Works with IACM, CI on Harness Cloud
  ✅ No secrets to manage
  ✅ Fine-grained: can scope to org/project/connector
  
  ❌ Requires IAM OIDC provider setup in AWS
  ❌ Only works from Harness platform (not delegate)
```

**When to use:** IACM workspaces, CI steps on Harness Cloud, any Harness-managed infrastructure.

### IRSA (IAM Roles for Service Accounts)

```
┌─────────────────────────────────────────────────────────────────┐
│  IRSA: For Delegates running in EKS                             │
└─────────────────────────────────────────────────────────────────┘

  Delegate Pod ──K8s SA──▶ AWS STS ──temp creds──▶ AWS APIs
  
  The delegate pod has a Kubernetes Service Account that's
  linked to an AWS IAM Role. The pod gets temporary AWS
  credentials automatically via the EKS OIDC provider.
  
  ✅ No secrets in the pod
  ✅ Automatic credential rotation
  ✅ Pod-level identity (not node-level)
  ✅ Works with "Inherit from Delegate" connector
  
  ❌ Only works in EKS
  ❌ Requires EKS OIDC provider + IAM role setup
  ❌ Requires delegate running in the cluster
```

**When to use:** Delegates running in EKS that need AWS access.

### Access Keys (Static Credentials)

```
┌─────────────────────────────────────────────────────────────────┐
│  Access Keys: Works anywhere, but less secure                   │
└─────────────────────────────────────────────────────────────────┘

  Harness Secrets ──Access Key + Secret──▶ AWS APIs
  
  ✅ Simple setup
  ✅ Works from anywhere (delegate, Harness Cloud, etc.)
  ✅ No IAM provider configuration needed
  
  ❌ Long-lived credentials (security risk)
  ❌ Must rotate manually
  ❌ Can be leaked/stolen
  ❌ Hard to audit usage
```

**When to use:** Quick POV setup, VM-based delegates, when OIDC/IRSA isn't feasible.

---

## Setting Up OIDC for Harness

### Step 1: Create OIDC Identity Provider in AWS

```bash
# Get your Harness account ID (e.g., EeRjnXTnS4GrLG5VNNJZUw)

aws iam create-open-id-connect-provider \
  --url "https://app.harness.io/ng/api/oidc/account/YOUR_ACCOUNT_ID" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "df3c24f9bfd666761b268073fe06d1cc8d4f82a4"
```

### Step 2: Create IAM Role with Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_AWS_ACCOUNT:oidc-provider/app.harness.io/ng/api/oidc/account/YOUR_HARNESS_ACCOUNT"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "app.harness.io/ng/api/oidc/account/YOUR_HARNESS_ACCOUNT:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Step 3: Attach Permissions to Role

```bash
aws iam attach-role-policy \
  --role-name HarnessOIDCRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Add other policies as needed
```

### Step 4: Create Harness Connector

```yaml
connector:
  name: AWS OIDC
  identifier: aws_oidc
  type: Aws
  spec:
    credential:
      type: OidcAuthentication
      spec:
        iamRoleArn: arn:aws:iam::123456789:role/HarnessOIDCRole
        region: us-east-1
    delegateSelectors: []  # Empty - runs on Harness Cloud
    executeOnDelegate: false
```

---

## Scoping OIDC Access

You can restrict which Harness resources can use the AWS role:

### Scope to Specific Project

```json
{
  "Condition": {
    "StringEquals": {
      "...:sub": "account/ABC123:org/default:project/MyProject"
    }
  }
}
```

### Scope to Specific Organization

```json
{
  "Condition": {
    "StringLike": {
      "...:sub": "account/ABC123:org/production:project/*"
    }
  }
}
```

### Scope to Specific Connector

The JWT includes `connector_id`, so you could theoretically scope to specific connectors (requires custom policy logic).

---

## Troubleshooting OIDC

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `InvalidIdentityToken` | OIDC provider not set up | Create IAM OIDC provider |
| `AccessDenied` | Role trust policy wrong | Check trust policy conditions |
| `ExpiredToken` | JWT expired | Retry (Harness will get new token) |
| `NotAuthorizedToAssumeRole` | Audience mismatch | Ensure `aud` is `sts.amazonaws.com` |

### Debugging Steps

1. **Check OIDC provider exists:**
   ```bash
   aws iam list-open-id-connect-providers
   ```

2. **Check role trust policy:**
   ```bash
   aws iam get-role --role-name HarnessOIDCRole \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. **Test connector in Harness:**
   - Go to connector → Test Connection
   - Check for specific error messages

4. **Check CloudTrail:**
   - Look for `AssumeRoleWithWebIdentity` events
   - Error details will show why it failed

---

## OIDC vs IRSA: When to Use Which

```
┌─────────────────────────────────────────────────────────────────┐
│  Decision Tree                                                  │
└─────────────────────────────────────────────────────────────────┘

  Is the workload running on Harness Cloud?
  │
  ├─ YES → Use OIDC
  │        (IACM, CI on Harness Cloud)
  │
  └─ NO → Is the delegate in EKS?
          │
          ├─ YES → Use IRSA
          │        (Delegate inherits pod identity)
          │
          └─ NO → Is the delegate on EC2?
                  │
                  ├─ YES → Use Instance Profile
                  │        (Delegate inherits node identity)
                  │
                  └─ NO → Use Access Keys
                          (VM, on-prem, etc.)
```

---

## Key Takeaways

1. **OIDC eliminates long-lived credentials** - No access keys to rotate or leak

2. **OIDC works for Harness Cloud** - When there's no delegate involved

3. **IRSA is OIDC for pods** - Same concept, but for workloads in EKS

4. **Trust policies control access** - AWS decides who can assume the role

5. **Temporary credentials are automatic** - Harness handles token refresh

6. **Audit trail is built-in** - CloudTrail shows exactly what happened

---

## Related Concepts

| Term | What It Means |
|------|---------------|
| **JWT** | JSON Web Token - signed claim about identity |
| **STS** | AWS Security Token Service - issues temporary credentials |
| **IRSA** | IAM Roles for Service Accounts - OIDC for K8s pods |
| **Workload Identity** | GCP's version of IRSA |
| **Federated Identity** | External identity provider trusted by cloud |
| **Trust Policy** | IAM policy defining who can assume a role |
| **Web Identity** | Identity from an OIDC provider (vs IAM user) |
