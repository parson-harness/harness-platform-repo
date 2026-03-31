---
description: Set up Harness Artifact Registry with DockerHub upstream proxy
---

# HAR Registry Setup Workflow

## Overview

Each POV gets its own HAR virtual registry with a DockerHub upstream proxy. This allows:
- Pulling base images (e.g., `eclipse-temurin:17-jre`) through HAR
- Caching images to avoid DockerHub rate limits
- Isolation between POVs

## Architecture

```
┌─────────────────────────────────────────────────┐
│  CI Pipeline (BuildAndPushDockerRegistry)       │
│  Image: pkg.harness.io/.../har-{owner}/{image}  │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Virtual Registry: har-{owner}                  │
│  Type: VIRTUAL                                  │
│  upstream_proxies: [{owner}-dockerhub-proxy]    │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Upstream Proxy: {owner}-dockerhub-proxy        │
│  Type: UPSTREAM                                 │
│  Source: Dockerhub                              │
│  Auth: Anonymous (or authenticated)             │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  DockerHub (index.docker.io)                    │
└─────────────────────────────────────────────────┘
```

## Terraform Module

The `harness-artifact-registry` module creates both:
- Virtual registry (`har-{owner}`)
- Upstream proxy (`{owner}-dockerhub-proxy`)

Key variables:
```hcl
module "har" {
  source = "../../modules/harness-artifact-registry"
  
  registry_id               = "har-${var.owner}"
  create_dockerhub_upstream = true
  dockerhub_upstream_id     = "${var.owner}-dockerhub-proxy"
  
  # Optional: authenticated DockerHub access
  dockerhub_username            = var.dockerhub_username
  dockerhub_password_secret_ref = var.dockerhub_password_secret_ref
}
```

## Common Issues

### Upstream Proxy Missing After Destroyer

**Symptom**: `eclipse-temurin:17-jre: not found` in CI build

**Timeline Pattern**:
1. Destroyer runs → deletes HAR resources (Cleanup Orphans stage)
2. CI pipeline triggers (git push) before provisioner runs
3. CI fails because upstream proxy doesn't exist

**Check**:
```bash
# List registries - look for {owner}-dockerhub-proxy
harness_list(resource_type='registry', org_id='sandbox', project_id='parson')
```

**Resolution**:
1. **Re-run Provisioner** (recommended) - recreates all resources
2. **Manual fix** - see API calls below

### Upstream Proxy Not Linked

**Symptom**: `eclipse-temurin:17-jre: not found` but upstream proxy exists

**Check**:
```bash
# Via Harness MCP
harness_get(resource_type='registry', org_id='sandbox', project_id='parson', resource_id='har-{owner}')
# Look for: config.upstreamProxies should contain "{owner}-dockerhub-proxy"
```

**Cause**: Virtual registry exists but upstream proxy not in upstreamProxies list

**Fix**: Re-run provisioner or manually link via API (see below)

### Upstream Proxy Doesn't Exist

**Check**:
```bash
# List upstream proxies
harness_list(resource_type='registry', org_id='sandbox', project_id='parson', filters={'type': 'UPSTREAM'})
```

**Fix**: Re-run provisioner to create it

### Manual HAR API Calls

The HAR API is unusual - it requires `/+` suffix in the `space_ref` parameter:

```bash
# Create upstream proxy
curl -X POST 'https://app.harness.io/har/api/v1/registry?space_ref={account_id}/{org_id}/{project_id}/%2B' \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "{owner}-dockerhub-proxy",
    "packageType": "DOCKER",
    "parentRef": "{account_id}/{org_id}/{project_id}",
    "config": {
      "type": "UPSTREAM",
      "source": "Dockerhub",
      "authType": "Anonymous"
    }
  }'

# Update virtual registry to link upstream
curl -X PUT 'https://app.harness.io/har/api/v1/registry/{account_id}/{org_id}/{project_id}/har-{owner}/%2B' \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "har-{owner}",
    "packageType": "DOCKER",
    "parentRef": "{account_id}/{org_id}/{project_id}",
    "config": {
      "type": "VIRTUAL",
      "upstreamProxies": ["{owner}-dockerhub-proxy"]
    }
  }'
```

## Dockerfile Configuration

The Dockerfile should use the HAR registry for base images:

```dockerfile
ARG BASE_IMAGE_REGISTRY
FROM ${BASE_IMAGE_REGISTRY}/eclipse-temurin:17-jre
```

The CI pipeline passes `BASE_IMAGE_REGISTRY=pkg.harness.io/{account_id}/har-{owner}`.

## Authenticated DockerHub Access

To avoid rate limits, configure authenticated access:

1. Create a Harness secret with DockerHub password/token
2. Set variables in IACM workspace:
   - `dockerhub_username`: Your DockerHub username
   - `dockerhub_password_secret_ref`: Secret reference (e.g., `account.dockerhub_token`)
