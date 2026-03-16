# AWS ALB: Dedicated vs Shared Load Balancers

A reference for understanding the difference between dedicated ALBs per application vs shared ALBs with path/host-based routing.

---

## TL;DR - Recommendations

| Scenario | Recommendation |
|----------|----------------|
| **POV / Demo** | Dedicated ALB per app (simpler, isolated) |
| **Production** | Shared ALB with Ingress Controller (cost-effective) |
| **Multi-tenant** | Shared ALB with host-based routing |

---

## The Two Approaches

### Approach 1: Dedicated ALB (What We Use)

Each Kubernetes Service of type `LoadBalancer` gets its own ALB.

```
┌─────────────────────────────────────────────────────────────────┐
│  Internet                                                       │
└─────────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐            ┌─────────────────┐
│  ALB (App A)    │            │  ALB (App B)    │
│  app-a.demo.com │            │  app-b.demo.com │
│  Port 80/443    │            │  Port 80/443    │
└─────────────────┘            └─────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐            ┌─────────────────┐
│  K8s Service A  │            │  K8s Service B  │
│  (LoadBalancer) │            │  (LoadBalancer) │
└─────────────────┘            └─────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐            ┌─────────────────┐
│  Pods (App A)   │            │  Pods (App B)   │
└─────────────────┘            └─────────────────┘
```

**How it works:**
1. You create a Kubernetes Service with `type: LoadBalancer`
2. AWS Cloud Controller Manager (running in EKS) sees this
3. It provisions a new ALB automatically
4. The ALB gets a DNS name like `a1b2c3d4.us-east-1.elb.amazonaws.com`
5. All traffic to that ALB goes to your service

**Pros:**
- ✅ Simple - one Service = one ALB
- ✅ Isolated - issues with one ALB don't affect others
- ✅ No shared config to manage
- ✅ Easy SSL termination per app

**Cons:**
- ❌ Cost - each ALB costs ~$16-25/month minimum
- ❌ Doesn't scale for many apps (10 apps = 10 ALBs = $160-250/month)
- ❌ Each ALB has its own DNS name (need Route53 for custom domains)

---

### Approach 2: Shared ALB with Ingress Controller

One ALB handles traffic for multiple applications, routing based on hostname or path.

```
┌─────────────────────────────────────────────────────────────────┐
│  Internet                                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Shared ALB     │
                    │  *.demo.com     │
                    │  Port 80/443    │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Ingress         │
                    │ Controller      │
                    │ (nginx/traefik) │
                    └─────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
        ┌───────────┐   ┌───────────┐   ┌───────────┐
        │ Service A │   │ Service B │   │ Service C │
        │ /app-a/*  │   │ /app-b/*  │   │ /app-c/*  │
        └───────────┘   └───────────┘   └───────────┘
              │               │               │
              ▼               ▼               ▼
        ┌───────────┐   ┌───────────┐   ┌───────────┐
        │  Pods A   │   │  Pods B   │   │  Pods C   │
        └───────────┘   └───────────┘   └───────────┘
```

**How it works:**
1. Install an Ingress Controller (nginx-ingress, AWS ALB Ingress Controller, Traefik)
2. The controller creates ONE ALB
3. You create Kubernetes `Ingress` resources that define routing rules
4. The controller configures the ALB's listener rules based on your Ingress specs
5. Traffic is routed to the correct service based on host/path

**Routing options:**

```yaml
# Host-based routing
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-a-ingress
spec:
  rules:
  - host: app-a.demo.com      # Route based on hostname
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-a
            port:
              number: 80

---
# Path-based routing
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shared-ingress
spec:
  rules:
  - host: demo.com
    http:
      paths:
      - path: /app-a           # Route based on URL path
        pathType: Prefix
        backend:
          service:
            name: app-a
            port:
              number: 80
      - path: /app-b
        pathType: Prefix
        backend:
          service:
            name: app-b
            port:
              number: 80
```

**Pros:**
- ✅ Cost-effective - one ALB for many apps
- ✅ Centralized SSL/TLS management
- ✅ Advanced routing (headers, weights, etc.)
- ✅ Standard Kubernetes pattern

**Cons:**
- ❌ More complex setup
- ❌ Shared fate - Ingress Controller issues affect all apps
- ❌ Need to manage Ingress resources
- ❌ Potential for routing conflicts

---

## How AWS ALB Actually Works

### The Components

```
┌─────────────────────────────────────────────────────────────────┐
│  ALB (Application Load Balancer)                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │  Listener   │    │  Listener   │    │  Listener   │         │
│  │  Port 80    │    │  Port 443   │    │  Port 8080  │         │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘         │
│         │                  │                  │                 │
│         ▼                  ▼                  ▼                 │
│  ┌─────────────────────────────────────────────────────┐       │
│  │                    Listener Rules                    │       │
│  │  IF host = app-a.demo.com → Target Group A          │       │
│  │  IF path = /api/*         → Target Group B          │       │
│  │  IF header X-Version = v2 → Target Group C          │       │
│  │  DEFAULT                  → Target Group Default    │       │
│  └─────────────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
       ┌────────────┐  ┌────────────┐  ┌────────────┐
       │Target Grp A│  │Target Grp B│  │Target Grp C│
       │ 10.0.1.5   │  │ 10.0.2.10  │  │ 10.0.3.15  │
       │ 10.0.1.6   │  │ 10.0.2.11  │  │ 10.0.3.16  │
       └────────────┘  └────────────┘  └────────────┘
              │               │               │
              ▼               ▼               ▼
         Pod IPs         Pod IPs         Pod IPs
```

**Key concepts:**

| Component | What It Does |
|-----------|--------------|
| **Listener** | Listens on a port (80, 443, etc.) for incoming connections |
| **Listener Rules** | Conditions that determine where to route traffic |
| **Target Group** | A set of targets (IPs/instances) that receive traffic |
| **Health Check** | ALB checks if targets are healthy before sending traffic |

### How EKS Connects to ALB

When you create a `LoadBalancer` service in EKS:

```
┌─────────────────────────────────────────────────────────────────┐
│  1. You apply Service YAML                                      │
│     kubectl apply -f service.yaml                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. AWS Cloud Controller Manager sees the Service              │
│     (runs as a pod in kube-system)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Controller calls AWS APIs to create:                        │
│     - ALB                                                       │
│     - Target Group                                              │
│     - Listener                                                  │
│     - Security Group rules                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Controller registers pod IPs as targets                     │
│     (watches for pod changes, updates target group)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Service gets external hostname                              │
│     status.loadBalancer.ingress[0].hostname                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Blue-Green & Canary with ALB

### How Harness Uses ALB for Traffic Shifting

For deployment strategies, Harness manipulates ALB target groups:

```
Blue-Green Deployment:
                              
  Before Swap                    After Swap
  ───────────                    ──────────
       ALB                            ALB
        │                              │
   ┌────┴────┐                    ┌────┴────┐
   ▼         ▼                    ▼         ▼
┌─────┐  ┌─────┐               ┌─────┐  ┌─────┐
│Blue │  │Green│               │Blue │  │Green│
│ v1  │  │ v2  │               │ v1  │  │ v2  │
│100% │  │ 0%  │               │ 0%  │  │100% │
└─────┘  └─────┘               └─────┘  └─────┘
   ▲                                       ▲
   │                                       │
 LIVE                                    LIVE


Canary Deployment:

  Phase 1 (10%)      Phase 2 (50%)      Phase 3 (100%)
  ─────────────      ─────────────      ──────────────
       ALB                ALB                 ALB
        │                  │                   │
   ┌────┴────┐        ┌────┴────┐         ┌────┴────┐
   ▼         ▼        ▼         ▼         ▼         ▼
┌─────┐  ┌─────┐   ┌─────┐  ┌─────┐    ┌─────┐  ┌─────┐
│Prod │  │Canary│  │Prod │  │Canary│   │Prod │  │Canary│
│ v1  │  │ v2   │  │ v1  │  │ v2   │   │ v1  │  │ v2   │
│ 90% │  │ 10%  │  │ 50% │  │ 50%  │   │ 0%  │  │100%  │
└─────┘  └─────┘   └─────┘  └─────┘    └─────┘  └─────┘
```

**What Harness does:**
1. Creates a second Target Group for the new version
2. Updates ALB listener rules to split traffic by percentage
3. Gradually shifts traffic (canary) or swaps instantly (blue-green)
4. Cleans up old target group after success

---

## Cost Comparison

| Setup | Monthly Cost (approx) | Best For |
|-------|----------------------|----------|
| 1 Dedicated ALB | $16-25 + data | Single app, POV |
| 5 Dedicated ALBs | $80-125 + data | Few isolated apps |
| 1 Shared ALB + Ingress | $16-25 + data | Many apps, production |

**ALB Pricing (us-east-1):**
- $0.0225/hour (~$16/month) base
- $0.008 per LCU-hour (based on connections, bandwidth, rules)

---

## Our POV Setup

We use **dedicated ALBs** because:

1. **Simplicity** - No Ingress Controller to install/manage
2. **Isolation** - Each POV app is independent
3. **Demo clarity** - Easy to show "this is your app's load balancer"
4. **Blue-Green/Canary** - Harness manages target groups directly

The tradeoff is cost, but for POVs with 1-3 apps, it's acceptable.

---

## When to Use Each

| Use Dedicated ALB When... | Use Shared ALB When... |
|---------------------------|------------------------|
| Running a POV/demo | Running production workloads |
| Need isolation between apps | Cost is a concern |
| Simple setup is priority | Have many (10+) services |
| Showing blue-green/canary | Already have Ingress Controller |
| Each app needs own SSL cert | Centralized SSL management |

---

## Related Concepts

| Term | What It Means |
|------|---------------|
| **NLB** | Network Load Balancer - Layer 4, for TCP/UDP, faster but less features |
| **CLB** | Classic Load Balancer - Legacy, avoid for new deployments |
| **Target Group** | Collection of targets (IPs/instances) that receive traffic |
| **Listener** | Process that checks for connection requests on a port |
| **Ingress** | Kubernetes resource that defines external access to services |
| **Ingress Controller** | Component that implements Ingress rules (nginx, ALB, Traefik) |
