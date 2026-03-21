# Bootstrap Setup Log

Manual steps performed outside of IaC code to stand up `harness-demo.dev`.
Run these **once per Harness account** before any POV/SE sandbox can be provisioned.

---

## 1. Route53 Hosted Zone

Created via `tofu apply` in this directory.

- **Zone ID:** `Z031547912F6D8STOXRA2`
- **Domain:** `harness-demo.dev`
- **Nameservers:**
  ```
  ns-1435.awsdns-51.org
  ns-1749.awsdns-26.co.uk
  ns-471.awsdns-58.com
  ns-906.awsdns-49.net
  ```

**Managed by:** `dns.tf` → `aws_route53_zone.harness_demo`

---

## 2. Domain Registration

Route53 Domains does **not** support `.dev` (Google TLD), so the domain was registered externally.

- **Registrar:** Squarespace Domains
- **Domain:** `harness-demo.dev`
- **Manage domain:** https://account.squarespace.com/domains/managed/harness-demo.dev/dns/nameservers

**To update nameservers if ever needed:**
1. Go to the URL above → click **Domain Nameservers** in the left nav
2. Switch from "Squarespace nameservers" to **Custom nameservers**
3. Enter the 4 Route53 NS records listed in Section 1

**Not managed by Tofu** — renew annually at Squarespace.

---

## 3. ACM Wildcard Certificate

Requested via AWS CLI (Route53 Domains registration flow doesn't apply here):

```bash
aws acm request-certificate \
  --domain-name '*.harness-demo.dev' \
  --validation-method DNS \
  --region us-east-1
```

- **Certificate ARN:** `arn:aws:acm:us-east-1:759984737373:certificate/9c90d4f8-208d-46cd-bdc1-bc13f1759c05`
- **Status:** ISSUED
- **Covers:** `*.harness-demo.dev` (all subdomains — one per POV/SE owner)

DNS validation CNAME was added to Route53 and validation completed automatically.

**Managed by:** `dns.tf` → `aws_route53_record.acm_validation` + `aws_acm_certificate_validation.wildcard`

The cert ARN is set in `environments/sandbox/terraform.tfvars` as `acm_cert_arn` and flows through
to each provisioned Harness service as a service variable, enabling HTTPS on the shared ALB.

---

## 4. Wildcard CNAME ✅

- **Record:** `*.harness-demo.dev`
- **Points to:** `a700467810e044bd98b2eab0a4904dc3-c4f3ecf0aa89fcea.elb.us-east-1.amazonaws.com`
- **Status:** Active

**If the ALB DNS ever changes** (e.g. after cluster recreation), re-run:
```bash
cd tofu/bootstrap
tofu apply -var="owner=parson" \
  -var="alb_dns_name=$(kubectl get ingress -A -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')"
```

**Managed by:** `dns.tf` → `aws_route53_record.wildcard`

---

## 5. S3 State Backend + DynamoDB Lock

Created via `tofu apply` in this directory.

- **S3 Bucket:** `harness-demo-tfstate-parson-842eb3a5`
- **DynamoDB Table:** `harness-demo-tfstate-lock-parson`
- **Region:** `us-east-1`

**Managed by:** `main.tf`

Add this backend config to any new environment's `main.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "harness-demo-tfstate-parson-842eb3a5"
    key            = "harness-demo/<environment>/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "harness-demo-tfstate-lock-parson"
  }
}
```

---

## How It All Connects

```
Squarespace (registrar)
  └─ NS → Route53 hosted zone (Z031547912F6D8STOXRA2)
           ├─ *.harness-demo.dev  CNAME → shared ALB  (added after first deploy)
           └─ _d29c1e3c5b9cf27b1a10c48d5b5bab19  CNAME → ACM validation

Shared ALB (AWS Load Balancer Controller on EKS)
  ├─ {owner}.harness-demo.dev       → {owner}-demo-app-service        (primary / blue)
  └─ {owner}-stage.harness-demo.dev → {owner}-demo-app-service-stage  (green / canary)

ACM cert (*.harness-demo.dev)
  └─ Attached to ALB via ingress annotation: alb.ingress.kubernetes.io/certificate-arn
     Set per-owner via Harness service variable: certArn
```
