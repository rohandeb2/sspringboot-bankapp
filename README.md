# 🏦 Banking Platform – Production-Grade DevOps Architecture

<div align="center">

![Platform Status](https://img.shields.io/badge/Platform-Production-brightgreen?style=for-the-badge)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.31-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-1.9.0-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20RDS%20%7C%20ALB-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-DevSecOps-D24939?style=for-the-badge&logo=jenkins&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-Service%20Mesh-466BB0?style=for-the-badge&logo=istio&logoColor=white)
![Compliance](https://img.shields.io/badge/Compliance-PCI--DSS-red?style=for-the-badge)

**A fully automated, zero-downtime, cloud-native banking platform built on AWS EKS — featuring end-to-end DevSecOps, GitOps governance, full-stack observability, and banking-grade security.**

[Architecture Overview](#-architecture-overview) • [Infrastructure](#-infrastructure-aws--terraform) • [CI/CD Pipeline](#-cicd-pipeline-jenkins--github-actions) • [Kubernetes Platform](#-kubernetes-platform) • [Observability](#-observability-stack) • [Security](#-security--compliance) • [Getting Started](#-getting-started)

</div>

---

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Architecture Overview](#-architecture-overview)
- [Tech Stack](#-tech-stack)
- [Infrastructure: AWS + Terraform](#-infrastructure-aws--terraform)
  - [VPC & Networking](#vpc--networking)
  - [EKS Cluster](#eks-cluster)
  - [RDS MySQL Database](#rds-mysql-database)
  - [Application Load Balancer](#application-load-balancer)
  - [IAM & Security](#iam--security)
  - [Remote State Management](#remote-state-management)
- [CI/CD Pipeline: Jenkins + GitHub Actions](#-cicd-pipeline-jenkins--github-actions)
  - [Jenkins DevSecOps Pipeline](#jenkins-devsecops-pipeline)
  - [GitHub Actions – Terraform Automation](#github-actions--terraform-automation)
- [Kubernetes Platform](#-kubernetes-platform)
  - [Helm Chart Architecture](#helm-chart-architecture)
  - [ArgoCD GitOps Governance](#argocd-gitops-governance)
  - [Progressive Delivery – Argo Rollouts](#progressive-delivery--argo-rollouts)
  - [Service Mesh – Istio](#service-mesh--istio)
  - [Autoscaling – Karpenter](#autoscaling--karpenter)
  - [Policy Enforcement – Kyverno](#policy-enforcement--kyverno)
  - [Disaster Recovery – Velero + MinIO](#disaster-recovery--velero--minio)
- [Observability Stack](#-observability-stack)
  - [Metrics – Prometheus](#metrics--prometheus)
  - [Logging – Loki](#logging--loki)
  - [Tracing – Tempo + OpenTelemetry](#tracing--tempo--opentelemetry)
  - [Visualization – Grafana](#visualization--grafana)
  - [Alerting – Alertmanager](#alerting--alertmanager)
- [Security & Compliance](#-security--compliance)
- [Application](#-application-spring-boot)
- [Getting Started](#-getting-started)
- [Repository Structure](#-repository-structure)

---

## 🎯 Project Overview

This project implements a **production-grade, cloud-native banking application platform** on AWS, designed to meet the operational and security standards of the financial services industry. It demonstrates end-to-end DevOps engineering — from infrastructure provisioning to application deployment, monitoring, and disaster recovery.

### Core Design Principles

| Principle | Implementation |
|---|---|
| **Zero Downtime** | Argo Rollouts Blue/Green deployments with automated rollback |
| **Zero Trust Security** | Istio mTLS, Kyverno policies, IRSA, no static credentials |
| **GitOps** | ArgoCD as the single source of truth for all cluster state |
| **Shift-Left Security** | SAST → SCA → Container Scanning → DAST in every pipeline run |
| **Observability** | Metrics + Logs + Traces correlated in Grafana (Golden Signals) |
| **Compliance** | PCI-DSS tagging, KMS encryption, audit logging, 30-day DR retention |
| **Cost Optimization** | Karpenter Spot consolidation, S3 Glacier lifecycle, S3 backend for Loki/Tempo |

---

## 🏗 Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          INTERNET                                         │
└──────────────────────────┬───────────────────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  Route 53   │  DNS + ACM SSL Validation
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  AWS ALB    │  HTTPS (TLS 1.3) | HTTP→HTTPS Redirect
                    └──────┬──────┘
                           │
┌──────────────────────────▼───────────────────────────────────────────────┐
│                          AWS VPC (10.0.0.0/16)                            │
│                                                                           │
│  ┌─────────────────────────────┐  ┌──────────────────────────────────┐   │
│  │  Public Subnets (2 AZs)     │  │  Private App Subnets (2 AZs)     │   │
│  │  - ALB                      │  │  - EKS Worker Nodes              │   │
│  │  - NAT Gateway              │  │  - Karpenter-managed Nodes       │   │
│  └─────────────────────────────┘  └──────────────────────────────────┘   │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │  EKS Cluster (v1.31)                                              │    │
│  │                                                                    │    │
│  │  ┌─────────────┐  ┌───────────────┐  ┌────────────────────────┐  │    │
│  │  │  banking-prod│  │  monitoring   │  │  istio-system          │  │    │
│  │  │  namespace  │  │  namespace    │  │  namespace             │  │    │
│  │  │             │  │               │  │                        │  │    │
│  │  │  Rollout    │  │  Prometheus   │  │  istiod                │  │    │
│  │  │  (BG)       │  │  Grafana      │  │  istio-gateway (NLB)   │  │    │
│  │  │  HPA        │  │  Loki+Promtail│  │  PeerAuthentication    │  │    │
│  │  │  NetworkPol │  │  Tempo        │  │  (STRICT mTLS)         │  │    │
│  │  │  PDB        │  │  OTel         │  │                        │  │    │
│  │  │  ExternalSec│  │  Alertmanager │  └────────────────────────┘  │    │
│  │  └─────────────┘  └───────────────┘                              │    │
│  │                                                                    │    │
│  │  ┌─────────────┐  ┌───────────────┐  ┌────────────────────────┐  │    │
│  │  │  argocd     │  │  karpenter    │  │  velero                │  │    │
│  │  │  namespace  │  │  namespace    │  │  namespace             │  │    │
│  │  │  (GitOps)   │  │  (Autoscaling)│  │  (DR + MinIO)          │  │    │
│  │  └─────────────┘  └───────────────┘  └────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │  Private Data Subnets (2 AZs)                                     │    │
│  │  - RDS MySQL 8.0 (Multi-AZ, KMS Encrypted, Private Only)         │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
               ┌────────────────────┼───────────────────────┐
               ▼                    ▼                        ▼
          AWS S3                AWS KMS               AWS Secrets Manager
    (Loki/Tempo/TF State)   (Encryption Key)        (DB Credentials)
```

---

## 🛠 Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Cloud** | AWS | EKS, RDS, ALB, S3, Route53, ACM, KMS |
| **IaC** | Terraform 1.9.0 | Modular infrastructure provisioning |
| **Container Orchestration** | Kubernetes 1.31 (EKS) | Production workload management |
| **GitOps** | ArgoCD + ApplicationSet | Declarative cluster state management |
| **Progressive Delivery** | Argo Rollouts | Blue/Green deployments + auto-rollback |
| **Service Mesh** | Istio 1.22 | mTLS, traffic control, observability |
| **Autoscaling** | Karpenter | Dynamic node provisioning (Spot + On-Demand) |
| **Policy Enforcement** | Kyverno | Policy-as-Code, security guardrails |
| **CI/CD** | Jenkins (Shared Library) + GitHub Actions | DevSecOps pipeline |
| **Security Scanning** | SonarQube + OWASP DC + Trivy + OWASP ZAP | SAST + SCA + Container + DAST |
| **Metrics** | Prometheus + kube-prometheus-stack | Infrastructure and application metrics |
| **Logging** | Loki + Promtail + S3 | Centralized log aggregation |
| **Tracing** | Tempo + OpenTelemetry | Distributed tracing |
| **Visualization** | Grafana | Unified observability dashboard |
| **Alerting** | Alertmanager + Slack | Real-time alert routing |
| **Disaster Recovery** | Velero + MinIO | Kubernetes backup and restore |
| **Package Management** | Helm | Kubernetes application templating |
| **Application** | Spring Boot 3.3 (Java 17) | Banking microservice |
| **Database** | MySQL 8.0.33 (RDS) | Persistent data store |
| **Container Runtime** | Docker (multi-stage) + ECR | Image build and registry |
| **Secrets Management** | External Secrets Operator + AWS Secrets Manager | Dynamic secret injection |

---

## ☁️ Infrastructure: AWS + Terraform

The infrastructure is built with a **modular Terraform architecture** — each concern (networking, compute, database, security) is an isolated, reusable module. Remote state is stored in S3 with DynamoDB locking.

### VPC & Networking

A production-grade, **Multi-AZ VPC** designed for Kubernetes workloads:

```
VPC CIDR: 10.0.0.0/16

Public Subnets    (2 AZs): 10.0.1.0/24 | 10.0.2.0/24   → ALB, NAT Gateway
Private App Subnets (2 AZs): 10.0.10.0/24 | 10.0.11.0/24 → EKS Nodes
Private Data Subnets (2 AZs): 10.0.20.0/24 | 10.0.21.0/24 → RDS MySQL
```

**Key highlights:**
- Internet Gateway for public subnet egress
- Single NAT Gateway with Elastic IP for private subnet outbound access
- Public subnets tagged `kubernetes.io/role/elb=1` for ALB integration
- Private app subnets tagged `karpenter.sh/discovery=bankapp` for node auto-discovery
- EKS cluster subnet tagging for internal load balancers

### EKS Cluster

```hcl
# Kubernetes v1.31 | Managed Control Plane | OIDC-enabled
module "eks" {
  kubernetes_version     = "1.31"
  private_app_subnet_ids = [private_app_az1, private_app_az2]
  endpoint_private_access = true
  endpoint_public_access  = true
}

# Managed Node Group
scaling_config {
  min_size     = 2
  desired_size = 2
  max_size     = 4
}
instance_types = ["t3.medium"]
capacity_type  = "ON_DEMAND"
update_config  { max_unavailable = 1 }  # Rolling updates
```

**OIDC Provider** is automatically provisioned to enable **IRSA (IAM Roles for Service Accounts)** — no EC2 instance profiles or hardcoded credentials for pods.

### RDS MySQL Database

```
Engine:       MySQL 8.0.33
Instance:     db.t3.medium (configurable)
Storage:      20GB gp3
Multi-AZ:     true (production)
Encryption:   KMS (customer-managed key)
Backups:      7-day retention | Automated snapshots
Logs:         error, general, slowquery → CloudWatch
Access:       Private subnets ONLY | Security group restricted to EKS nodes
```

Deletion protection and final snapshot are enforced in the production environment.

### Application Load Balancer

```
Scheme:        Internet-facing
Subnets:       Public (2 AZs)
Deletion:      Protection enabled

Listeners:
  Port 80  → HTTP_301 redirect to HTTPS
  Port 443 → Forward to Target Group (TLS 1.3 policy)

Target Group:
  Port:        8080 (Spring Boot)
  Target Type: IP (EKS-compatible)
  Health Check: /actuator/health
```

### IAM & Security

**KMS:** A single customer-managed KMS key with auto-rotation covers RDS, S3, CloudWatch Logs, and EBS volumes.

**Security Groups:**
- `eks-nodes-sg` — Allows all egress; tagged for Karpenter discovery
- `rds-sg` — Allows only port 3306 **from the EKS nodes SG** (source-based locking)
- `alb-sg` — Allows ports 80 and 443 from `0.0.0.0/0`

**IRSA Roles provisioned:**

| Service Account | AWS Access | Namespace |
|---|---|---|
| `banking-app-sa` | S3 read/write, Secrets Manager read | `banking-prod` |
| `loki-sa` | S3 read/write/delete (loki bucket) | `monitoring` |
| `tempo-sa` | S3 read/write (tempo bucket) | `monitoring` |
| `karpenter-sa` | EC2 launch/terminate, pricing API | `karpenter` |

### Remote State Management

**Bootstrap** (run once, manually):
```
S3 Bucket:      bankapp-terraform-state-{account_id}
  - Versioning: Enabled
  - Encryption: AES256
  - Object Lock: 30-day GOVERNANCE mode
  - Public Access: Fully blocked

DynamoDB Table: bankapp-terraform-locks
  - Billing:   PAY_PER_REQUEST
  - PITR:      Enabled
  - Deletion:  Protection enabled
```

**Production backend** (`prod/backend.tf`) references the bootstrap resources. The `init.sh` script automates backend configuration and workspace creation.

---

## 🚀 CI/CD Pipeline: Jenkins + GitHub Actions

### Jenkins DevSecOps Pipeline

The pipeline is implemented as a **Jenkins Shared Library** — one reusable function (`devSecOpsPipeline`) called by a three-line `Jenkinsfile`. This enables consistent security gates across all application teams.

```
Developer Push
     │
     ▼
┌─────────────────────────────────────────────────────────┐
│                  Jenkins Shared Library Pipeline         │
│                                                         │
│  1. Maven Build         mvn clean package -DskipTests   │
│         │                                               │
│  2. SAST (SonarQube)   Code quality + security scan     │
│         │               Quality Gate enforced (blocks!) │
│  3. SCA (OWASP DC)     Vulnerable library detection     │
│         │               (Log4j, CVE scanning)           │
│  4. Docker Build        Multi-stage OTel Dockerfile     │
│         │                                               │
│  5. Container Scan      Trivy: CRITICAL = build fail 🚫  │
│         │                                               │
│  6. Push to ECR         Private registry (AWS)          │
│         │                                               │
│  7. DAST (OWASP ZAP)   Runtime scan (K8s preview env)   │
│         │                                               │
│  8. GitOps Trigger      Update values.yaml image tag    │
│                          ArgoCD auto-syncs → Deploy 🚀   │
└─────────────────────────────────────────────────────────┘
```

**Security gates summary:**

| Stage | Tool | Failure Action |
|---|---|---|
| SAST | SonarQube Quality Gate | Pipeline aborts |
| SCA | OWASP Dependency Check | Report published |
| Container | Trivy (CRITICAL severity) | Build blocked |
| Runtime | OWASP ZAP baseline | Report published |

### GitHub Actions – Terraform Automation

**Trigger:** Push to `main` or PR on `terraform/**` paths.

```yaml
# Authentication: OIDC (no static AWS credentials stored in GitHub)
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}

# Workflow: Format Check → Plan → PR Comment → Apply
```

**PR workflow:** The plan output is automatically posted as a PR comment for peer review before any infrastructure change is merged and applied.

**Terraform automation scripts:**

| Script | Purpose |
|---|---|
| `init.sh` | Validates S3 backend, configures remote state, creates workspace |
| `deploy.sh` | Plan → save to file → manual approval gate → apply |
| `destroy.sh` | Double confirmation (type env name) → destroy |

---

## ☸️ Kubernetes Platform

### Helm Chart Architecture

The `banking-platform` Helm chart provides a fully templated, environment-aware deployment. A single chart deploys to dev, staging, and production via `values.yaml` overrides.

**Resources provisioned by the chart:**

```
banking-platform/
├── Namespace          (Pod Security Standards: restricted + Istio injection)
├── ServiceAccount     (IRSA annotation for AWS access)
├── ConfigMap          (Spring profile, DB host, feature flags)
├── ExternalSecret     (Fetches DB credentials from AWS Secrets Manager)
├── Rollout            (Argo Rollouts Blue/Green strategy)
├── Service (active)   (Production traffic → stable pods)
├── Service (preview)  (Test traffic → new version pods)
├── HPA                (CPU + Memory dual-metric autoscaling)
├── PodDisruptionBudget (minAvailable: 2 during node maintenance)
├── NetworkPolicy      (Default deny + allowlist: ALB → app → DNS/RDS)
├── DestinationRule    (Istio mTLS + circuit breaker + LEAST_CONN LB)
├── VirtualService     (Retry logic + timeout + CORS)
├── Gateway            (Istio entry point for api.rohandevops.co.in)
├── Ingress            (AWS ALB Controller, ACM cert, HTTPS enforce)
└── ServiceMonitor     (Prometheus auto-scrape configuration)
```

**Production values (`values-prod.yaml`):**

```yaml
replicaCount: 3
resources:
  requests: { cpu: 500m, memory: 1Gi }
  limits:   { cpu: 1000m, memory: 2Gi }
hpa:
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### ArgoCD GitOps Governance

The platform uses the **App-of-Apps pattern** — one root application (`root-banking-stack`) manages the entire cluster state by pointing to the `argocd-infra/` directory recursively.

**AppProject security boundaries (`banking-core-project`):**

```yaml
# Source restriction — only trusted GitHub repo
sourceRepos: ['https://github.com/rohan/Springboot-BankApp.git']

# Destination restriction — only banking-prod namespace
destinations:
  - namespace: banking-prod
    server: https://kubernetes.default.svc

# Cluster-level: ONLY namespace creation allowed
clusterResourceWhitelist:
  - group: ''
    kind: Namespace

# Namespace-level: only standard app resources
namespaceResourceWhitelist:
  - Deployment, StatefulSet, Rollout, Service, ConfigMap,
    Secret, Ingress, NetworkPolicy, HPA

# RBAC
roles:
  - read-only  (QA/Support team)
  - srv-admin  (DevOps/SRE team)
```

**ApplicationSet** enables multi-environment deployment using list generators and Helm value file overrides — one template, multiple environments.

**Drift detection** is enabled (`orphanedResources.warn: true`) — any manual `kubectl` change triggers a warning.

### Progressive Delivery – Argo Rollouts

**Blue/Green strategy** with automated Prometheus-based promotion gates:

```
New Image Pushed to ECR
        │
        ▼
  Preview Service (Green)
  ┌──────────────────────────────────┐
  │  pre-promotion analysis          │
  │  ┌──────────────────────────────┐│
  │  │ Prometheus: success-rate     ││
  │  │ Interval: 1m × 5 checks      ││
  │  │ Threshold: ≥ 99% success     ││
  │  │ failureLimit: 2              ││
  │  └──────────────────────────────┘│
  │  Manual approval required ✋     │
  └──────────────────────────────────┘
        │ PASS                  │ FAIL
        ▼                       ▼
  Active Service (Blue)   Auto Rollback 🚨
  Traffic switches        Old version restored
  Old pods retained 120s  (scaleDownDelaySeconds)
```

The `AnalysisTemplate` (`banking-success-rate-check`) queries Prometheus:
```promql
sum(rate(http_requests_total{status!~"5.*", app="banking-api"}[2m]))
/
sum(rate(http_requests_total{app="banking-api"}[2m]))
```
Success condition: `result[0] >= 0.995` (99.5% for core analysis, 99% for Blue/Green gate).

### Service Mesh – Istio

Istio 1.22 is deployed via ArgoCD (Helm) in three components: `istio-base` (CRDs), `istiod` (control plane), `istio-ingressgateway` (AWS NLB entry point).

**Zero Trust enforcement:**
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
spec:
  mtls:
    mode: STRICT  # All pod-to-pod traffic must be mTLS. No exceptions.
```

**Traffic resilience (DestinationRule):**
```yaml
trafficPolicy:
  loadBalancer: { simple: LEAST_CONN }
  outlierDetection:
    consecutive5xxErrors: 3    # Eject bad pod after 3 failures
    interval: 10s
    baseEjectionTime: 30s      # Quarantine for 30s
  connectionPool:
    http: { http1MaxPendingRequests: 10 }
```

**istiod** is configured with 100% trace sampling and access logging for full audit trails — a requirement for banking compliance.

### Autoscaling – Karpenter

Karpenter replaces the default cluster autoscaler with **just-in-time node provisioning**:

```yaml
# NodePool — diverse instance families to avoid AZ stockouts
requirements:
  - key: karpenter.sh/capacity-type
    values: ["spot", "on-demand"]
  - key: instance-category
    values: ["t", "m", "c"]
  - key: kubernetes.io/arch
    values: ["amd64"]

# Smart cost optimization
disruption:
  consolidationPolicy: WhenUnderutilized  # Bin-pack and remove idle nodes
  expireAfter: 720h                        # Rotate nodes every 30 days
```

Nodes are auto-discovered by subnet and security group tags (`karpenter.sh/discovery: bankapp`). The controller uses IRSA — no node credentials required.

### Policy Enforcement – Kyverno

A `ClusterPolicy` (`banking-guardrails`) enforces two non-negotiable rules in `Enforce` mode:

```yaml
# Rule 1: Resource limits mandatory (prevents Karpenter over-provisioning)
validate:
  pattern:
    spec:
      containers:
      - resources:
          limits:
            cpu: "?*"
            memory: "?*"

# Rule 2: No root containers (security baseline)
validate:
  pattern:
    spec:
      securityContext:
        runAsNonRoot: true
```

Any deployment violating these rules is **blocked at admission** — not warned.

### Disaster Recovery – Velero + MinIO

**Backup schedule:** Every 6 hours (RPO = 6h), 30-day retention.

```yaml
spec:
  schedule: "0 */6 * * *"
  template:
    includedNamespaces: ["banking-prod"]
    snapshotVolumes: true   # EBS snapshots
    ttl: 720h0m0s           # 30-day retention
    hooks:
      resources:
        - pre:               # Database-consistent backup
            exec:
              command: ["mysqladmin", "flush-tables", "--lock-all-tables"]
        - post:
            exec:
              command: ["mysqladmin", "flush-tables", "--unlock-all-tables"]
```

Backup storage (`BackupStorageLocation`) uses **SSE-KMS encryption** and `STANDARD_IA` storage class for cost efficiency. Both MinIO (local) and AWS S3 are supported via the Velero AWS plugin.

---

## 📊 Observability Stack

The platform implements the **Golden Signals principle** (Latency, Traffic, Errors, Saturation) across all layers.

```
Application → OpenTelemetry Java Agent (automatic instrumentation)
                         │
                         ▼
              OTel Collector (central pipeline)
                    │              │
          Traces → Tempo      Logs → Loki
                         │
              Prometheus scrapes /actuator/prometheus
                         │
              Grafana ← Unified visualization
                         │
              Alertmanager → Slack (#alerts-critical / #alerts-warning)
```

### Metrics – Prometheus

Deployed via `kube-prometheus-stack` (Helm, pinned to `67.3.0`):

- **Retention:** 15 days
- **Storage:** 20Gi gp3 EBS (persistent)
- **ServiceMonitor:** Auto-scrapes the banking app at `/actuator/prometheus` every 30s
- **Relabeling:** `application=banking-core` label applied for consistent dashboard queries

### Logging – Loki

- **Collection:** Promtail DaemonSet (auto-discovers all pod logs)
- **Storage:** AWS S3 (`bankapp-prod-loki-logs-prod`) via IRSA — no credentials in config
- **Schema:** `boltdb-shipper` with S3 object store
- **Integration:** Grafana datasource auto-provisioned via ConfigMap label (`grafana_datasource: "1"`)

### Tracing – Tempo + OpenTelemetry

- **Collector:** Receives traces (OTLP gRPC/HTTP) and logs, fans out to Tempo and Loki
- **Storage:** AWS S3 (`banking-prod-loki-logs-prod`) via IRSA
- **Retention:** 14-day trace compaction
- **Java Agent:** OpenTelemetry Java agent baked into the Docker image (Stage 1 of multi-stage build)

**Grafana trace correlation** is fully configured:
- Trace → Logs: Click a trace span, see matching Loki logs
- Trace → Metrics: Click a service in a trace, see Prometheus dashboards
- Service Dependency Graph: Live visualization of microservice communication (via Kiali)

### Visualization – Grafana

- **Spring Boot Dashboard:** Custom ConfigMap-based dashboard, auto-loaded via sidecar (`grafana_dashboard: "1"` label)
- **Access:** AWS ALB Ingress at `grafana.rohandevops.co.in` (HTTPS enforced, session stickiness enabled)
- **Data Sources:** Prometheus, Loki, Tempo — all auto-provisioned, no manual setup

### Alerting – Alertmanager

Custom `PrometheusRule` covers 12 alert categories:

| Category | Key Alerts |
|---|---|
| **Availability** | `ServiceDown` (1m) |
| **Errors** | `HighErrorRate` >5% over 2m |
| **Latency** | `HighLatency` P95 >1.5s over 5m |
| **Resources** | `HighCPUUsage`, `HighMemoryUsage` |
| **Kubernetes** | `NodeNotReady`, `PodCrashLooping`, `OOMKilled` |
| **Database** | `DBConnectionPoolHigh`, `DatabaseHighLatency` |
| **Infrastructure** | `LowDiskSpace` <10% |
| **Traffic** | `TrafficDrop` 50% below 1hr baseline, `TrafficSpike` 2× |
| **Security** | `AuthFailures` >20/5m |
| **TLS** | `SSLCertExpiringSoon` <15 days |
| **Backup** | `BackupFailed` (Velero) |
| **Queue** | `QueueBacklog` >1000 (Kafka consumer lag) |

Alerts route to `#alerts-critical` or `#alerts-warning` Slack channels based on severity.

---

## 🔐 Security & Compliance

### Defence-in-Depth Security Model

```
Layer 1 — Network:    VPC isolation, Security Groups, NACLs, Private subnets
Layer 2 — Ingress:    ALB + TLS 1.3, HTTPS-only, ACM wildcard cert
Layer 3 — Mesh:       Istio STRICT mTLS (all east-west traffic encrypted)
Layer 4 — Identity:   IRSA (OIDC) — zero static credentials anywhere
Layer 5 — Secrets:    External Secrets Operator → AWS Secrets Manager (1h rotation)
Layer 6 — Network K8s: NetworkPolicy default-deny + explicit allowlist
Layer 7 — Container:  Non-root user, readOnlyRootFilesystem, no privilege escalation
Layer 8 — Policy:     Kyverno ClusterPolicy — resource limits + no-root enforced
Layer 9 — Encryption: KMS key with auto-rotation for RDS, S3, EBS, CloudWatch
Layer 10 — Scanning:  SonarQube + OWASP DC + Trivy + ZAP in every pipeline run
```

### Secrets Management

```
Developer → Git (no secrets) → ArgoCD → ExternalSecrets Operator
                                               │
                                     AWS Secrets Manager
                                    (auto-rotated, IRSA access)
                                               │
                                         Kubernetes Secret
                                    (injected at pod runtime)
```

### Compliance Tagging

All resources are tagged for PCI-DSS auditability:

```hcl
common_tags = {
  Project            = "Banking-System"
  Environment        = "Production"
  ManagedBy          = "Terraform"
  CostCenter         = "Finance-IT"
  SecurityCompliance = "PCI-DSS"
}
```

---

## 🍃 Application: Spring Boot

The `banking-api` is a Spring Boot 3.3 (Java 17) application providing core banking operations:

**Features:** User registration/login • Account dashboard • Deposit & withdrawal • Fund transfer • Transaction history

**Security:** Spring Security with BCrypt password encoding, CSRF (disabled for API), session-based authentication.

**Observability:** Spring Actuator exposes `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness`, and `/actuator/prometheus`. OpenTelemetry Java Agent provides automatic instrumentation — no code changes required.

**Docker image** — 3-stage build:

```dockerfile
# Stage 1: Download OTel agent (Alpine, lean)
# Stage 2: Maven build (openjdk-17)
# Stage 3: Production runtime (eclipse-temurin:17-jre)
#   - Non-root user (appuser:appgroup)
#   - JVM tuning: -Xms256m -Xmx512m
#   - exec ENTRYPOINT for graceful SIGTERM handling
```

**Local development** with Docker Compose:
```
nginx:80 → bankapp:8080 → mysql:3306
```
- MySQL health checks gate application startup (`depends_on: condition: service_healthy`)
- NGINX configured with rate limiting (10r/s), security headers (HSTS, X-Frame-Options), and proxy buffering

---

## 🚦 Getting Started

### Prerequisites

```bash
# Required tools
aws-cli >= 2.0
kubectl >= 1.30
helm >= 3.0
terraform >= 1.9.0
argocd-cli
kubectl-argo-rollouts
```

### 1. Bootstrap Terraform Backend

```bash
cd terraform/scripts
./init.sh
# Validates S3 bucket, configures remote state, selects 'prod' workspace
```

### 2. Provision Infrastructure

```bash
cd terraform/scripts
./deploy.sh
# Generates plan → requires manual approval → applies
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name bankapp-prod-eks
```

### 4. Install Cluster Components

```bash
# AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=bankapp-prod-eks

# External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace

# ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### 5. Deploy via GitOps

```bash
# Apply the root App-of-Apps — ArgoCD takes over from here
kubectl apply -f k8s-manifests/argocd-infra/master-app.yaml

# ArgoCD will recursively sync:
# → Istio → Karpenter → Kyverno → Loki → Tempo → Prometheus → Velero → banking-app
```

### 6. Deploy Application (Helm Direct)

```bash
helm upgrade --install banking-prod ./k8s-manifests/banking-platform \
  --namespace banking-prod \
  --create-namespace \
  --values ./k8s-manifests/banking-platform/values.yaml \
  --values ./k8s-manifests/banking-platform/values-prod.yaml \
  --wait --timeout 5m
```

### 7. Access Services

| Service | URL |
|---|---|
| Banking API | `https://api.rohandevops.co.in` |
| Grafana | `https://grafana.rohandevops.co.in` |
| SonarQube | `https://sonarqube.rohandevops.co.in` |
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` |

---

## 📁 Repository Structure

```
.
├── Dockerfile                          # Multi-stage: OTel agent + Maven build + JRE runtime
├── docker-compose.yml                  # Local dev: nginx + app + mysql
├── Jenkinsfile                         # 3-line entrypoint → Shared Library
├── nginx.conf                          # Rate limiting, security headers, proxy config
├── pom.xml                             # Spring Boot 3.3, MySQL connector, Security
│
├── src/
│   └── main/
│       ├── java/com/example/bankapp/   # Spring Boot application source
│       └── resources/
│           └── templates/              # Thymeleaf HTML templates
│
├── k8s-manifests/
│   ├── banking-platform/               # Helm chart (main application)
│   │   ├── Chart.yaml
│   │   ├── values.yaml                 # Base values
│   │   ├── values-prod.yaml            # Production overrides
│   │   └── templates/
│   │       ├── rollout.yaml            # Argo Rollouts Blue/Green
│   │       ├── network-policy.yaml     # Default-deny NetworkPolicy
│   │       ├── external-secret.yaml    # AWS Secrets Manager integration
│   │       ├── destination-rule.yaml   # Istio circuit breaker + mTLS
│   │       ├── virtual-service.yaml    # Retry + timeout + CORS
│   │       ├── hpa.yaml                # CPU + Memory autoscaling
│   │       ├── pdb.yaml                # PodDisruptionBudget (minAvailable: 2)
│   │       ├── service-monitor.yaml    # Prometheus scrape config
│   │       └── ingress.yaml            # AWS ALB + ACM HTTPS
│   │
│   └── argocd-infra/                   # GitOps infrastructure manifests
│       ├── master-app.yaml             # Root App-of-Apps
│       ├── app-project.yaml            # AppProject (security governance)
│       ├── application-set.yaml        # Dynamic multi-env deployment
│       ├── repo-secret.yaml            # GitHub credentials
│       ├── argocd-rollouts/
│       │   ├── analysis-template.yaml  # Prometheus success-rate check
│       │   └── blue-green-strategy.yaml
│       ├── disaster-recovery/
│       │   ├── velero-app.yaml
│       │   ├── minio-stack.yaml
│       │   ├── velero-schedule.yaml    # 6-hour backup schedule
│       │   ├── velero-storage.yaml     # S3 + KMS backup location
│       │   └── velero-namespace.yaml   # ResourceQuota + NetworkPolicy
│       ├── governance/
│       │   ├── kyverno.yaml
│       │   ├── cluster-policies.yaml   # resource-limits + no-root
│       │   ├── karpenter.yaml
│       │   ├── karpenter-nodeclass.yaml
│       │   └── karpenter-nodepool.yaml
│       ├── monitoring/
│       │   ├── prometheus-stack.yaml   # kube-prometheus-stack + alertmanager
│       │   ├── prometheus-rules.yaml   # 12 alert categories
│       │   ├── loki-stack.yaml         # Loki + Promtail + S3 backend
│       │   ├── tempo-stack.yaml        # Tempo + S3 backend
│       │   ├── otel-collector.yaml     # OTel traces→Tempo, logs→Loki
│       │   ├── grafana-dashboard-configmap.yaml
│       │   ├── grafana-ingress.yaml    # ALB ingress for Grafana
│       │   ├── loki-datasource.yaml    # Auto-provisioned datasource
│       │   ├── tempo-datasource.yaml   # Trace→Log correlation config
│       │   ├── kiali-stack.yaml        # Service mesh observability
│       │   ├── loki-service-account.yaml
│       │   └── tempo-sa.yaml
│       ├── networking/
│       │   ├── istio-base.yaml
│       │   ├── istiod.yaml             # Control plane + 100% tracing
│       │   ├── istio-gateway.yaml      # NLB + autoscaling
│       │   └── peer-auth.yaml          # STRICT mTLS mesh-wide
│       └── devsecops/
│           └── sonarqube-stack.yaml
│
├── terraform/
│   ├── bootstrap/                      # One-time backend setup
│   │   ├── s3-backend/                 # State bucket + Object Lock
│   │   └── dynamodb-lock/              # Lock table + PITR
│   ├── global/                         # Shared resources (ACM, Route53)
│   │   ├── acm/                        # Wildcard cert + DNS validation
│   │   ├── route53/                    # Hosted zone + ALB alias
│   │   └── s3-backend/                 # Global state + KMS
│   ├── modules/                        # Reusable infrastructure modules
│   │   ├── networking/                 # VPC, subnets, IGW, NAT
│   │   ├── eks/                        # EKS cluster + node group + OIDC
│   │   │   └── karpenter_iam.tf        # Karpenter node + controller IAM
│   │   ├── rds/                        # MySQL + subnet group + encryption
│   │   ├── alb/                        # ALB + TG + HTTPS + HTTP redirect
│   │   ├── iam/                        # IRSA roles for app pods
│   │   ├── security/                   # KMS + EKS SG + RDS SG
│   │   ├── s3/                         # Versioned + encrypted + lifecycle
│   │   ├── cloudwatch/                 # Log groups + metric filters + alarms
│   │   └── route53/                    # DNS records + ACM validation
│   ├── prod/                           # Production environment root
│   │   ├── main.tf                     # Module composition + IRSA for Loki/Tempo
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf                  # S3 + DynamoDB remote state
│   │   └── terraform.tfvars            # PCI-DSS tags, CIDR blocks, DB config
│   └── scripts/
│       ├── init.sh                     # Backend validation + workspace setup
│       ├── deploy.sh                   # Plan → approval → apply
│       └── destroy.sh                  # Double-confirm → destroy
│
├── vars/
│   └── devSecOpsPipeline.groovy        # Jenkins Shared Library (SAST+SCA+Trivy+ZAP+GitOps)
│
└── .github/
    └── workflows/
        └── deploy.yaml                 # GitHub Actions: OIDC auth + TF plan/apply
```

---

## 🤝 Contributing

This repository follows a GitOps workflow. All changes must go through a pull request:

1. Fork the repository and create a feature branch
2. For infrastructure changes: the GitHub Actions workflow will post a `terraform plan` as a PR comment
3. For application changes: the Jenkins pipeline runs all security gates before the image is pushed
4. Merge to `main` → ArgoCD auto-syncs to the cluster within seconds

---

<div align="center">

Built with ☕ and a deep respect for production reliability.

**Rohan DevOps** | [rohan@rohandevops.co.in](mailto:rohan@rohandevops.co.in)

</div>