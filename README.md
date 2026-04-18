# Harness Demo Application

A modern, customer-branded demo application designed for Harness CI/CD pipelines. This Spring Boot application supports multiple deployment targets including **EKS, ECS, Lambda, and ASG**, with built-in support for **blue/green and canary deployments**, **Prometheus metrics**, **Continuous Verification**, and **Harness Chaos Engineering**.

![Java](https://img.shields.io/badge/Java-17-orange)
![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.2-green)
![License](https://img.shields.io/badge/License-MIT-blue)

## For Sales Engineers

This repo is designed to be **forked** for customer POVs. Each SE can:
1. Fork this repo to their own GitHub account/org
2. Use the included OpenTofu code to spin up AWS infrastructure
3. Import the pipeline YAML templates into Harness
4. Customize branding via environment variables

See [Getting Started for SEs](#getting-started-for-ses) below.

## Repository Architecture

For the current repo-level architecture, lifecycle boundaries, and control-plane vs workload ownership model, see [docs/repo-architecture.md](docs/repo-architecture.md).

## Features

### 🎨 Visual & Engaging UI
- Modern, responsive design with TailwindCSS
- Real-time deployment variant indicators (Blue/Green/Canary)
- Color-coded banners that change based on deployment type
- Interactive API testing from the browser
- Chaos engineering controls for live demonstrations

### 🔧 Personalization
- Customer name customization via environment variables
- Custom logo support
- Configurable colors per deployment variant

### 📊 Observability
- Prometheus metrics at `/actuator/prometheus`
- Custom metrics for page views, API calls, processing time
- Chaos event tracking
- Ready for Grafana dashboards

### 🚀 Deployment Strategies
- **Blue/Green**: Separate deployments with distinct colors
- **Canary**: Gradual rollout with visual indicators
- Environment-based configuration

## Quick Start

### Local Development

```bash
# Build the application
./mvnw clean package

# Run locally
./mvnw spring-boot:run

# Or with custom settings
APP_VERSION=2.0.0 DEPLOYMENT_VARIANT=canary VARIANT_COLOR=#F59E0B ./mvnw spring-boot:run
```

### Docker

```bash
# Build image
docker build -t harness-pov-app:1.0.0 .

# Run container
docker run -p 8080:8080 \
  -e DEPLOYMENT_VARIANT=blue \
  -e VARIANT_COLOR="#3B82F6" \
  -e CUSTOMER_NAME="Acme Corp" \
  harness-pov-app:1.0.0
```

### Kubernetes

```bash
# Deploy to Kubernetes
kubectl apply -f k8s/deployment.yaml

# Blue/Green deployment
kubectl apply -f k8s/blue-green/

# Canary deployment
kubectl apply -f k8s/canary/
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_VERSION` | Application version displayed | `1.0.0` |
| `APP_ENVIRONMENT` | Environment name | `development` |
| `DEPLOYMENT_VARIANT` | Variant type (blue/green/canary/stable) | `stable` |
| `VARIANT_COLOR` | Hex color for UI theming | `#3B82F6` |
| `CUSTOMER_NAME` | Customer name for personalization | `Harness Customer` |
| `CUSTOMER_LOGO` | URL to customer logo | (empty) |
| `CHAOS_ENABLED` | Enable chaos engineering features | `true` |
| `CHAOS_LATENCY_MS` | Injected latency in milliseconds | `0` |
| `CHAOS_ERROR_RATE` | Error injection rate (0.0-1.0) | `0.0` |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main dashboard |
| `/features` | GET | Features showcase |
| `/deployment` | GET | Deployment information |
| `/chaos` | GET | Chaos engineering controls |
| `/api/info` | GET | Application information JSON |
| `/api/health` | GET | Health check |
| `/api/version` | GET | Version details |
| `/api/process` | POST | Process simulation |
| `/api/simulate-load` | GET | CPU load simulation |
| `/api/simulate-memory` | GET | Memory allocation simulation |
| `/actuator/prometheus` | GET | Prometheus metrics |
| `/actuator/health` | GET | Spring Actuator health |

## Harness Module Integration

### CI (Continuous Integration)
- Maven build with test execution
- JaCoCo code coverage
- Docker image building
- Static analysis with SpotBugs

### CD (Continuous Delivery)
- Kubernetes manifests for deployment
- Blue/Green deployment configurations
- Canary deployment support
- Health checks for rolling updates

### STO (Security Testing Orchestration)
- OWASP Dependency Check plugin
- Container scanning ready (Trivy/Grype compatible)
- Non-root Docker user

### Artifact Registry
- Multi-stage Dockerfile for optimized images
- Semantic versioning support
- Image tagging for variants

### Chaos Engineering
- Built-in latency injection
- Error rate simulation
- CPU and memory stress testing
- Metrics for chaos events

### IDP (Internal Developer Portal)
- Backstage `catalog-info.yaml` included
- API documentation
- Service metadata

### IACM (Infrastructure as Code Management)
- Terraform configurations
- Kubernetes resource definitions
- Variable-driven deployments

## Deployment Variants

### Blue Deployment
```bash
DEPLOYMENT_VARIANT=blue
VARIANT_COLOR=#3B82F6
```

### Green Deployment
```bash
DEPLOYMENT_VARIANT=green
VARIANT_COLOR=#10B981
```

### Canary Deployment
```bash
DEPLOYMENT_VARIANT=canary
VARIANT_COLOR=#F59E0B
```

## Prometheus Metrics

Custom metrics exposed:
- `harness_demo_page_views_total` - Page view counter by page
- `harness_demo_api_calls_total` - API call counter by endpoint
- `harness_demo_processing_duration` - Processing time histogram
- `harness_demo_chaos_events_total` - Chaos injection counter
- `harness_demo_errors_total` - Error counter by type

## Project Structure

```
├── src/
│   ├── main/
│   │   ├── java/io/harness/demo/
│   │   │   ├── config/          # Configuration classes
│   │   │   ├── controller/      # REST and MVC controllers
│   │   │   └── service/         # Business logic
│   │   └── resources/
│   │       ├── templates/       # Thymeleaf templates
│   │       └── application.yml  # Application config
│   └── test/                    # Unit tests
├── k8s/                         # Kubernetes manifests
│   ├── blue-green/             # Blue/Green configs
│   └── canary/                 # Canary configs
├── terraform/                   # Terraform configs
├── Dockerfile                   # Container build
├── catalog-info.yaml           # Backstage catalog
└── pom.xml                     # Maven build
```

## Getting Started for SEs

### 1. Fork This Repository

```bash
# Fork via GitHub UI, then clone your fork
git clone https://github.com/YOUR-ORG/harness-demo-app.git
cd harness-demo-app
```

### 2. Provision AWS Infrastructure

```bash
cd tofu/stacks/eks

# Configure your variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# - owner
# - eks_cluster_name
# - harness_account_id
# - harness_api_key
# - harness_api_key_email

# Deploy infrastructure
tofu init
tofu apply
```

This creates:
- Kubernetes namespace for the sandbox
- Harness service, environment, and infrastructure definitions
- Harness connectors (K8s, AWS, GitHub, AWS for ECR when needed)
- Harness Artifact Registry integration or ECR wiring, depending on `artifact_registry_type`
- Optional per-sandbox delegate and generated delivery pipelines

### 3. Use the Generated Delivery Pipelines

The stack creates the Harness service, environment, infrastructure, and delivery pipeline resources for the sandbox.

If you want to inspect or manually import legacy example YAMLs, they remain in `harness/pipelines/`:

Pipeline YAML templates are in `harness/pipelines/`:

| Pipeline | Description |
|----------|-------------|
| `ci-build.yaml` | Build, test, scan, push to ECR |
| `cd-eks-canary.yaml` | Canary deployment with CV |
| `cd-eks-bluegreen.yaml` | Blue-Green deployment |
| `cd-ecs.yaml` | ECS rolling deployment |

Manual import example:
```bash
harness pipeline create --file harness/pipelines/ci-build.yaml
```

### 4. Customize for Customer

Set environment variables in your deployment:
```yaml
env:
  - name: CUSTOMER_LOGO
    value: "https://customer.com/logo.png"
  - name: DEPLOYMENT_VARIANT
    value: "canary"
```

## CV Canary Rollback Demo

The app includes chaos injection endpoints for demonstrating Continuous Verification:

```bash
# Trigger chaos on canary deployment
curl -X POST "http://canary-service:8080/api/chaos/degrade-canary"
```

This causes metrics to degrade, CV detects the issue, and triggers automatic rollback.

See [docs/CV_CANARY_ROLLBACK.md](docs/CV_CANARY_ROLLBACK.md) for full instructions.

## Repository Structure

```
├── src/                     # Spring Boot application
├── k8s/                     # Kubernetes manifests
├── tofu/                    # OpenTofu infrastructure code
│   ├── modules/             # Reusable modules (VPC, EKS, ECR, Delegate, Connectors)
│   └── environments/        # Environment configs (sandbox, pov-template)
├── harness/                 # Harness pipeline YAML templates
│   └── pipelines/
├── docs/                    # Documentation
├── Dockerfile
├── catalog-info.yaml        # Backstage/IDP catalog
└── pom.xml
```

## License

MIT License - Feel free to use this for your Harness POV demonstrations.
