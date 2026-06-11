# Spring Boot Banking Application - Production Deployment Guide

**Project:** Banking Core Platform  
**Environment:** AWS (us-east-1)  
---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Provisioning](#infrastructure-provisioning)
4. [Application Deployment](#application-deployment)
5. [CI/CD Pipeline](#cicd-pipeline)
6. [Monitoring & Observability](#monitoring--observability)
7. [Disaster Recovery](#disaster-recovery)
8. [Security & Compliance](#security--compliance)
9. [Post-Deployment Validation](#post-deployment-validation)
10. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Infrastructure Layers

**1. Networking Layer**
- VPC: `10.0.0.0/16` with 6 subnets (2 public, 2 private-app, 2 private-data)
- Internet Gateway + NAT Gateway for outbound traffic
- Route53 for DNS (domain: `rohandevops.co.in`)
- ALB with HTTPS termination via ACM certificate

**2. Compute Layer**
- EKS cluster (Kubernetes 1.31, API + Config Map auth)
- Karpenter for auto-scaling (consolidation enabled, spot+on-demand)
- 2 general node groups (m7i-flex.large, SPOT capacity)

**3. Data Layer**
- RDS MySQL 8.0 (Multi-AZ production, encrypted with KMS)
- S3 buckets for Terraform state, Loki logs, Tempo traces
- DynamoDB for Terraform state locking

**4. Security Layer**
- KMS for encryption at rest
- IRSA (IAM Roles for Service Accounts) for fine-grained permissions
- Kyverno for policy enforcement
- Security Groups with least-privilege ingress/egress

**5. Observability Stack**
- Prometheus + Grafana for metrics
- Loki for log aggregation (S3-backed storage)
- Tempo for distributed tracing
- Kiali for service mesh visualization
- OpenTelemetry Collector for instrumentation

**6. CI/CD & GitOps**
- Jenkins with 6 security scanning stages
- ArgoCD with ApplicationSet for multi-environment sync
- GitHub Actions (OIDC) for infrastructure automation

---

## Prerequisites

### Local Tools Required

```bash
# Install dependencies (script provided)
bash install_tools.sh

# Verify installations
terraform version          # ~> 1.9.0
kubectl version           # Client ~> 1.31
helm version              # ~> 3.x
aws --version             # ~> 2.x
docker --version          # ~> 24.x
argocd version
eksctl version
velero version
istioctl version
```

### AWS Account Setup

```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID="<your-key>"
export AWS_SECRET_ACCESS_KEY="<your-secret>"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="959589242185"

# Verify access
aws sts get-caller-identity
```

### GitHub Setup

```bash
# Generate GitHub token with repo + workflow scopes
export GIT_TOKEN="<github-personal-access-token>"

# Test authentication
curl -H "Authorization: token $GIT_TOKEN" \
  https://api.github.com/user
```

---

## Infrastructure Provisioning

### Phase 1: Terraform State Backend (Automated)

The state backend is bootstrapped before any resources are created.

```bash
# 1. Navigate to bootstrap directory
cd terraform/bootstrap

# 2. S3 Backend Provisioning
cd s3-backend
terraform init
terraform apply -var-file=terraform.tfvars -auto-approve

# Output: S3 bucket name, ARN

# 3. DynamoDB Lock Table Provisioning
cd ../dynamodb-lock
terraform init
terraform apply -var-file=terraform.tfvars -auto-approve

# Output: DynamoDB table name for state locking
```

**Resources Created:**
- S3 bucket with versioning, encryption (KMS), object lock (GOVERNANCE, 30-day retention)
- DynamoDB table for state locking with point-in-time recovery enabled
- Bucket policies restricting public access

### Phase 2: Production Infrastructure Deployment

```bash
# 1. Initialize Terraform with remote state
cd terraform/prod
terraform init \
  -backend-config="bucket=bankapp-terraform-state-874516984521" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=bankapp-terraform-locks-8446176321459" \
  -backend-config="encrypt=true"

# 2. Validate configuration
terraform validate
terraform fmt -recursive

# 3. Run TFLint for compliance
tflint --init
tflint --recursive --f compact

# 4. Security scanning (Checkov)
checkov -d . --framework terraform --quiet

# 5. Plan infrastructure changes
terraform plan \
  -var-file=terraform.tfvars \
  -out=tfplan

# 6. Apply infrastructure (idempotent)
terraform apply tfplan
```

**Provisioned Resources:**

| Layer | Resource | Config |
|-------|----------|--------|
| Networking | VPC | 10.0.0.0/16, 6 subnets |
| Networking | IGW + NAT | Internet access, outbound NAT |
| Networking | Route53 | rohandevops.co.in + subdomains |
| Security | KMS Key | Alias: `bankapp-key`, 30-day rotation |
| Security | Security Groups | EKS nodes, RDS, ALB (least-privilege) |
| Compute | EKS Cluster | 1.31, public + private endpoints |
| Compute | Node Group | m7i-flex.large, 1-4 nodes (SPOT) |
| Compute | Karpenter | Consolidation every 30s, drift enabled |
| Storage | RDS MySQL | db.t4g.micro, Multi-AZ, automated backups |
| Storage | S3 Buckets | app data, Loki logs, Tempo traces (S3 storage classes) |
| Security | IAM Roles | IRSA for EKS, Jenkins, Velero, Loki, Tempo |
| Load Balancing | ALB | HTTPS termination, health checks, sticky sessions |

**Terraform Outputs:**

```bash
# After successful apply, capture these outputs
terraform output vpc_id
terraform output eks_cluster_name
terraform output eks_cluster_endpoint
terraform output alb_dns_name
terraform output rds_endpoint
terraform output app_irsa_role_arn
terraform output loki_irsa_role_arn
terraform output tempo_irsa_role_arn
```

### Phase 3: EKS Cluster Post-Setup

```bash
# 1. Configure kubectl
aws eks update-kubeconfig \
  --name bankapp-prod-eks \
  --region us-east-1

# Verify cluster access
kubectl get nodes
kubectl get all -A

# 2. Verify OIDC provider
aws iam list-open-id-connect-providers | \
  grep "oidc.eks.us-east-1.amazonaws.com"

# 3. Create argocd namespace and secret
kubectl create namespace argocd
kubectl apply -n argocd -f argocd/app-project.yaml

# 4. Create banking-prod namespace
kubectl create namespace banking-prod
kubectl label namespace banking-prod \
  pod-security.kubernetes.io/enforce=privileged

# 5. Create monitoring namespace
kubectl create namespace monitoring

# 6. Verify aws-auth ConfigMap (Karpenter + Node groups)
kubectl get configmap -n kube-system aws-auth -o yaml
```

---

## Application Deployment

### Phase 1: Docker Image Build & Registry

```bash
# 1. Build Docker image locally
docker build -t springboot-bankapp:latest .

# 2. Authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  959589242185.dkr.ecr.us-east-1.amazonaws.com

# 3. Create ECR repository (if not exists)
aws ecr create-repository \
  --repository-name springboot-bankapp \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true

# 4. Tag and push image
docker tag springboot-bankapp:latest \
  959589242185.dkr.ecr.us-east-1.amazonaws.com/springboot-bankapp:latest

docker push 959589242185.dkr.ecr.us-east-1.amazonaws.com/springboot-bankapp:latest

# 5. Enable automated ECR scanning
aws ecr put-image-scanning-configuration \
  --repository-name springboot-bankapp \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1
```

### Phase 2: RDS Database Initialization

```bash
# 1. Store DB credentials in AWS Secrets Manager
aws secretsmanager create-secret \
  --name banking-prod-db-secret \
  --region us-east-1 \
  --secret-string '{"db_username":"bankadmin","db_password":"<secure-password>"}'

# 2. Retrieve RDS endpoint
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "RDS Endpoint: $RDS_ENDPOINT"

# 3. Connect to RDS (requires security group rules)
mysql -h $RDS_ENDPOINT -u bankadmin -p

# 4. Create application tables (execute in DB)
# The Spring application will handle schema creation via Flyway/Liquibase
# Or manually run migration scripts

# 5. Verify connectivity from EKS
kubectl run mysql-test --image=mysql:8.0 -it --rm -- \
  mysql -h $RDS_ENDPOINT -u bankadmin -p$DB_PASSWORD -e "SELECT 1;"
```

### Phase 3: Kubernetes Secrets & ConfigMaps

```bash
# 1. Create database secret
kubectl create secret generic banking-db-secret \
  --from-literal=DB_PASSWORD=<secure-password> \
  -n banking-prod

# 2. Create GitHub credentials for ArgoCD
kubectl create secret generic banking-repo-creds \
  --from-literal=username=<github-username> \
  --from-literal=password=$GIT_TOKEN \
  -n argocd

# 3. Create Jenkins credentials
aws secretsmanager create-secret \
  --name jenkins-secret \
  --secret-string '{"sonar-token":"<token>","gemini_api_key":"<key>"}'

# 4. Verify secrets
kubectl get secrets -n banking-prod
kubectl get secrets -n argocd
```

### Phase 4: Helm Chart Deployment

```bash
# 1. Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update

# 2. Deploy Helm chart (manual or via ArgoCD)
helm install banking-app helm_k8s/ \
  --namespace banking-prod \
  --values helm_k8s/values-prod.yaml

# 3. Verify deployment
kubectl get deployment -n banking-prod
kubectl get pods -n banking-prod
kubectl describe pod -n banking-prod <pod-name>

# 4. Check logs
kubectl logs -n banking-prod deployment/prod-banking-platform-banking-platform
```

### Phase 5: ArgoCD ApplicationSet Deployment

```bash
# 1. Install ArgoCD (via Helm or kubectl)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s

# 3. Retrieve ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# 4. Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 5. Login to ArgoCD
argocd login localhost:8080 \
  --username admin \
  --password $ARGOCD_PASSWORD

# 6. Apply root ApplicationSet for multi-environment management
kubectl apply -f root_argocd_aop/master-app.yaml

# 7. Monitor sync status
argocd app list
argocd app sync root-banking-stack
argocd app wait root-banking-stack --sync
```

---

## CI/CD Pipeline

### Jenkins Setup

```bash
# 1. Install Jenkins on EKS or EC2
# For EKS, deploy via Helm chart or kubectl manifest

# 2. Configure Jenkins Security
# - Enable RBAC authorization
# - Configure OIDC/OAuth for GitHub authentication
# - Enable pipeline script approval

# 3. Create Pipeline Job
# - Pipeline type: Multibranch Pipeline
# - Branch sources: GitHub (rohandeb2/sspringboot-bankapp)
# - Build triggers: GitHub Push
# - Jenkinsfile path: ./Jenkinsfile

# 4. Configure Build Credentials
kubectl create secret generic jenkins-aws-creds \
  --from-literal=aws_access_key_id=<key> \
  --from-literal=aws_secret_access_key=<secret> \
  -n jenkins

# 5. Store secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name jenkins-aws-creds \
  --secret-string '{"aws_access_key_id":"<key>","aws_secret_access_key":"<secret>"}'

aws secretsmanager create-secret \
  --name jenkins-secret \
  --secret-string '{"sonar-token":"<token>","gemini_api_key":"<key>"}'

aws secretsmanager create-secret \
  --name banking-github-creds \
  --secret-string '{"git_username":"<user>","git_password":"<token>"}'
```

### Pipeline Stages (Jenkinsfile)

The pipeline executes in this order:

1. **Configure AWS + Pull Secrets** - Fetch credentials from Secrets Manager
2. **Build & Package** - Maven clean package (skip tests)
3. **SAST - SonarQube** - Static code analysis with quality gate enforcement
4. **SCA - OWASP Dependency Check** - Vulnerability scanning of dependencies
5. **Docker Build + Trivy Scan** - Build image and scan for CRITICAL vulnerabilities
6. **Push to ECR** - Push image and enable native ECR scanning
7. **GitOps - Update Image Tag** - Update Helm values-prod.yaml with new tag (triggers ArgoCD)

### Local Pipeline Testing

```bash
# Run Jenkinsfile locally with Jenkins CLI
java -jar jenkins-cli.jar -s http://localhost:8080 \
  declarative-linter < Jenkinsfile

# Run SonarQube scan locally
mvn sonar:sonar \
  -Dsonar.projectKey=springboot-bankapp \
  -Dsonar.projectName=springboot-bankapp \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.login=<token>

# Run Dependency Check
dependency-check.sh --scan . --format HTML --out ./reports

# Build and scan Docker image
docker build -t springboot-bankapp:test .
trivy image springboot-bankapp:test --severity CRITICAL,HIGH
```

---

## Monitoring & Observability

### Prometheus + Grafana Stack

```bash
# 1. Deploy Prometheus stack via ArgoCD
kubectl apply -f monitoring/1_prometheus-stack.yaml

# 2. Wait for pods
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kube-prometheus-stack \
  -n monitoring --timeout=600s

# 3. Access Prometheus
kubectl port-forward -n monitoring \
  svc/prometheus-kube-prometheus-prometheus 9090:9090

# Open: http://localhost:9090

# 4. Verify service monitor (scrapes banking app)
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor -n monitoring prod-banking-platform-banking-platform

# 5. Test prometheus query
# Visit http://localhost:9090/graph
# Query: up{app="banking-platform"} == 1

# 6. Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Default creds: admin / <password from secret>
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d
```

### Loki Logs Aggregation

```bash
# 1. Deploy Loki stack
kubectl apply -f monitoring/10_loki-stack.yaml

# 2. Verify Loki service
kubectl get svc -n monitoring | grep loki

# 3. Verify S3 bucket configuration
# Loki stores logs in: s3://bankapp-prod-loki-logs-prod/

# 4. Query logs in Grafana
# Data source → Loki: http://loki-stack:3100
# Sample query: {app="banking-platform"}

# 5. View logs from CLI
kubectl logs -n banking-prod deployment/prod-banking-platform-banking-platform \
  --tail=100 -f
```

### Tempo Distributed Tracing

```bash
# 1. Deploy Tempo stack
kubectl apply -f monitoring/5_tempo-stack.yaml

# 2. Verify Tempo service
kubectl get svc -n monitoring | grep tempo

# 3. Verify OTel Collector is forwarding traces
kubectl logs -n monitoring deployment/otel-collector | grep trace

# 4. View traces in Grafana
# Data source → Tempo: http://tempo-stack:3200
# Query: {service="banking-core-service"}

# 5. Enable trace sampling in application
# Set OTEL_TRACES_EXPORTER=otlp in deployment env vars
```

### Service Mesh Observability (Kiali)

```bash
# 1. Deploy Istio base and istiod
kubectl apply -f istio/1_istio-base.yaml
kubectl apply -f istio/3_istiod.yaml

# 2. Deploy Kiali
kubectl apply -f monitoring/8_kiali-stack.yaml

# 3. Port-forward to Kiali
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Open: http://localhost:20001
# Auth: anonymous (configured)

# 4. Explore traffic graph
# Namespaces → banking-prod
# Displays service dependencies, latencies, error rates
```

### Custom Alerts

```bash
# 1. View PrometheusRule
kubectl get prometheusrule -n monitoring
kubectl describe prometheusrule banking-app-alerts -n monitoring

# 2. Verify rules in Prometheus
# http://localhost:9090/alerts

# 3. Configure AlertManager
kubectl get alertmanagerconfig -n monitoring
kubectl describe alertmanager -n monitoring kube-prometheus-stack-alertmanager

# 4. Test alert firing
# Simulate: kubectl delete pod -n banking-prod <pod-name>
# Check AlertManager UI: http://localhost:9093
```

---

## Disaster Recovery

### Velero Backup & Restore

```bash
# 1. Deploy MinIO for backup storage
kubectl apply -f disaster-recovery/2_minio-stack.yaml

# 2. Wait for MinIO
kubectl get svc -n velero minio

# 3. Deploy Velero
kubectl apply -f disaster-recovery/3_velero-app.yaml

# 4. Create Velero credentials
kubectl create secret generic velero-minio-secret \
  --from-literal=cloud='[default]
aws_access_key_id = rohan-admin
aws_secret_access_key = secure-storage-pass' \
  -n velero

# 5. Create backup schedule
kubectl apply -f disaster-recovery/4_velero-schedule.yaml

# 6. Verify schedule
velero schedule get

# 7. Trigger manual backup
velero backup create banking-prod-manual --include-namespaces banking-prod

# 8. Monitor backup progress
velero backup logs banking-prod-manual
velero backup describe banking-prod-manual

# 9. List all backups
velero backup get

# 10. Restore from backup
velero restore create --from-backup banking-prod-manual

# 11. Verify restore
kubectl get all -n banking-prod
```

**Backup Policy:**
- Frequency: Every 6 hours (cron: `0 */6 * * *`)
- Retention: 30 days (720 hours)
- Includes: banking-prod namespace, Kubernetes metadata
- Excludes: PersistentVolumes (EBS snapshots handled separately)
- Storage: MinIO backend (S3 API compatible)

---

## Security & Compliance

### Kyverno Policy Enforcement

```bash
# 1. Deploy Kyverno
kubectl apply -f policy/1_kyverno.yaml

# 2. Wait for webhook to be ready
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kyverno \
  -n kyverno --timeout=300s

# 3. Apply cluster policies
kubectl apply -f policy/2_cluster-policies.yaml

# 4. Verify policies
kubectl get clusterpolicy
kubectl describe clusterpolicy banking-guardrails

# 5. Test policy: Run privileged pod (should be blocked)
kubectl run privileged-test --image=alpine --privileged -n banking-prod
# Expected: Denied by policy "disallow-root-user"

# 6. View policy violations
kubectl logs -n kyverno deployment/kyverno --tail=50
```

**Enforced Policies:**
- Resource limits required (CPU + memory)
- Non-root user enforcement (runAsNonRoot: true)
- Privileged container prevention
- Read-only root filesystem

### Network Policies

```bash
# 1. Deploy network policies
kubectl apply -f helm_k8s/templates/5_network-policy.yaml

# 2. Verify policies
kubectl get networkpolicy -n banking-prod
kubectl describe networkpolicy prod-banking-platform-banking-platform-default-deny

# 3. Test connectivity rules
# DNS (allowed): kubectl exec -it <pod> -- nslookup example.com
# Database (allowed): kubectl exec -it <pod> -- nc -zv <rds-endpoint> 3306
# External (blocked): kubectl exec -it <pod> -- curl http://example.com
```

### Pod Security & RBAC

```bash
# 1. Verify pod security standards
kubectl label namespace banking-prod \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite

# 2. Create service accounts with IRSA
kubectl annotate serviceaccount prod-banking-platform-banking-platform \
  -n banking-prod \
  eks.amazonaws.com/role-arn=arn:aws:iam::959589242185:role/bankapp-prod-app-irsa-role

# 3. Verify RBAC
kubectl auth can-i get secrets --as=system:serviceaccount:banking-prod:prod-banking-platform-banking-platform
kubectl get rolebinding,clusterrolebinding -n banking-prod -o wide
```

### Secrets Management

```bash
# 1. Deploy External Secrets Operator
# (Already referenced in helm chart with ClusterSecretStore)

# 2. Verify ExternalSecret resources
kubectl get externalsecrets -n banking-prod
kubectl describe externalsecret prod-banking-platform-banking-platform-db-secrets

# 3. Verify secret sync from AWS Secrets Manager
kubectl get secret -n banking-prod
kubectl get secret prod-banking-platform-banking-platform-db-secrets -n banking-prod -o yaml | grep DB_PASSWORD
```

---

## Post-Deployment Validation

### Health Checks

```bash
# 1. Cluster health
kubectl get nodes
kubectl get componentstatuses

# 2. Application health
kubectl get deployment -n banking-prod
kubectl get pods -n banking-prod

# 3. Verify running containers
kubectl get pods -n banking-prod -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# 4. Check application logs
kubectl logs -n banking-prod deployment/prod-banking-platform-banking-platform --tail=50

# 5. Health endpoint test
kubectl port-forward -n banking-prod svc/prod-banking-platform-banking-platform-active 8080:80
curl http://localhost:8080/actuator/health
```

### Load Testing

```bash
# 1. Install Apache Bench (ab) or wrk
apt-get install apache2-utils

# 2. Test endpoint
ab -n 1000 -c 10 http://<ALB-DNS>/
# Verify: throughput, latency (p95 < 1500ms), error rate 0%

# 3. Monitor during load test
kubectl top nodes
kubectl top pods -n banking-prod
```

### Database Connectivity

```bash
# 1. Verify RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier bankapp-prod-db \
  --query 'DBInstances[0].Endpoint'

# 2. Connect from EKS pod
kubectl run mysql-client --image=mysql:8.0 -it --rm -- \
  mysql -h <RDS-ENDPOINT> -u bankadmin -p<password> \
  -e "SELECT DATABASE(); SHOW TABLES;"

# 3. Verify encryption at rest
aws rds describe-db-instances \
  --db-instance-identifier bankapp-prod-db \
  --query 'DBInstances[0].[StorageEncrypted,KmsKeyId]'
```

### Ingress & TLS

```bash
# 1. Get ALB DNS name
ALB_DNS=$(kubectl get ingress -n banking-prod -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# 2. Verify TLS certificate
openssl s_client -connect $ALB_DNS:443 -servername api.rohandevops.co.in

# 3. Test DNS resolution
nslookup api.rohandevops.co.in
curl -I https://api.rohandevops.co.in/
```

### Security Scanning Results

```bash
# 1. View ECR scan findings
aws ecr describe-image-scan-findings \
  --repository-name springboot-bankapp \
  --image-id imageTag=<tag>

# 2. View Trivy scan report
cat trivy-report.json | jq '.Results[].Vulnerabilities[] | {Severity, Title}'

# 3. View Dependency Check report
open dependency-check-report/dependency-check-report.html

# 4. View SonarQube quality gate
curl -s http://localhost:9000/api/qualitygates/project_status?projectKey=springboot-bankapp | jq
```

---

## Troubleshooting

### Common Issues & Solutions

#### Issue: Pod CrashLoopBackOff

```bash
# 1. Check pod logs
kubectl logs -n banking-prod <pod-name> --previous

# 2. Describe pod for events
kubectl describe pod -n banking-prod <pod-name>

# Common causes & fixes:
# - Database connection: Verify RDS endpoint, security groups
# - Missing ConfigMap: kubectl get configmap -n banking-prod
# - Missing Secret: kubectl get secrets -n banking-prod
# - OOM Killed: Increase memory limits in values.yaml
```

#### Issue: ImagePullBackOff

```bash
# 1. Verify ECR repository exists
aws ecr describe-repositories --repository-names springboot-bankapp

# 2. Check image push status
aws ecr describe-images \
  --repository-name springboot-bankapp \
  --query 'imageDetails[0]'

# 3. Verify imagePullSecrets in deployment
kubectl get secrets -n banking-prod | grep ecr

# 4. Create docker-registry secret if missing
kubectl create secret docker-registry ecr-secret \
  --docker-server=959589242185.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password) \
  -n banking-prod
```

#### Issue: ArgoCD Application OutOfSync

```bash
# 1. Check application status
argocd app get root-banking-stack --refresh

# 2. View sync differences
argocd app diff root-banking-stack

# 3. Manual sync
argocd app sync root-banking-stack

# 4. Rollback to previous version
argocd app rollback root-banking-stack

# Common causes:
# - Image tag mismatch: Verify Jenkins updated values-prod.yaml
# - Helm chart values: Check for typos in values-prod.yaml
# - CRD drift: Karpenter/Kyverno CRDs may drift (use RespectIgnoreDifferences)
```

#### Issue: Database Connection Timeout

```bash
# 1. Verify RDS is running
aws rds describe-db-instances \
  --db-instance-identifier bankapp-prod-db \
  --query 'DBInstances[0].DBInstanceStatus'

# 2. Check security groups
aws ec2 describe-security-groups \
  --group-ids <rds-sg-id> \
  --query 'SecurityGroups[0].IpPermissions'

# 3. Verify network connectivity from pod
kubectl exec -it <pod-name> -n banking-prod -- \
  nc -zv <RDS-ENDPOINT> 3306

# 4. Check database credentials in secret
kubectl get secret prod-banking-platform-banking-platform-db-secrets \
  -n banking-prod -o yaml
```

#### Issue: High Memory/CPU Usage

```bash
# 1. Identify resource utilization
kubectl top pods -n banking-prod --sort-by=memory

# 2. Check VPA recommendations (if enabled)
kubectl describe vpa banking-predictive-scaler -n banking-prod

# 3. Check HPA status (if enabled)
kubectl get hpa -n banking-prod
kubectl describe hpa prod-banking-platform-banking-platform -n banking-prod

# 4. Adjust resource limits
kubectl set resources deployment prod-banking-platform-banking-platform \
  -n banking-prod \
  --limits=cpu=1000m,memory=2Gi \
  --requests=cpu=500m,memory=1Gi
```

#### Issue: ArgoCD Webhook Timeout

```bash
# 1. Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# 2. Verify webhook is reachable
kubectl get service -n argocd argocd-server

# 3. Port-forward and test
kubectl port-forward -n argocd svc/argocd-server 443:443
curl -k https://localhost/api/version

# 4. Update GitHub webhook URL in repository settings
# Settings → Webhooks → Update payload URL to ArgoCD service endpoint
```

### Debug Mode Deployment

```bash
# 1. Enable verbose logging
kubectl set env deployment/prod-banking-platform-banking-platform \
  -n banking-prod \
  LOG_LEVEL=DEBUG

# 2. Stream logs in real-time
kubectl logs -n banking-prod -l app=banking-platform -f --all-containers=true

# 3. Execute shell in running pod
kubectl exec -it <pod-name> -n banking-prod -- /bin/sh

# 4. Describe resource details
kubectl describe all -n banking-prod | less

# 5. Export resource definitions for review
kubectl get all -n banking-prod -o yaml > debug-dump.yaml
```

### Performance Profiling

```bash
# 1. Check metrics server
kubectl get deployment metrics-server -n kube-system

# 2. View top consumers
kubectl top nodes
kubectl top pods -n banking-prod --sort-by=cpu

# 3. Analyze application metrics
kubectl port-forward -n banking-prod svc/prod-banking-platform-banking-platform-active 8080:80
curl http://localhost:8080/actuator/metrics

# 4. Check Prometheus for historical data
# Query: rate(container_cpu_usage_seconds_total[5m])
```

---

## Rollback Procedures

### Application Rollback

```bash
# 1. Via ArgoCD (instant)
argocd app rollback root-banking-stack <revision-number>

# 2. Via Helm (manual)
helm rollback banking-app 1 --namespace banking-prod

# 3. Via Argo Rollouts (canary/blue-green)
# If using Rollout instead of Deployment:
kubectl argo rollouts promote prod-banking-platform-banking-platform -n banking-prod
```

### Infrastructure Rollback

```bash
# 1. Via Terraform state
terraform apply -refresh=true  # Revert to last known good state

# 2. Restore from backup
velero restore create --from-backup banking-prod-<date> --wait

# 3. Manual recovery from RDS snapshot
aws rds describe-db-snapshots --db-instance-identifier bankapp-prod-db
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier bankapp-prod-db-restore \
  --db-snapshot-identifier <snapshot-id>
```

---

## Production Checklist

- [ ] Terraform backend provisioned (S3 + DynamoDB)
- [ ] EKS cluster created and configured
- [ ] VPC, subnets, route tables, and NAT gateway in place
- [ ] RDS MySQL instance running with Multi-AZ
- [ ] KMS key created for encryption
- [ ] IAM roles and policies configured (IRSA)
- [ ] ECR repository created and image pushed
- [ ] Database credentials stored in Secrets Manager
- [ ] Kubernetes namespaces created (banking-prod, monitoring, argocd)
- [ ] ArgoCD installed and configured
- [ ] Jenkins pipeline running successfully
- [ ] Prometheus, Grafana, Loki, Tempo deployed
- [ ] Kyverno policies enforced
- [ ] Network policies applied
- [ ] Velero backup schedule active
- [ ] TLS certificate issued and valid
- [ ] DNS records pointing to ALB
- [ ] Application health checks passing
- [ ] Monitoring dashboards populated with metrics
- [ ] Alerting rules configured and tested
- [ ] Security scanning enabled (Trivy, SonarQube, OWASP)
- [ ] Backup restoration tested
- [ ] Load testing completed successfully
- [ ] Documentation updated

---

## Support & Escalation

**On-Call Runbook:** See `oncall-runbook.md` (to be created)

**Critical Issues:**
1. Pod CrashLoopBackOff → Check logs → RDS/Secret/ConfigMap
2. Database down → AWS RDS console → Restore from snapshot
3. ArgoCD sync failed → Manual `argocd app sync` + review Git changes
4. Security breach → Enable GuardDuty → Review CloudTrail → Quarantine resources

**Contacts:**
- Infrastructure: DevOps team
- Application: Backend team  
- Database: DBA on-call
- Security: Security operations center (SOC)

---

**Last Updated:** June 2026  
**Maintained By:** Ruhon (rohandeb2)  
**Repository:** https://github.com/rohandeb2/sspringboot-bankapp
