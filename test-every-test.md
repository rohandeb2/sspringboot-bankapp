# 🏦 Banking Platform — Full Validation Guide

---

## 📑 Table of Contents

- [ArgoCD](#argocd)
- [Autoscaling](#autoscaling)
- [Disaster Recovery](#disaster-recovery)
- [K8s Manifests](#k8s-manifests)
- [Policy](#policy)
- [Security Scanning](#security-scanning)
- [Service Mesh](#service-mesh)
- [Jenkins / Vars with Jenkinsfile](#vars--jenkins-with-jenkinsfile)
- [Scripts](#scripts)
- [Dockerfile](#dockerfile)
- [Docker Compose](#docker-composeyaml)
- [VPA](#vpa)
- [Monitoring](#monitoring)
  - [Prometheus](#prometheus)
  - [Grafana](#grafana)
  - [Tempo](#tempo)
  - [Kiali](#kiali)
  - [OpenTelemetry Collector](#otel)
  - [Loki](#loki)
  - [AI Alerts](#ai_alertspy)
- [Banking App Alerts](#banking-app)

---

## ArgoCD

### 1️⃣ External Secret (Git Credentials)

#### ✅ What's Setup

- Fetches GitHub credentials from AWS Secrets Manager (`banking-github-creds`)
- Creates Kubernetes Secret `banking-repo-creds` in `argocd`
- Used by ArgoCD for repo authentication
- Auto-refresh every 1 hour

#### 🔍 Existence Check

```bash
kubectl get externalsecret -n argocd
kubectl get secret banking-repo-creds -n argocd
```

#### 🚀 Real Validation

**Test 1: Secret Auto-Recreation**

```bash
kubectl delete secret banking-repo-creds -n argocd
```

Expected:
- ✔ Secret recreated automatically

**Test 2: Actual Usage**

```bash
argocd app sync <your-app>
```

Expected:
- ✔ Sync succeeds (repo access working)

---

### 2️⃣ ArgoCD AppProject (Security Boundary)

#### ✅ What's Setup

- Only repo allowed: `sspringboot-bankapp`
- Only namespace allowed: `banking-prod`
- Resource restrictions applied (Deployment, Service, HPA, etc.)
- Roles defined (read-only, admin)

#### 🔍 Existence Check

```bash
kubectl get appproject banking-core-project -n argocd
```

#### 🚀 Real Validation

**✅ Test 1: Valid Case (PASS)**

```bash
argocd app create test-app \
  --repo https://github.com/rohandeb2/sspringboot-bankapp.git \
  --path . \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace banking-prod \
  --project banking-core-project

argocd app sync test-app
```

Expected:
- ✔ Deployment succeeds

**❌ Test 2: Wrong Repo (FAIL)**

```bash
argocd app create bad-app \
  --repo https://github.com/other/repo.git \
  ...
```

Expected:
- ❌ Rejected

**❌ Test 3: Wrong Namespace (FAIL)**

```bash
--dest-namespace default
```

Expected:
- ❌ Rejected

---

### 3️⃣ ApplicationSet (Auto Deployment)

#### ✅ What's Setup

Auto-creates 3 apps:
- `prod-banking-platform`
- `infra-istio-istio-base`
- `security-sonarqube`
- Auto-sync enabled (prune + selfHeal)
- Auto namespace creation

#### 🔍 Existence Check

```bash
kubectl get applicationset -n argocd
kubectl get applications -n argocd
```

#### 🚀 Real Validation

**Test 1: Auto-Recreation**

```bash
kubectl delete application prod-banking-platform -n argocd
```

Expected:
- ✔ App recreated automatically

**Test 2: Self-Heal**

```bash
kubectl delete pod <pod-name> -n banking-prod
```

Expected:
- ✔ Pod recreated

**Test 3: Git Change**

Modify replicas in repo

Expected:
- ✔ Auto-sync updates cluster

**Test 4: Prune**

Remove resource from Git

Expected:
- ✔ Resource deleted from cluster

---

### 4️⃣ AnalysisTemplate (Deployment Validation)

#### ✅ What's Setup

- Uses Prometheus metrics
- Validates success rate ≥ 99.5%
- Runs every 1 min (5 times)
- Fails after 2 errors

#### 🔍 Existence Check

```bash
kubectl get analysistemplate -n banking-prod
```

> ⚠️ **Important Note:** This template does NOT run automatically. It only works when used in an Argo Rollout.

#### 🔍 Check if it is actually used

```bash
kubectl get analysisrun -n banking-prod
# If empty → ❌ Not being used
```

#### 🚀 Real Validation

**✅ Test 1: Good Traffic (PASS)**

```bash
# Send normal traffic
kubectl get analysisrun -n banking-prod
kubectl describe analysisrun <name> -n banking-prod
```

Expected:
- ✔ Status = Successful
- ✔ Value ≥ 0.995

**❌ Test 2: Break App (FAIL)**

```bash
# Force 500 errors / stop backend
kubectl describe analysisrun <name> -n banking-prod
```

Expected:
- ❌ Status = Failed

**❌ Test 3: No Metrics (FAIL)**

Remove `http_requests_total`

Expected:
- ❌ Empty result / Failed

#### 📊 Optional (Metric Verification)

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090
# Open → http://localhost:9090
# Run query to verify success rate
```

---

## Autoscaling

### 1️⃣ Karpenter

#### ✅ What's Setup

- Karpenter installed via ArgoCD
- Auto node scaling enabled (EKS)
- Uses IAM role (IRSA)

#### 🔍 Check

```bash
kubectl get pods -n karpenter
kubectl get nodepool   # or kubectl get provisioner
```

#### 🚀 Test (REAL)

Create unschedulable pod:

```bash
kubectl run test --image=busybox --requests='cpu=2' -- sleep 3600
```

Watch:

```bash
kubectl get pods -w
kubectl get nodes -w
```

#### 🎯 Expected

- Pod → Pending
- New node created
- Pod → Running

#### ❌ If not working

- No node → NodePool/Provisioner missing
- Still pending → IAM / config issue

---

### 2️⃣ EC2NodeClass — FULL VALIDATION

#### ✅ Setup

- EC2 config for nodes (AMI, IAM role, subnet, SG)
- AMI: AL2023 (`al2023@latest`)
- Subnet/SG via tag: `karpenter.sh/discovery=bankapp-prod`
- IAM Role: `bankapp-prod-karpenter-node-role`

#### 🔍 Step 1: Pre-check (everything exists)

```bash
kubectl get pods -n karpenter
kubectl get ec2nodeclass
kubectl get nodepool   # or provisioner
```

Expected:
- Karpenter pod Running
- EC2NodeClass = `default`
- NodePool exists

#### 🚀 Step 2: Trigger scaling (real test)

```bash
kubectl run test --image=busybox --requests='cpu=2' -- sleep 3600
kubectl get pods -w
```

Expected:
- Pod = Pending (no capacity)

#### 🚀 Step 3: Observe node creation

```bash
kubectl get nodes -w
```

Expected:
- New node appears in cluster

#### 🚀 Step 4: Pod scheduling

```bash
kubectl get pods -w
```

Expected:
- Pod moves: Pending → Running

#### 🔍 Step 5: Verify EC2NodeClass is USED (CRITICAL)

```bash
# Get new node name
kubectl get nodes

# Inspect node
kubectl describe node <node-name>
```

Verify:
- Karpenter labels present
- Node created by Karpenter

#### 🔍 Step 6: AWS-level verification (MOST IMPORTANT)

In AWS Console → EC2 → Instances

Verify:
- ✔ AMI = AL2023
- ✔ IAM Role = `bankapp-prod-karpenter-node-role`
- ✔ Subnet tag = `bankapp-prod`
- ✔ Security Group tag = `bankapp-prod`

#### 🧹 Step 7: Scale down test (cleanup)

```bash
kubectl delete pod test
kubectl get nodes -w
```

Expected:
- Node eventually terminated (if no workload)

#### 🎯 FINAL RESULT (What to tell client)

- ✔ Node created on demand
- ✔ Correct AWS config applied (AMI, IAM, network)
- ✔ Pod scheduled successfully
- ✔ Node removed after use

#### ❌ If any step fails

- No node → NodePool / config issue
- Node wrong config → EC2NodeClass issue
- Pod stuck → scheduling / limits issue
- Node not deleted → consolidation not working

> 🏁 **FINAL CLAIM:** "The autoscaling system using Karpenter has been validated end-to-end, including node provisioning, correct infrastructure configuration, workload scheduling, and scale-down behavior."

---

### 3️⃣ NodePool Configuration

#### ✅ What's Setup

- Defines how nodes are created by Karpenter
- Uses EC2NodeClass: `default`
- Allows capacity: spot + on-demand
- Instance types: t / m / c families
- Architecture: amd64
- Auto scale-down (consolidation after 30s)
- Node expiry: 720h

#### 🔍 Step 1: Pre-check

```bash
kubectl get nodepool
kubectl describe nodepool default
```

Expected:
- NodePool exists
- `nodeClassRef` → `default`

#### 🚀 Step 2: Trigger scaling

```bash
kubectl run test --image=busybox --requests='cpu=2' -- sleep 3600
kubectl get pods -w
```

Expected:
- Pod = Pending

#### 🚀 Step 3: Node creation

```bash
kubectl get nodes -w
```

Expected:
- New node created

#### 🔍 Step 4: Verify NodePool rules

```bash
kubectl describe node <node-name>
```

Verify:
- ✔ capacity-type = spot/on-demand
- ✔ instance type = t/m/c family
- ✔ arch = amd64
- ✔ using EC2NodeClass = `default`

#### 🔍 Step 5: AWS verification (CRITICAL)

AWS Console → EC2 → Instances

Verify:
- ✔ Instance type → t/m/c family
- ✔ Purchase option → spot or on-demand
- ✔ AMI → AL2023
- ✔ IAM Role → `bankapp-prod-karpenter-node-role`
- ✔ Subnet/SG → `bankapp-prod` tags

#### 🧹 Step 6: Scale down test

```bash
kubectl delete pod test
kubectl get nodes -w
```

Expected:
- Node removed after ~30s (underutilized)

#### 🎯 Final Result

- ✔ Node created on demand
- ✔ Correct infra config applied
- ✔ Workload scheduled
- ✔ Node auto-terminated

#### ❌ If not working

- No node → NodePool/NodeClass issue
- Wrong instance → requirement misconfig
- Node not deleted → consolidation issue

> 🏁 **Final Claim:** "The NodePool configuration has been validated end-to-end, including provisioning, constraint enforcement, and automatic consolidation behavior."

---

## Disaster Recovery

### 1️⃣ Velero Namespace + Security + Quota — FULL VALIDATION

#### ✅ What's Setup

- Namespace: `velero` (isolated for backups)
- Pod Security: privileged (needed for volume access)
- ResourceQuota: CPU/Memory limits enforced
- NetworkPolicy:
  - Ingress: only from argocd + velero namespace
  - Egress: allowed to internet + all namespaces

#### 🔍 Step 1: Pre-check

```bash
kubectl get ns velero
kubectl get resourcequota -n velero
kubectl get networkpolicy -n velero
```

Expected:
- Namespace exists
- Quota applied
- NetworkPolicy present

#### 🔍 Step 2: Verify labels (IMPORTANT)

```bash
kubectl get ns velero --show-labels
```

Expected:
- `pod-security.kubernetes.io/enforce=privileged`

#### 🚀 Step 3: ResourceQuota test

```bash
# Try exceeding CPU
kubectl run quota-test --image=busybox -n velero \
  --requests='cpu=600m' -- sleep 3600
```

Expected:
- ❌ Pod rejected (quota exceeded)

#### 🚀 Step 4: NetworkPolicy test (Ingress)

```bash
# From another namespace (not argocd)
kubectl run test --image=busybox -n default -- sleep 3600

# Try to connect to velero pod (simulate)
kubectl exec -n default test -- wget <velero-pod-ip>
```

Expected:
- ❌ Connection blocked

#### 🚀 Step 5: Allowed traffic test

```bash
# From argocd namespace
kubectl run test --image=busybox -n argocd -- sleep 3600
kubectl exec -n argocd test -- wget <velero-pod-ip>
```

Expected:
- ✔ Connection allowed

#### 🚀 Step 6: Egress test

```bash
kubectl exec -n velero <velero-pod> -- wget google.com
```

Expected:
- ✔ Outbound internet works

#### 🎯 Final Result

- ✔ Namespace isolated
- ✔ Resource limits enforced
- ✔ Network restricted properly
- ✔ External access allowed for backups

#### ❌ If not working

- Pod not blocked → quota misconfig
- Traffic not blocked → NetworkPolicy not enforced
- No internet → egress issue

> 🏁 **Final Claim:** "The Velero namespace is secured, resource-controlled, and network-isolated, with verified access policies and operational readiness for backup and restore operations."

---

### 2️⃣ MinIO (ArgoCD Application) — FULL VALIDATION

#### ✅ What's Setup

- Deploys MinIO via Helm (Bitnami chart)
- Image pulled from private ECR
- Credentials: rootUser / rootPassword
- Persistent storage: 50Gi
- Service: ClusterIP
- Default bucket: `velero-backups`
- Runs in `velero` namespace (for backups)
- Security: non-root user enforced

#### 🔍 Step 1: Pre-check

```bash
kubectl get application minio -n argocd
kubectl get pods -n velero
kubectl get svc -n velero
```

Expected:
- MinIO pod Running
- Service exists

#### 🔍 Step 2: Check storage

```bash
kubectl get pvc -n velero
```

Expected:
- PVC bound (50Gi)

#### 🚀 Step 3: Access MinIO UI

```bash
kubectl port-forward svc/minio -n velero 9001:9001
# Open: http://localhost:9001
# Login: user: rohan-admin / pass: secure-storage-pass
```

Expected:
- ✔ UI accessible

#### 🚀 Step 4: Bucket verification

```bash
# In UI: Check bucket: velero-backups exists
# OR via CLI (inside pod):
kubectl exec -n velero <minio-pod> -- mc ls local
```

Expected:
- ✔ `velero-backups` present

#### 🚀 Step 5: Write test (REAL)

```bash
kubectl exec -n velero <minio-pod> -- \
  sh -c "echo test > /tmp/file && mc cp /tmp/file local/velero-backups/"
```

Expected:
- ✔ File uploaded successfully

#### 🚀 Step 6: Restart test (persistence)

```bash
kubectl delete pod -n velero <minio-pod>
kubectl get pods -w -n velero
# After restart: Check file still exists
```

Expected:
- ✔ Data persists

#### 🔍 Step 7: Image verification

```bash
kubectl describe pod <minio-pod> -n velero
```

Verify:
- ✔ Image from ECR
- ✔ Running as non-root (1001)

#### 🎯 Final Result

- ✔ MinIO running
- ✔ Storage working
- ✔ Bucket created
- ✔ Data persists after restart
- ✔ Secure configuration applied

#### ❌ If not working

- Pod crash → image/command issue
- PVC pending → storage class issue
- No UI → service/port issue
- Data lost → persistence issue

> 🏁 **Final Claim:** "MinIO object storage has been validated for deployment, access, persistence, and secure configuration, and is fully operational for backup storage use cases."

---

### 3️⃣ Velero (ArgoCD Application) — FULL VALIDATION

#### ✅ What's Setup

- Deploys Velero via Helm
- Backup storage: AWS S3 bucket (`bankapp-velero-backups-959589242185`)
- Snapshot: AWS (EBS)
- Uses IRSA: `bankapp-prod-velero-irsa` (no static creds)
- AWS plugin enabled
- Auto-sync (prune + selfHeal)

#### 🔍 Step 1: Pre-check

```bash
kubectl get application velero -n argocd
kubectl get pods -n velero
```

Expected:
- Velero pod Running

#### 🔍 Step 2: Check logs (IMPORTANT)

```bash
kubectl logs -n velero deployment/velero
```

Expected:
- ✔ No AWS / permission errors

#### 🔍 Step 3: Check backup location

```bash
kubectl get backupstoragelocation -n velero
kubectl describe backupstoragelocation -n velero
```

Expected:
- ✔ Phase = Available

#### 🚀 Step 4: Create test backup

```bash
kubectl create ns test-backup
kubectl run nginx --image=nginx -n test-backup
velero backup create test-backup --include-namespaces test-backup

# Watch:
velero backup get
```

Expected:
- ✔ Status = Completed

#### 🚀 Step 5: Verify in AWS (CRITICAL)

AWS Console → S3 → bucket

Expected:
- ✔ Backup files present

#### 🚀 Step 6: Restore test (REAL)

```bash
kubectl delete ns test-backup
velero restore create --from-backup test-backup
kubectl get ns
```

Expected:
- ✔ Namespace restored
- ✔ Pod restored

#### 🚀 Step 7: Snapshot test (optional)

```bash
velero backup describe test-backup --details
```

Expected:
- ✔ Volume snapshots created (if PVC exists)

#### 🎯 Final Result

- ✔ Backup created
- ✔ Stored in S3
- ✔ Restore successful
- ✔ IRSA working (no static creds)

#### ❌ If not working

- Backup fails → IAM / S3 issue
- Location unavailable → config error
- Restore fails → snapshot/permission issue

> 🏁 **Final Claim:** "Velero backup and restore system has been validated end-to-end, including AWS integration, secure access via IRSA, and successful recovery of workloads."

---

### 4️⃣ Velero Schedule — FULL VALIDATION

#### ✅ What's Setup

- Scheduled backups every 6 hours
- Target namespace: `banking-prod`
- Retention: 720h (30 days)
- Uses storageLocation: `default` (S3)
- Volume snapshots disabled

#### 🔍 Step 1: Pre-check

```bash
kubectl get schedule -n velero
kubectl describe schedule banking-prod-daily-backup -n velero
```

Expected:
- Schedule exists
- Cron: `*/6` hours

#### 🚀 Step 2: Manual trigger (don't wait 6h)

```bash
velero backup create manual-test --from-schedule banking-prod-daily-backup
velero backup get
```

Expected:
- ✔ Backup created
- ✔ Status = Completed

#### 🔍 Step 3: Verify backup content

```bash
velero backup describe manual-test --details
```

Expected:
- ✔ Includes namespace: `banking-prod`

#### 🔍 Step 4: AWS verification (CRITICAL)

AWS Console → S3 → bucket

Expected:
- ✔ Backup files created

#### 🚀 Step 5: Restore test (REAL)

```bash
kubectl create ns temp-test
velero restore create --from-backup manual-test
kubectl get ns
```

Expected:
- ✔ banking-prod resources restored (or test namespace if mapped)

#### 🔍 Step 6: Auto-schedule validation

```bash
kubectl get backups -n velero --watch
```

Expected:
- ✔ New backups created every 6 hours

#### 🎯 Final Result

- ✔ Backup runs on schedule
- ✔ Correct namespace backed up
- ✔ Stored in S3
- ✔ Restore works

#### ❌ If not working

- No backup → schedule misconfig
- Backup fails → IAM/S3 issue
- Empty backup → namespace issue

> 🏁 **Final Claim:** "Automated backup scheduling has been validated, ensuring periodic backups of production workloads with successful storage and recovery capability."

---

## K8s Manifests

### 1️⃣ ArgoCD Root Application (App of Apps) — FULL VALIDATION

#### ✅ What's Setup

- Root app manages entire repo (recursive)
- Excludes non-K8s files (terraform, src, etc.)
- Auto-sync enabled (prune + selfHeal)
- Retry with backoff configured
- IgnoreDifferences for ExternalSecret & Kyverno
- Acts as "App of Apps" (controls all child apps)

#### 🔍 Step 1: Pre-check

```bash
kubectl get application root-banking-stack -n argocd
```

Expected:
- Application exists

#### 🔍 Step 2: Sync status

```bash
kubectl get applications -n argocd
```

Expected:
- `root-banking-stack` = Synced / Healthy
- Child apps also present

#### 🚀 Step 3: Child app creation (REAL)

```bash
kubectl get applications -n argocd
```

Expected:
- ✔ All apps from repo created automatically

#### 🚀 Step 4: Self-heal test

```bash
# Delete any resource managed by ArgoCD
kubectl delete deployment <any-app> -n <namespace>

# Watch:
kubectl get pods -w -n <namespace>
```

Expected:
- ✔ Resource recreated automatically

#### 🚀 Step 5: Git change test

```bash
# Change something in repo (e.g., replicas)
# Wait or refresh sync
kubectl get applications -n argocd
```

Expected:
- ✔ Change applied automatically

#### 🚀 Step 6: Prune test

Remove a resource from Git

Expected:
- ✔ Resource deleted from cluster

#### 🔍 Step 7: IgnoreDifferences test (IMPORTANT)

```bash
# Modify ExternalSecret or Kyverno rule manually
kubectl edit externalsecret <name>
```

Expected:
- ✔ ArgoCD does NOT revert those fields

#### 🔍 Step 8: Retry behavior

```bash
# Break app (wrong image, bad config)
kubectl get applications -n argocd
```

Expected:
- ✔ Argo retries sync (5 times with backoff)

#### 🎯 Final Result

- ✔ Root app manages all resources
- ✔ Auto-sync + self-heal working
- ✔ Drift handled correctly
- ✔ Selective ignore working
- ✔ Retry mechanism active

#### ❌ If not working

- No child apps → path/exclude issue
- No auto-sync → syncPolicy issue
- Drift not fixed → selfHeal not working
- Ignore not working → config issue

> 🏁 **Final Claim:** "The root ArgoCD application has been validated for full lifecycle management, including automated deployment, drift correction, selective reconciliation, and failure recovery across all managed resources."

---

## Policy

### 1️⃣ Kyverno (ArgoCD Application) — FULL VALIDATION

#### ✅ What's Setup

- Installs Kyverno via Helm
- Policy engine for Kubernetes (admission control)
- Auto-sync enabled (prune + selfHeal)
- Deploys in `kyverno` namespace

#### 🔍 Step 1: Pre-check

```bash
kubectl get application kyverno -n argocd
kubectl get pods -n kyverno
```

Expected:
- Kyverno pods Running

#### 🔍 Step 2: Check components

```bash
kubectl get deploy -n kyverno
```

Expected:
- ✔ kyverno-admission-controller
- ✔ kyverno-background-controller
- ✔ kyverno-cleanup-controller

#### 🚀 Step 3: Policy enforcement test (REAL)

```bash
# Create invalid pod (no labels / violates policy)
kubectl run bad-pod --image=nginx
```

Expected:
- ❌ Request denied by Kyverno (if policy exists)

#### 🚀 Step 4: Mutation test (if enabled)

```bash
kubectl run test-pod --image=nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl get pod test-pod -o yaml
```

Expected:
- ✔ Labels/fields auto-added by Kyverno

#### 🔍 Step 5: Logs verification

```bash
kubectl logs -n kyverno deploy/kyverno-admission-controller
```

Expected:
- ✔ Policy evaluation logs (allow/deny)

#### 🚀 Step 6: Self-heal test

```bash
kubectl delete deployment kyverno-admission-controller -n kyverno
```

Expected:
- ✔ ArgoCD recreates it

#### 🎯 Final Result

- ✔ Kyverno installed and running
- ✔ Policies enforced (deny/mutate)
- ✔ Admission controller active
- ✔ Auto-healing working

#### ❌ If not working

- Pods not running → install issue
- No deny → no policies applied
- No mutation → config missing
- Logs empty → controller issue

> 🏁 **Final Claim:** "Kyverno policy engine has been validated for deployment, enforcement, and mutation capabilities, ensuring Kubernetes admission control is functioning as expected."

---

### 2️⃣ Kyverno ClusterPolicy (banking-guardrails) — FULL VALIDATION

#### ✅ What's Setup

- Enforces cluster-wide security rules
- Rule 1: Pods in `banking-prod` MUST have CPU & memory limits
- Rule 2: Pods cannot run as root (except system namespaces)
- Mode: Enforce (blocks invalid resources)
- Background scan enabled

#### 🔍 Step 1: Pre-check

```bash
kubectl get clusterpolicy
kubectl describe clusterpolicy banking-guardrails
```

Expected:
- Policy exists
- `validationFailureAction = Enforce`

#### 🚀 Step 2: Test Resource Limits (FAIL case)

```bash
kubectl run bad-pod --image=nginx -n banking-prod
```

Expected:
- ❌ Denied (no resource limits)

#### 🚀 Step 3: Test Resource Limits (PASS case)

```bash
kubectl run good-pod --image=nginx -n banking-prod \
  --limits='cpu=200m,memory=256Mi'
```

Expected:
- ✔ Pod created

#### 🚀 Step 4: Test Root User (FAIL case)

```bash
kubectl run root-pod --image=nginx \
  --overrides='
  {
    "spec": {
      "securityContext": {
        "runAsNonRoot": false
      }
    }
  }'
```

Expected:
- ❌ Denied

#### 🚀 Step 5: Test Allowed Namespace (PASS)

```bash
kubectl run monitor-test --image=nginx -n monitoring
```

Expected:
- ✔ Allowed (excluded namespace)

#### 🔍 Step 6: Background scan check

```bash
kubectl get policyreport -A
```

Expected:
- ✔ Violations listed for existing resources

#### 🔍 Step 7: Logs verification

```bash
kubectl logs -n kyverno deploy/kyverno-admission-controller
```

Expected:
- ✔ Policy decisions (allow/deny)

#### 🎯 Final Result

- ✔ Resource limits enforced
- ✔ Root access blocked
- ✔ Exceptions working correctly
- ✔ Background scan active

#### ❌ If not working

- Pod allowed → policy not enforced
- No violations → background scan issue
- Root allowed → rule misconfig

> 🏁 **Final Claim:** "Cluster-wide security guardrails have been validated, enforcing resource limits and non-root execution, ensuring compliance and stability across workloads."

---

### 3️⃣ aws-auth ConfigMap (EKS Node Access) — FULL VALIDATION

#### ✅ What's Setup

- Maps IAM roles → Kubernetes node identity
- Allows nodes to join cluster
- Roles:
  - ✔ `bankapp-prod-eks-node-role` (default nodes)
  - ✔ `bankapp-prod-karpenter-node-role` (Karpenter nodes)
- Grants groups: `system:bootstrappers`, `system:nodes`

#### 🔍 Step 1: Pre-check

```bash
kubectl get configmap aws-auth -n kube-system
kubectl describe configmap aws-auth -n kube-system
```

Expected:
- Both IAM roles present in `mapRoles`

#### 🚀 Step 2: Node join test (REAL)

```bash
# Trigger node creation (Karpenter or ASG)
kubectl run test --image=busybox --requests='cpu=2' -- sleep 3600
kubectl get nodes -w
```

Expected:
- ✔ New node joins cluster (Ready state)

#### 🔍 Step 3: Verify node identity

```bash
kubectl get nodes -o wide
```

Expected:
- ✔ Node appears with internal DNS name
- ✔ Node is NOT in NotReady state

#### 🔍 Step 4: Describe node

```bash
kubectl describe node <node-name>
```

Verify:
- ✔ Node authenticated as `system:node:<dns>`
- ✔ No auth errors

#### 🚀 Step 5: Negative test (IMPORTANT)

```bash
# Remove role temporarily (simulate issue)
# (edit aws-auth and remove karpenter role)
kubectl get nodes -w
```

Expected:
- ❌ New nodes fail to join (NotReady / not visible)

#### 🎯 Final Result

- ✔ Nodes successfully join cluster
- ✔ IAM roles correctly mapped
- ✔ Karpenter nodes authenticated
- ✔ No bootstrap/auth issues

#### ❌ If not working

- Node not joining → role missing in aws-auth
- Node NotReady → IAM / networking issue
- No scaling → Karpenter blocked

> 🏁 **Final Claim:** "EKS node authentication has been validated, ensuring both managed and Karpenter-provisioned nodes can securely join and operate within the cluster."

---

## Security Scanning

### 1️⃣ SonarQube (ArgoCD Application) — FULL VALIDATION

#### ✅ What's Setup

- Deploys SonarQube via Helm
- PostgreSQL DB enabled (20Gi)
- App persistence enabled (10Gi)
- Resource limits defined (CPU/Mem)
- Exposed via Ingress (`sonarqube.rohandevops.co.in`)
- Auto-sync enabled (prune + selfHeal)

#### 🔍 Step 1: Pre-check

```bash
kubectl get application sonarqube -n argocd
kubectl get pods -n devsecops
kubectl get svc -n devsecops
```

Expected:
- SonarQube pod Running
- PostgreSQL pod Running

#### 🔍 Step 2: Storage check

```bash
kubectl get pvc -n devsecops
```

Expected:
- ✔ 2 PVCs (DB + SonarQube) Bound

#### 🚀 Step 3: Access UI

```bash
kubectl get ingress -n devsecops
# Open: http://sonarqube.rohandevops.co.in
```

Expected:
- ✔ UI loads

#### 🚀 Step 4: Login test

Default:
- user: `admin`
- pass: `admin` (or changed)

Expected:
- ✔ Login successful

#### 🚀 Step 5: DB connectivity (REAL)

```bash
kubectl logs -n devsecops <sonarqube-pod>
```

Expected:
- ✔ Connected to PostgreSQL (no DB errors)

#### 🚀 Step 6: Persistence test

```bash
kubectl delete pod -n devsecops <sonarqube-pod>
kubectl get pods -w -n devsecops
# After restart: ✔ Data still present (projects/settings)
```

#### 🚀 Step 7: Self-heal test

```bash
kubectl delete deployment -n devsecops <sonarqube-deployment>
```

Expected:
- ✔ ArgoCD recreates it

#### 🚀 Step 8: Real scan test (IMPORTANT)

```bash
sonar-scanner \
  -Dsonar.projectKey=test \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://sonarqube.rohandevops.co.in \
  -Dsonar.login=<token>
```

Expected:
- ✔ Project appears in UI
- ✔ Scan results visible

#### 🎯 Final Result

- ✔ SonarQube running
- ✔ DB connected
- ✔ Persistent storage working
- ✔ UI accessible
- ✔ Code scan working

#### ❌ If not working

- Pod crash → resource/DB issue
- No UI → ingress/DNS issue
- Data loss → PVC issue
- Scan fails → network/token issue

> 🏁 **Final Claim:** "SonarQube has been validated for deployment, persistence, database connectivity, external access, and real code analysis, ensuring full functionality for DevSecOps workflows."

---

## Service Mesh

### 1️⃣–6️⃣ Istio Service Mesh + Gateway + TLS — FULL VALIDATION

#### ✅ What's Setup

- Istio base + control plane (istiod)
- Ingress Gateway (AWS NLB, internet-facing)
- mTLS STRICT enabled (secure pod-to-pod)
- Gateway + VirtualService for routing
- Domains:
  - ✔ `rohandevops.co.in`
  - ✔ `api.rohandevops.co.in`
- TLS via cert-manager (Let's Encrypt)
- Auto-scaling enabled (gateway + istiod)

#### 🔍 Step 1: Pre-check

```bash
kubectl get application -n argocd | grep istio
kubectl get pods -n istio-system
```

Expected:
- ✔ istiod Running
- ✔ ingressgateway Running

#### 🔍 Step 2: Gateway service

```bash
kubectl get svc -n istio-system
```

Expected:
- ✔ LoadBalancer service
- ✔ External IP (AWS NLB)

#### 🚀 Step 3: External access test

```
# Open in browser:
http://rohandevops.co.in
http://api.rohandevops.co.in
```

Expected:
- ✔ Traffic reaches app

#### 🔍 Step 4: Routing validation

```bash
kubectl get virtualservice -A
kubectl describe virtualservice banking-vs -n banking-prod
```

Expected:
- ✔ Routes to bankapp service

#### 🔐 Step 5: TLS validation

```bash
kubectl get certificate -n istio-system
kubectl describe certificate banking-tls-cert -n istio-system
```

Expected:
- ✔ Status = Ready

```
# Browser: https://rohandevops.co.in
```

Expected:
- ✔ Valid SSL (no warning)

#### 🔐 Step 6: mTLS test (CRITICAL)

```bash
kubectl exec -it <pod> -n banking-prod -- curl http://<another-pod-ip>
```

Expected:
- ❌ Direct call blocked (STRICT mTLS)

```bash
# Through service:
kubectl exec -it <pod> -n banking-prod -- curl http://service-name
```

Expected:
- ✔ Allowed via Istio

#### 🚀 Step 7: Autoscaling test

```bash
kubectl get hpa -n istio-system
# Generate load (optional)
```

Expected:
- ✔ Replicas increase (gateway / istiod)

#### 🔍 Step 8: ACME challenge test

```bash
kubectl get virtualservice -n istio-system | grep acme
```

Expected:
- ✔ Routes exist for `/.well-known/acme-challenge/`

#### 🔍 Step 9: Self-heal test

```bash
kubectl delete pod -n istio-system <istio-pod>
```

Expected:
- ✔ Recreated by ArgoCD

#### 🎯 Final Result

- ✔ Service mesh running
- ✔ External traffic working
- ✔ TLS secured
- ✔ mTLS enforced
- ✔ Routing correct
- ✔ Auto-scaling working

#### ❌ If not working

- No external IP → LB issue
- 404 → VirtualService issue
- TLS fail → cert-manager issue
- mTLS not enforced → PeerAuth issue

> 🏁 **Final Claim:** "Istio service mesh has been validated end-to-end, including secure traffic (mTLS), external exposure via gateway, TLS automation, and intelligent routing for production workloads."

---

## Vars / Jenkins with Jenkinsfile

### Jenkins DevSecOps Pipeline — FULL VALIDATION

#### ✅ What's Setup

- CI/CD pipeline (Jenkins)
- Build: Maven (Java app)
- SAST: SonarQube (quality gate enforced)
- SCA: OWASP Dependency Check
- Image: Docker build + Trivy scan (CRITICAL vuln block)
- Registry: AWS ECR push
- GitOps: Updates Helm values (ArgoCD auto deploy)
- Notifications: Email + AI RCA on failure

#### 🔍 Step 1: Pre-check (Jenkins setup)

In Jenkins UI:
- Agent: `banking-agent` available
- Tools:
  - ✔ Maven container
  - ✔ Docker client
  - ✔ Trivy
  - ✔ AWS CLI
- Credentials:
  - ✔ `github-token`
  - ✔ `SonarQube-Server`
  - ✔ AWS access (IRSA or creds)

#### 🚀 Step 2: Trigger pipeline

Jenkins UI → Build Now

Expected:
- ✔ Pipeline starts successfully

#### 🚀 Step 3: Build stage

```bash
mvn clean package
```

Expected:
- ✔ Build SUCCESS
- ✔ JAR created

#### 🚀 Step 4: SAST (SonarQube)

Check logs:
- ✔ Analysis runs
- ✔ Quality Gate = OK

❌ Negative test: Add bad code (bug/vuln)

Expected:
- ❌ Pipeline FAIL at quality gate

#### 🚀 Step 5: SCA (Dependency Check)

Expected:
- ✔ Report generated (HTML)

Check: Jenkins → Artifacts → `dependency-check-report.html`

#### 🚀 Step 6: Docker + Trivy

Expected:
- ✔ Image built

❌ Negative test: Use vulnerable base image

Expected:
- ❌ Pipeline FAIL (CRITICAL vuln)

#### 🚀 Step 7: Push to ECR

```bash
aws ecr describe-images --repository-name springboot-bankapp
```

Expected:
- ✔ Image with BUILD_NUMBER tag exists

#### 🚀 Step 8: GitOps update

Check GitHub repo: `values-prod.yaml` updated

Expected:
- ✔ New image tag committed

#### 🚀 Step 9: ArgoCD auto deploy

```bash
kubectl get pods -n banking-prod
```

Expected:
- ✔ New pods with updated image

#### 🚀 Step 10: Email notification

- Success: ✔ Email received
- Failure: ✔ Email with AI RCA report

#### 🎯 Final Result

- ✔ Build pipeline working
- ✔ Security checks enforced
- ✔ Image scanned & pushed
- ✔ GitOps triggered
- ✔ Deployment updated automatically

#### ❌ If not working

- Build fail → Maven issue
- SAST fail → code quality issue
- Trivy fail → vulnerable image
- Push fail → AWS auth issue
- No deploy → ArgoCD/GitOps issue

> 🏁 **Final Claim:** "The end-to-end DevSecOps pipeline has been validated, covering build, security scanning, containerization, registry push, GitOps deployment, and automated feedback mechanisms."

---

## Scripts

### AI RCA Script (Gemini) — FULL VALIDATION

#### ✅ What's Setup

- Python script for AI-based root cause analysis
- Takes Jenkins logs as input (stdin)
- Sends logs to Gemini API
- Returns root cause + fix suggestion
- Uses `GEMINI_API_KEY` (env variable)

#### 🔍 Step 1: Pre-check

```bash
python3 --version
echo $GEMINI_API_KEY
```

Expected:
- ✔ Python installed
- ✔ API key present

#### 🚀 Step 2: Manual test (REAL)

```bash
echo "BUILD FAILURE: Compilation error in App.java line 10" | python3 ai_rca.py
```

Expected:
- ✔ AI response with root cause + fix

#### 🚀 Step 3: Real Jenkins logs test

```bash
cat sample_logs.txt | python3 ai_rca.py
```

Expected:
- ✔ Meaningful analysis (not empty/error)

#### 🚀 Step 4: Pipeline integration test

Trigger failed Jenkins build

Check email/log output: AI RCA section should appear

Expected:
- ✔ AI analysis included in failure email

#### 🔍 Step 5: API failure test (IMPORTANT)

```bash
unset GEMINI_API_KEY
echo "error test" | python3 ai_rca.py
```

Expected:
- ❌ Script fails (shows API/auth error)

#### 🔍 Step 6: Large log handling

```bash
cat large_logs.txt | python3 ai_rca.py
```

Expected:
- ✔ Only last 2000 chars analyzed
- ✔ No crash

#### 🎯 Final Result

- ✔ Script reads logs correctly
- ✔ AI analysis returned
- ✔ Integrated with Jenkins failure flow
- ✔ Handles large logs safely

#### ❌ If not working

- Empty output → API/key issue
- Script crash → Python/env issue
- No AI in email → pipeline integration issue

> 🏁 **Final Claim:** "AI-based root cause analysis has been validated, enabling automated failure diagnosis and actionable insights integrated into the CI/CD pipeline."

---

## Dockerfile

### Dockerfile (Spring Boot + OTel) — FULL VALIDATION

#### ✅ What's Setup

- Multi-stage build (secure & optimized)
- Stage 1: Downloads OpenTelemetry Java Agent
- Stage 2: Builds Spring Boot JAR (Maven)
- Stage 3: Lightweight runtime (JRE 17)
- Runs as NON-ROOT user (security)
- OTel agent attached for observability
- JVM tuned (256m–512m)

#### 🔍 Step 1: Build image

```bash
docker build -t bankapp:test .
```

Expected:
- ✔ Build successful
- ✔ JAR created + agent downloaded

#### 🚀 Step 2: Run container

```bash
docker run -p 8080:8080 bankapp:test
```

Expected:
- ✔ App starts
- ✔ Logs visible

#### 🔍 Step 3: Health check

```bash
curl http://localhost:8080
```

Expected:
- ✔ Response from app

#### 🔐 Step 4: Non-root validation (CRITICAL)

```bash
docker exec -it <container-id> whoami
```

Expected:
- ✔ `appuser` (NOT root)

#### 🔍 Step 5: OTel agent check

```bash
docker logs <container-id> | grep -i opentelemetry
```

Expected:
- ✔ Agent initialized

#### 🚀 Step 6: Resource limits test

```bash
docker stats
```

Expected:
- ✔ Memory within ~512MB

#### 🚀 Step 7: Graceful shutdown test

```bash
docker stop <container-id>
```

Expected:
- ✔ Clean shutdown (no force kill)

#### 🔍 Step 8: Image size check

```bash
docker images | grep bankapp
```

Expected:
- ✔ Smaller than full JDK image (optimized)

#### 🎯 Final Result

- ✔ Image builds successfully
- ✔ App runs correctly
- ✔ Non-root security enforced
- ✔ OTel agent active
- ✔ Graceful shutdown works

#### ❌ If not working

- Build fail → Maven/dependency issue
- App crash → JAR issue
- Runs as root → security misconfig
- No OTel logs → agent not loaded

> 🏁 **Final Claim:** "The container image has been validated for secure, optimized build, non-root execution, observability integration, and reliable runtime behavior."

---

## Docker Compose.yaml

### Docker Compose (MySQL + App + Nginx) — FULL VALIDATION

#### ✅ What's Setup

- MySQL DB (persistent volume)
- Spring Boot app (connects to MySQL)
- Nginx (reverse proxy on port 80)
- Health checks for DB + App
- Internal network: `bankapp`
- Env-based config (DB creds)

#### 🔍 Step 1: Pre-check

```bash
docker compose config
```

Expected:
- ✔ No syntax errors
- ✔ Variables resolved (.env)

#### 🚀 Step 2: Start stack

```bash
docker compose up -d
docker ps
```

Expected:
- ✔ mysql, bankapp, nginx running

#### 🔍 Step 3: Health check

```bash
docker ps
```

Expected:
- ✔ mysql = healthy
- ✔ bankapp = healthy

#### 🚀 Step 4: App test (via Nginx)

```bash
curl http://localhost
```

Expected:
- ✔ App response (proxied via nginx)

#### 🔍 Step 5: DB connectivity test

```bash
docker exec -it bankapp sh
# Inside container: try DB connection (logs or app auto-connect)
docker logs bankapp
```

Expected:
- ✔ Connected to MySQL (no errors)

#### 🚀 Step 6: Persistence test

```bash
docker compose down
docker compose up -d
```

Expected:
- ✔ DB data persists (volume working)

#### 🚀 Step 7: Dependency test (IMPORTANT)

```bash
# Stop MySQL
docker stop mysql
# Expected: ❌ App becomes unhealthy / fails

# Start MySQL again
docker start mysql
# Expected: ✔ App recovers
```

#### 🔍 Step 8: Nginx config test

```bash
docker exec -it nginx nginx -t
```

Expected:
- ✔ config OK

#### 🔍 Step 9: Network test

```bash
docker network inspect bankapp
```

Expected:
- ✔ All 3 containers connected

#### 🎯 Final Result

- ✔ All services running
- ✔ App connected to DB
- ✔ Nginx routing working
- ✔ Health checks enforced
- ✔ Data persistence working

#### ❌ If not working

- App crash → DB/env issue
- DB not healthy → config/password issue
- No response → nginx config issue
- Data loss → volume issue

> 🏁 **Final Claim:** "The multi-container application stack has been validated for service orchestration, database connectivity, reverse proxy routing, health management, and data persistence."

---

## VPA

### VPA + Cert-Manager Stack — FULL VALIDATION

#### ✅ What's Setup

- VPA (Recommender, Updater, Admission Controller)
- Custom TLS via cert-manager (CA + webhook certs)
- Webhook secured (MutatingWebhookConfiguration)
- ArgoCD manages full stack (auto-heal + prune)
- Runs in `kube-system` (cluster-level autoscaling)

#### 🔍 Step 1: ArgoCD app check

```bash
kubectl get app vpa-stack -n argocd
```

Expected:
- ✔ STATUS = Synced, Healthy

#### 🔍 Step 2: Cert-manager check

```bash
kubectl get pods -n cert-manager
kubectl get certificate -n kube-system
```

Expected:
- ✔ All pods Running
- ✔ `vpa-ca` + `vpa-webhook-tls` READY=True

#### 🔍 Step 3: TLS Secret check

```bash
kubectl get secret vpa-tls-certs -n kube-system
```

Expected:
- ✔ Secret exists (tls.crt, tls.key)

#### 🔍 Step 4: Webhook check

```bash
kubectl get mutatingwebhookconfiguration vpa-webhook-config -o yaml
```

Expected:
- ✔ caBundle populated (NOT empty)

#### 🔍 Step 5: VPA components check

```bash
kubectl get pods -n kube-system | grep vpa
```

Expected:
- ✔ vpa-recommender Running
- ✔ vpa-updater Running
- ✔ vpa-admission-controller Running

#### 🚀 Step 6: Create test app (IMPORTANT)

```bash
kubectl create deploy vpa-test --image=nginx -n default

# Add VPA:
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: vpa-test
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: vpa-test
  updatePolicy:
    updateMode: "Auto"
EOF
```

#### 🔍 Step 7: Recommendation check

```bash
kubectl describe vpa vpa-test
```

Expected:
- ✔ CPU/Memory recommendations visible

#### 🚀 Step 8: Auto scaling test (REAL)

```bash
# Generate load
kubectl run load --image=busybox -- /bin/sh -c "while true; do wget -q -O- http://vpa-test; done"

# Watch pods
kubectl get pods -w
```

Expected:
- ✔ Pod restarted with new resources (VPA applied)

#### 🔍 Step 9: Admission webhook test

```bash
# Create pod WITHOUT resources
kubectl run test-no-limits --image=nginx
```

Expected:
- ✔ Pod still created (failurePolicy=Ignore)
- ✔ But webhook is hit (check logs)

```bash
kubectl logs -n kube-system deploy/vpa-admission-controller
```

#### 🔍 Step 10: CA injection test

```bash
kubectl get mutatingwebhookconfiguration vpa-webhook-config \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}'
```

Expected:
- ✔ Non-empty (cert-manager injected)

#### 🎯 Final Result

- ✔ VPA components running
- ✔ TLS secured via cert-manager
- ✔ Webhook working (CA injected)
- ✔ Recommendations generated
- ✔ Pods auto-resized

#### ❌ If not working

- No recommendations → metrics-server missing
- TLS empty → cert-manager issue
- Pod not restarting → updateMode issue
- Webhook fail → CA bundle missing

> 🏁 **Final Claim:** "Vertical Pod Autoscaler has been fully validated with secure webhook communication, dynamic resource recommendations, and automated pod resizing functioning as per configuration."

---

## Monitoring

### Prometheus

#### Prometheus + Grafana + Alerts — FULL VALIDATION

##### ✅ What's Setup

- kube-prometheus-stack via ArgoCD
- Prometheus (15d retention + 20Gi storage)
- Grafana (persistent 10Gi)
- Alertmanager (5Gi storage)
- Custom PrometheusRule (banking alerts)
- Auto-discovery via label: `release=kube-prometheus-stack`

##### 🔍 Step 1: ArgoCD check

```bash
kubectl get app kube-prometheus-stack -n argocd
```

Expected:
- ✔ Synced, Healthy

##### 🔍 Step 2: Pods check

```bash
kubectl get pods -n monitoring
```

Expected:
- ✔ prometheus-* Running
- ✔ grafana-* Running
- ✔ alertmanager-* Running

##### 🔍 Step 3: Storage check

```bash
kubectl get pvc -n monitoring
```

Expected:
- ✔ Prometheus PVC (20Gi)
- ✔ Grafana PVC (10Gi)
- ✔ Alertmanager PVC (5Gi)

##### 🚀 Step 4: Access UI

```bash
# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090

# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000

# Open:
# http://localhost:9090
# http://localhost:3000
```

Expected:
- ✔ UI accessible

##### 🔍 Step 5: Metrics check (CRITICAL)

In Prometheus UI: query `up`

Expected:
- ✔ Targets showing (not 0)

##### 🔍 Step 6: Rule loaded check

```bash
kubectl get prometheusrule -n monitoring
```

Expected:
- ✔ `banking-app-alerts` present

In Prometheus UI → Status → Rules

Expected:
- ✔ All alert rules visible

##### 🚀 Step 7: ALERT TEST (REAL)

**❌ Test 1: ServiceDown**

```bash
kubectl scale deploy <banking-app> --replicas=0 -n banking-prod
```

Where to see: Prometheus UI → Alerts tab OR `kubectl get alerts -A`

Expected:
- ✔ ServiceDown = FIRING

**❌ Test 2: HighErrorRate**

Force 500 errors (break app / wrong endpoint)

Where to see: Prometheus UI → Alerts

Expected:
- ✔ HighErrorRate firing

**❌ Test 3: HighCPU**

```bash
kubectl run stress --image=busybox -- /bin/sh -c "while true; do :; done"
```

Where to see: Prometheus → Alerts

Expected:
- ✔ HighCPUUsage firing

**❌ Test 4: PodCrashLoop**

```bash
kubectl run crash --image=busybox -- /bin/sh -c "exit 1"
```

Expected:
- ✔ PodCrashLooping alert

**❌ Test 5: NodeNotReady (optional)**

Stop node (or simulate)

Expected:
- ✔ NodeNotReady firing

##### 🚀 Step 8: Alertmanager check

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093
# Open: http://localhost:9093
```

Expected:
- ✔ Alerts grouped + visible

##### 🔍 Step 9: Grafana dashboard check

```bash
# Open Grafana → Explore
# Query: rate(http_server_requests_seconds_count[5m])
```

Expected:
- ✔ Graph visible

##### 🎯 Final Result

- ✔ Monitoring stack running
- ✔ Metrics collected
- ✔ Rules loaded
- ✔ Alerts firing correctly
- ✔ Grafana dashboards working

##### ❌ If not working

- No metrics → app not exposing metrics
- No alerts → label mismatch (`release=...`)
- No data → Prometheus target issue
- No UI → service/port-forward issue

> 🏁 **Final Claim:** "Monitoring and alerting stack has been fully validated with real-time metrics collection, persistent storage, alert rule execution, and end-to-end alert triggering confirmed."

---

#### Prometheus Alerts — End to End Validation

##### ✅ STEP 1: Verify Prometheus is running

```bash
kubectl get pods -n monitoring
```

Expected:
- ✔ prometheus pod Running
- ✔ alertmanager Running
- ✔ grafana Running

##### ✅ STEP 2: Verify rules are loaded

```bash
kubectl get prometheusrule -n monitoring
```

Expected:
- ✔ `banking-app-alerts` present

Check inside Prometheus UI: `http://localhost:9090` → Status → Rules

Expected:
- ✔ All rules visible (ServiceDown, HighErrorRate, etc.)

##### 🚀 STEP 3: Open Prometheus UI

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090
# Open: http://localhost:9090
# Go to: Status → Targets
```

Expected:
- ✔ ALL targets = UP

##### 🚀 STEP 4: Open Alert UI

In Prometheus UI → Alerts tab

Expected:
- ✔ Alerts list visible (initially EMPTY or inactive)

##### ❌ STEP 5: TEST ALERT 1 — ServiceDown (MOST IMPORTANT)

```bash
kubectl scale deploy banking-platform --replicas=0 -n banking-prod
# Wait 1–2 minutes
# CHECK: Prometheus UI → Alerts
```

Expected:
- ✔ ServiceDown = FIRING
- ✔ Severity = critical

##### ❌ STEP 6: TEST ALERT 2 — High Error Rate

```bash
# FORCE ERROR (choose one):
# Option A: break endpoint
# Option B: stop backend service dependency

# Generate traffic:
while true; do curl http://api-url; done
# CHECK: Prometheus → Alerts
```

Expected:
- ✔ HighErrorRate = FIRING

##### ❌ STEP 7: TEST ALERT 3 — High CPU

```bash
kubectl run cpu-stress --image=busybox -- /bin/sh -c "while true; do :; done"
# Wait 2–5 min
# CHECK: Prometheus → Alerts
```

Expected:
- ✔ HighCPUUsage = FIRING

##### ❌ STEP 8: TEST ALERT 4 — Pod CrashLoop

```bash
kubectl run crash-test --image=busybox -- /bin/sh -c "exit 1"
# CHECK: kubectl get pods
```

Expected:
- ✔ PodCrashLooping = FIRING

##### ❌ STEP 9: TEST ALERT 5 — Memory Pressure (optional)

```bash
kubectl run mem --image=busybox -- /bin/sh -c "dd if=/dev/zero of=/dev/null"
# CHECK: Prometheus Alerts
```

Expected:
- ✔ HighMemoryUsage = FIRING

##### 📩 STEP 10: VERIFY ALERT DELIVERY (CRITICAL PROOF)

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093
# Open: http://localhost:9093
```

Expected:
- ✔ Alerts grouped
- ✔ Alerts visible in UI

##### 🔁 STEP 11: FIX + RECOVERY TEST

```bash
kubectl scale deploy banking-platform --replicas=2 -n banking-prod
# WAIT 2–3 minutes
```

Expected:
- ✔ ServiceDown = RESOLVED automatically
- ✔ Alert disappears

##### 🎯 FINAL CLIENT PROOF CHECKLIST

- ✔ Prometheus running
- ✔ Rules loaded
- ✔ Alert UI visible
- ✔ Alerts FIRE on real failures
- ✔ Alerts RESOLVE automatically
- ✔ Alertmanager receiving alerts

> 🏁 **Final Statement:** "All alerting rules are not only configured but also validated end-to-end using real failure injection. Alerts are firing, visible in Prometheus and Alertmanager, and automatically resolving when system recovers."

---

### Grafana

#### Grafana Dashboard + Ingress — FULL VALIDATION

##### ✅ What's Setup

- Grafana dashboard auto-import via ConfigMap
- Label: `grafana_dashboard=1` (auto-discovery)
- Dashboard: Spring Boot Micrometer metrics
- Panels:
  - ✔ JVM memory usage
  - ✔ HTTP request rate
- Grafana folder: "Banking Operations"
- Ingress:
  - ✔ AWS ALB (internet-facing)
  - ✔ HTTPS + HTTP redirect
  - ✔ Routes `grafana.rohandevops.co.in` → Grafana service
  - ✔ Sticky sessions enabled

##### 🔍 STEP 1: Check Grafana is running

```bash
kubectl get pods -n monitoring | grep grafana
```

Expected:
- ✔ grafana pod Running

##### 🔍 STEP 2: Check dashboard ConfigMap

```bash
kubectl get cm springboot-banking-dashboard -n monitoring
kubectl describe cm springboot-banking-dashboard -n monitoring
```

Expected:
- ✔ `grafana_dashboard=1` label present

##### 🚀 STEP 3: Verify dashboard imported in Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000
# Open: http://localhost:3000
# Go to: Dashboards → Browse
```

Expected:
- ✔ "Banking Operations" folder exists
- ✔ "Banking Core - Performance" dashboard visible

##### 🔍 STEP 4: Validate metrics inside dashboard

Open dashboard panels:

**JVM Panel:** ✔ Graph showing JVM memory usage

**HTTP Panel:** ✔ Request rate graph visible (non-zero if traffic exists)

##### 🚀 STEP 5: Generate real metrics (IMPORTANT TEST)

```bash
kubectl run test-traffic --image=busybox -- /bin/sh -c "while true; do wget -q -O- http://banking-app; done"
# Wait 1–2 minutes, then refresh Grafana dashboard
```

Expected:
- ✔ JVM graph moves
- ✔ HTTP request rate increases

##### 🔍 STEP 6: Check ALB Ingress

```bash
kubectl get ingress -n monitoring
kubectl describe ingress grafana-ingress -n monitoring
```

Expected:
- ✔ `grafana-ingress` present
- ✔ AWS ALB hostname generated

##### 🌐 STEP 7: External access test

```
https://grafana.rohandevops.co.in
```

Expected:
- ✔ Grafana login page loads

##### 🔐 STEP 8: SSL + routing check

```bash
curl -I https://grafana.rohandevops.co.in
```

Expected:
- ✔ 200 / 302 response
- ✔ HTTPS working

##### 🔁 STEP 9: Session persistence test

1. Login to Grafana
2. Refresh page multiple times

Expected:
- ✔ Session does NOT break (sticky session working)

##### 🎯 FINAL RESULT

- ✔ Dashboard auto-provisioned
- ✔ Metrics visualized correctly
- ✔ Grafana accessible via ALB
- ✔ Domain routing working
- ✔ SSL enabled
- ✔ Sticky sessions working

##### ❌ If not working

- No dashboard → label missing (`grafana_dashboard=1`)
- No panels → JSON error
- No traffic graph → app metrics missing
- No ALB → ingress controller issue
- Domain not working → DNS issue

> 🏁 **Final Client Statement:** "Grafana dashboards are fully automated via Kubernetes ConfigMap, verified for metric visualization, and securely exposed via AWS ALB ingress with production-grade routing and SSL."

---

### Tempo

#### Tempo + Grafana Observability Stack — FULL VALIDATION

##### ✅ What's Setup

- Tempo deployed via ArgoCD (Grafana Helm chart)
- Stores distributed traces (OpenTelemetry)
- Grafana datasource auto-config via ConfigMap
- IRSA enabled for AWS access (`tempo-sa` role)
- Grafana ↔ Tempo integration enabled
  - ✔ Trace ingestion (App → Tempo)
  - ✔ Trace storage (local / S3-ready)
  - ✔ Trace visualization (Grafana Explore)

##### 🔍 STEP 1: Check Tempo is running

```bash
kubectl get pods -n monitoring | grep tempo
```

Expected:
- ✔ tempo pods Running
- ✔ 1/1 READY

##### 🔍 STEP 2: Check Tempo service

```bash
kubectl get svc -n monitoring | grep tempo
```

Expected:
- ✔ tempo service exists
- ✔ port 3200 exposed

##### 🔍 STEP 3: Check Grafana datasource ConfigMap

```bash
kubectl get cm tempo-datasource -n monitoring
kubectl describe cm tempo-datasource -n monitoring
```

Expected:
- ✔ `grafana_datasource: "1"`
- ✔ URL correct: `http://tempo-stack.monitoring.svc.cluster.local:3200`

##### 🚀 STEP 4: Verify datasource in Grafana UI

```
Open Grafana: http://grafana.rohandevops.co.in
Go: Connections → Data Sources → Tempo
```

Expected:
- ✔ Data source is WORKING
- ✔ Save & Test SUCCESS

##### 🚀 STEP 5: Generate real application traces

```bash
curl http://<app-url>/api/test
curl http://<app-url>/login
curl http://<app-url>/api/transfer
# WAIT 1–2 minutes
```

##### 🔍 STEP 6: Check traces in Grafana

```
Grafana → Explore → Tempo
Query: { service.name = "banking-app" }
```

Expected:
- ✔ Traces visible
- ✔ Span timeline shown
- ✔ Request duration visible

##### 🔍 STEP 7: Validate trace details

Open any trace:
- ✔ Service graph visible
- ✔ Span breakdown present
- ✔ Latency shown
- ✔ Parent-child trace relationship

##### 🔐 STEP 8: Validate IRSA (AWS access)

```bash
kubectl describe sa tempo-sa -n monitoring
```

Expected:
- ✔ IAM role attached: `arn:aws:iam::959589242185:role/tempo-s3-role`

##### 🔐 STEP 9: Validate pod IAM access

```bash
kubectl exec -it <tempo-pod> -n monitoring -- sh
env | grep AWS
```

Expected:
- ✔ No static AWS keys
- ✔ IAM role assumed via IRSA

##### 📊 STEP 10: End-to-end validation

CHECK FLOW: Application → OpenTelemetry → Tempo → Grafana

Expected:
- ✔ Trace generated
- ✔ Trace stored in Tempo
- ✔ Trace visible in Grafana

##### 🎯 FINAL RESULT

- ✔ Tempo deployed successfully via ArgoCD
- ✔ Grafana datasource auto-configured
- ✔ Application traces flowing end-to-end
- ✔ Grafana Explore showing live traces
- ✔ IRSA secure authentication working
- ✔ Observability stack fully functional

##### ❌ IF NOT WORKING

- No traces → app not instrumented (OTel missing)
- Datasource fail → wrong Tempo service URL
- No pods → deployment issue
- No IAM role → IRSA misconfigured
- No traces in Grafana → pipeline broken between app → Tempo

> 🏁 **Final Client Statement:** "Tempo observability stack is fully deployed and validated. End-to-end distributed tracing is working from application instrumentation through Tempo ingestion and storage, and finally visualized in Grafana with secure AWS IRSA-based access."

---

### Kiali

#### Kiali (Service Mesh Observability) — FULL VALIDATION

##### ✅ What's Setup

- Kiali deployed via ArgoCD (Helm chart)
- Runs in `istio-system` namespace
- Access mode: **anonymous login (no auth required)**
- Integrations enabled:
  - ✔ Prometheus → metrics
  - ✔ Grafana → dashboards
  - ✔ Tempo → distributed tracing (Istio + app traces)

##### 🔗 Service Mesh Flow

```
Istio Services
      ↓
Prometheus (metrics)
      ↓
Grafana (visualization)
      ↓
Tempo (traces)
      ↓
Kiali (service mesh UI)
```

##### 🔍 STEP 1: Check Kiali deployment

```bash
kubectl get pods -n istio-system | grep kiali
```

Expected:
- ✔ kiali-server pod Running
- ✔ 1/1 READY

##### 🔍 STEP 2: Check Kiali service

```bash
kubectl get svc -n istio-system | grep kiali
```

Expected:
- ✔ kiali service exists
- ✔ port 20001 (default UI port)

##### 🚀 STEP 3: Access Kiali UI

```bash
kubectl port-forward svc/kiali -n istio-system 20001:20001
# Open: http://localhost:20001
```

Expected:
- ✔ Kiali dashboard opens
- ✔ No login required (anonymous mode)

##### 🔍 STEP 4: Verify Prometheus connection

Inside Kiali UI: Configuration → External Services → Prometheus

OR CLI check:

```bash
kubectl get svc -n monitoring | grep prometheus
```

Expected:
- ✔ Prometheus reachable at: `http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090`

##### 🔍 STEP 5: Verify Grafana integration

In Kiali UI: Go → Grafana link

OR check:

```bash
kubectl get svc -n monitoring | grep grafana
```

Expected:
- ✔ Grafana URL configured
- ✔ Dashboard links visible in Kiali

##### 🔍 STEP 6: Verify tracing (Tempo integration)

```bash
kubectl describe cm -n istio-system kiali
```

OR UI: Go → Distributed Tracing

Expected:
- ✔ Tracing enabled
- ✔ Tempo endpoint configured: `http://tempo-stack.monitoring.svc.cluster.local:3100`

##### 🚀 STEP 7: Generate real traffic

```bash
curl http://<app-url>/api/test
curl http://<app-url>/login
curl http://<app-url>/api/transfer
# Wait 1–2 minutes
```

##### 🔍 STEP 8: Validate service graph in Kiali

```
Open Kiali UI → Graph
Select namespace: banking-prod
```

Expected:
- ✔ Service nodes visible
- ✔ Traffic lines between services
- ✔ Request flow visualization

##### 🔍 STEP 9: Validate tracing inside Kiali

```
Kiali → Traces
```

Expected:
- ✔ Distributed traces visible
- ✔ Request flow across services
- ✔ Latency breakdown shown

##### 🔐 STEP 10: Validate external service connectivity

```bash
kubectl exec -it <any-pod> -n istio-system -- curl <service-url>
```

Expected:
- ✔ Prometheus reachable
- ✔ Grafana reachable
- ✔ Tempo reachable

##### 🎯 FINAL RESULT

- ✔ Kiali deployed successfully via ArgoCD
- ✔ Service mesh visibility working
- ✔ Istio traffic graph generated
- ✔ Prometheus metrics integrated
- ✔ Grafana dashboards linked
- ✔ Tempo tracing enabled
- ✔ End-to-end observability achieved

##### ❌ IF NOT WORKING

- No graph → Istio sidecar injection missing
- No metrics → Prometheus URL wrong
- No traces → Tempo not receiving data
- UI not opening → service or port issue
- Empty graph → no traffic generated

> 🏁 **Final Client Statement:** "Kiali service mesh observability is fully deployed and validated. It provides real-time visibility of service-to-service communication with integrated metrics, logs, and distributed tracing across Prometheus, Grafana, and Tempo."

---

### OTEL

#### OpenTelemetry Collector (OTEL) — FULL VALIDATION

##### ✅ What's Setup

- OpenTelemetry Collector deployed via ArgoCD
- Runs as **Deployment** in `monitoring` namespace
- Receives telemetry data from applications
  - ✔ Traces → Tempo
  - ✔ Logs → Loki
  - ✔ Protocols → OTLP (gRPC + HTTP)

##### 🔗 Data Flow

```
Spring Boot App (OTel SDK)
        ↓
OTEL Collector (Receiver)
    ↓           ↓
  Tempo        Loki
(traces)      (logs)
    ↓           ↓
    Grafana (visualization)
```

##### 🔍 STEP 1: Check OTEL Collector pods

```bash
kubectl get pods -n monitoring | grep otel
```

Expected:
- ✔ otel-collector pod Running
- ✔ 1/1 READY

##### 🔍 STEP 2: Check OTEL service

```bash
kubectl get svc -n monitoring | grep otel
```

Expected:
- ✔ otel collector service exists
- ✔ ports: 4317 (gRPC), 4318 (HTTP)

##### 🔍 STEP 3: Validate config inside collector

```bash
kubectl get cm -n monitoring | grep otel
kubectl describe cm otel-collector -n monitoring
```

Check:
- ✔ receivers: otlp enabled
- ✔ exporters:
  - tempo → `tempo-stack.monitoring.svc.cluster.local:4317`
  - loki → `loki-stack.monitoring.svc.cluster.local:3100`

##### 🚀 STEP 4: Generate application telemetry

```bash
curl http://<app-url>/api/test
curl http://<app-url>/login
curl http://<app-url>/api/transfer
# Wait 1–2 minutes
```

##### 🔍 STEP 5: Verify traces in Tempo

```
Grafana → Explore → Tempo
Query: { service.name = "banking-app" }
```

Expected:
- ✔ Traces visible
- ✔ Spans generated
- ✔ Latency shown

##### 🔍 STEP 6: Verify logs in Loki

```
Grafana → Explore → Loki
Query: { app="banking-app" }
```

Expected:
- ✔ Logs appearing
- ✔ Correlated with trace IDs

##### 🔗 STEP 7: Verify trace-log correlation

Open any trace in Tempo:
- ✔ "Logs for this span"
- ✔ trace_id linking logs
- ✔ request flow visibility

##### 🔍 STEP 8: Check OTEL collector health

```bash
kubectl logs -n monitoring deploy/otel-collector
```

Expected:
- ✔ No errors
- ✔ "Exporter succeeded"
- ✔ "receiving data" logs

##### 🔐 STEP 9: Validate security context

```bash
kubectl describe pod -n monitoring <otel-pod>
```

Check:
- ✔ runAsNonRoot = true
- ✔ runAsUser = 1000
- ✔ fsGroup = 1000

##### 🎯 FINAL RESULT

- ✔ OTEL collector deployed successfully
- ✔ Traces received from application
- ✔ Logs collected and pushed to Loki
- ✔ Traces exported to Tempo
- ✔ Full observability pipeline active

##### ❌ IF NOT WORKING

- No traces → app not sending OTLP data
- No logs → Loki exporter misconfigured
- No data → wrong service endpoints
- Collector crash → config syntax issue
- Empty Grafana → pipeline broken

> 🏁 **Final Client Statement:** "OpenTelemetry Collector is fully deployed and validated. It successfully receives telemetry from applications and exports traces to Tempo and logs to Loki, enabling complete distributed observability across the platform."

---

### LOKI

#### Loki Stack (Log Aggregation) — FULL VALIDATION

##### ✅ What's Setup

- Loki deployed via ArgoCD (Grafana Helm chart)
- Centralized log aggregation system
- Logs collected via Promtail
- Stored in S3 (production backend)
  - ✔ Promtail → collects logs from pods
  - ✔ Loki → processes + stores logs
  - ✔ S3 → long-term storage backend
  - ✔ Grafana → log visualization
  - ✔ IRSA → secure AWS access for Loki

##### 🔗 Log Pipeline Flow

```
Application Logs
        ↓
Promtail (node/pod log collector)
        ↓
Loki (log ingestion + indexing)
        ↓
S3 (persistent storage)
        ↓
Grafana (query + visualization)
```

##### 🔍 STEP 1: Check Loki pods

```bash
kubectl get pods -n monitoring | grep loki
```

Expected:
- ✔ loki pods Running
- ✔ 1/1 READY

##### 🔍 STEP 2: Check Promtail (log agent)

```bash
kubectl get pods -n monitoring | grep promtail
```

Expected:
- ✔ promtail running on nodes
- ✔ DaemonSet deployed

##### 🔍 STEP 3: Check Loki service

```bash
kubectl get svc -n monitoring | grep loki
```

Expected:
- ✔ loki-stack service exists
- ✔ port 3100 exposed

##### 🔍 STEP 4: Validate Loki datasource in Grafana

```bash
kubectl get cm loki-datasource -n monitoring
kubectl describe cm loki-datasource -n monitoring
```

Expected:
- ✔ `grafana_datasource: "1"`
- ✔ URL: `http://loki-stack.monitoring.svc.cluster.local:3100`

##### 🚀 STEP 5: Verify Grafana log access

```
Open Grafana: http://grafana.rohandevops.co.in
Go: Explore → Loki
Query: { namespace="banking-prod" }
```

Expected:
- ✔ Logs visible
- ✔ Real-time streaming logs working

##### 🚀 STEP 6: Generate application logs

```bash
curl http://<app-url>/api/test
curl http://<app-url>/login
curl http://<app-url>/api/transfer
# Wait 1–2 minutes
```

##### 🔍 STEP 7: Verify logs in Grafana

```
Grafana → Explore → Loki
Query: { app="banking-app" }
```

Expected:
- ✔ Logs appearing
- ✔ Timestamped entries visible
- ✔ Request logs available

##### 🔗 STEP 8: Validate trace-log correlation

Open Tempo trace → click span:
- ✔ "Logs for this span"
- ✔ trace_id correlation working
- ✔ request lifecycle visible

##### 🔍 STEP 9: Check Promtail ingestion

```bash
kubectl logs -n monitoring daemonset/promtail
```

Expected:
- ✔ log shipping active
- ✔ no errors
- ✔ "pushed batch" logs

##### 🔐 STEP 10: Validate IRSA (AWS S3 access)

```bash
kubectl describe sa loki-sa -n monitoring
```

Expected:
- ✔ IAM role attached: `arn:aws:iam::959589242185:role/loki-s3-role`

##### 🔐 STEP 11: Verify S3 backend (indirect check)

```bash
kubectl logs -n monitoring deploy/loki
```

Expected:
- ✔ no storage errors
- ✔ successful chunk uploads
- ✔ boltdb-shipper active

##### 🎯 FINAL RESULT

- ✔ Loki deployed successfully via ArgoCD
- ✔ Promtail collecting logs from all nodes
- ✔ Logs stored in S3 backend
- ✔ Grafana querying logs successfully
- ✔ Trace-log correlation working (Tempo + Loki)
- ✔ IRSA-based secure AWS access enabled

##### ❌ IF NOT WORKING

- No logs → promtail not running
- Empty Grafana logs → label mismatch
- Loki errors → S3 permission issue
- No ingestion → wrong loki URL
- Missing logs → app not writing stdout logs

> 🏁 **Final Client Statement:** "Loki logging stack is fully deployed and validated. It successfully collects logs from all Kubernetes workloads via Promtail, stores them in S3, and integrates with Grafana and Tempo for unified observability with logs and distributed tracing correlation."

---

### ai_alerts.py

#### Prometheus Rule (Log Anomaly Alerts) — FULL VALIDATION

##### ✅ What's Setup

- PrometheusRule deployed via Prometheus Operator
- Namespace: `monitoring`
- Used for **log/anomaly-based alerting**
- Detects abnormal behavior in banking workloads
  - ✔ Monitors pod restarts
  - ✔ Detects anomaly spikes
  - ✔ Sends alerts via Alertmanager

##### 🔗 Alert Flow

```
Kubernetes Metrics (kube-state-metrics)
        ↓
Prometheus (rule evaluation)
        ↓
Alertmanager (notification engine)
        ↓
Slack / Email / Ops system (if configured)
```

##### 🔍 STEP 1: Check rule is loaded in Prometheus

```bash
kubectl get prometheusrule -n monitoring
```

Expected:
- ✔ `log-anomaly-alerts` present

##### 🔍 STEP 2: Verify rule in Prometheus UI

```bash
kubectl port-forward svc/kube-prometheus-stack-kube-prom-prometheus -n monitoring 9090:9090
# Open: http://localhost:9090
# Go: Status → Rules
```

Expected:
- ✔ `ai-log-alerts` group visible
- ✔ `HighLogAnomalyScore` rule listed

##### 🔍 STEP 3: Validate rule expression manually

Run in Prometheus "Graph" tab:

```promql
increase(kube_pod_container_status_restarts_total{namespace="banking-prod"}[5m]) > 3
```

Expected:
- ✔ returns 0 or 1
- ✔ no query errors

##### 🚀 STEP 4: Trigger anomaly test (FORCED)

```bash
kubectl rollout restart deployment <app-name> -n banking-prod
# OR delete repeatedly:
kubectl delete pod <pod-name> -n banking-prod
# WAIT 2–5 minutes
```

##### 🔍 STEP 5: Check alert firing state

```bash
kubectl get alerts -n monitoring
# OR in Prometheus UI: Alerts tab
```

Expected:
- ✔ HighLogAnomalyScore → FIRING state (if threshold hit)

##### 🔍 STEP 6: Check Alertmanager

```bash
kubectl get pods -n monitoring | grep alertmanager

kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093
# Open: http://localhost:9093
```

Expected:
- ✔ Alert visible
- ✔ Status: FIRING or RESOLVED

##### 🔍 STEP 7: Verify alert annotations

In alert details:
- ✔ summary: "Anomaly detected in banking pods"

##### 🔍 STEP 8: Validate metric source

```bash
kubectl get pods -n banking-prod
# Metric used: kube_pod_container_status_restarts_total
```

Expected:
- ✔ kube-state-metrics is running
- ✔ restart metric is available

##### 🎯 FINAL RESULT

- ✔ PrometheusRule deployed successfully
- ✔ Anomaly detection rule active
- ✔ Pod restart monitoring working
- ✔ Alert pipeline integrated with Alertmanager
- ✔ Rule evaluation confirmed in Prometheus

##### ❌ IF NOT WORKING

- No alert → kube-state-metrics missing
- Rule not visible → Prometheus not scraping CRDs
- No firing → threshold not reached
- Wrong namespace → selector mismatch
- No metrics → monitoring stack issue

> 🏁 **Final Client Statement:** "Prometheus anomaly detection rule is fully deployed and validated. It actively monitors pod restart behavior in banking workloads and triggers alerts via Prometheus Alertmanager when abnormal activity is detected."

---

## Banking App

### 🚨 Prometheus Alerts — Full Validation Guide

#### ✅ What's Setup

- kube-prometheus-stack installed via Helm
- PrometheusRule CRDs deployed (custom alerts)
- Grafana connected to Prometheus
- Metrics sources:
  - ✔ Spring Boot (Micrometer)
  - ✔ Kubernetes metrics (node/pod/container)
  - ✔ MySQL / Infra / Istio / Velero signals
- Alert Categories:
  - ✔ App health (ServiceDown, HighErrorRate, Latency)
  - ✔ Infra (CPU, Memory, Disk, OOMKilled)
  - ✔ Kubernetes health (PodCrashLooping, NodeNotReady)
  - ✔ Database alerts
  - ✔ Security alerts (AuthFailures)
  - ✔ Traffic anomalies
  - ✔ Backup failures (Velero)

#### 🔍 STEP 1: Check Prometheus is running

```bash
kubectl get pods -n monitoring | grep prometheus
```

Expected:
- ✔ `prometheus-kube-prometheus-stack` running

#### 🔍 STEP 2: Check PrometheusRule is applied

```bash
kubectl get prometheusrule -n monitoring
```

Expected:
- ✔ `banking-app-alerts`
- ✔ `log-anomaly-alerts`

#### 🔍 STEP 3: Verify Prometheus loaded rules

```bash
kubectl port-forward svc/kube-prometheus-stack-kube-prom-prometheus -n monitoring 9090
# Open: http://localhost:9090/rules
```

Expected:
- ✔ service-availability
- ✔ application-errors
- ✔ latency
- ✔ resource-usage
- ✔ kubernetes-health
- ✔ database
- ✔ security
- ✔ backup

#### 🔍 STEP 4: Check alert state in Prometheus

```
Open: http://localhost:9090/alerts
```

Expected:
- ✔ Alerts listed (Inactive / Pending / Firing)

#### 🚀 STEP 5: Trigger ALERT (TEST METHOD)

**Option A — Crash test pod**

```bash
kubectl run crash-test --image=busybox -n banking-prod -- /bin/sh -c "exit 1"
```

**Option B — Force restarts**

```bash
kubectl delete pod -l app=banking-api -n banking-prod
```

Expected:
- ✔ PodCrashLooping alert → FIRING

#### 🔥 STEP 6: Generate High CPU Alert

```bash
kubectl run cpu-stress --image=busybox -n banking-prod -- /bin/sh -c "while true; do :; done"
```

Expected:
- ✔ HighCPUUsage alert → FIRING

#### 💥 STEP 7: Generate HTTP traffic alert

```bash
kubectl run traffic-test --image=busybox -n banking-prod -- /bin/sh -c "while true; do wget -q -O- http://banking-api; done"
```

Expected:
- ✔ HTTP metrics increase
- ✔ latency / traffic alerts trigger (if threshold crossed)

#### 🧠 STEP 8: Check Grafana Alert Panels

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000
# Open: http://localhost:3000
# Go to: Alerting → Alert Rules
```

Expected:
- ✔ All Prometheus alerts visible
- ✔ State: Normal / Pending / Firing

#### 📩 STEP 9: Check Alertmanager (IMPORTANT)

```bash
kubectl get pods -n monitoring | grep alertmanager

kubectl port-forward svc/kube-prometheus-stack-kube-prom-alertmanager -n monitoring 9093
# Open: http://localhost:9093
```

Expected:
- ✔ Alerts grouped
- ✔ Status: firing / resolved

#### 📬 STEP 10: Verify Email Alerts (if configured)

Trigger any alert again, then check email inbox.

Expected:
- ✔ Subject: CRITICAL / WARNING alert
- ✔ Prometheus alert payload included

#### 🔁 STEP 11: Verify auto-recovery (self-heal)

After fixing issue:

```bash
kubectl delete pod crash-test -n banking-prod
```

Expected:
- ✔ Alert → RESOLVED automatically

#### 📊 STEP 12: Validate key metrics exist

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090
```

Check queries:

```promql
# CPU
rate(container_cpu_usage_seconds_total[5m])

# Memory
container_memory_working_set_bytes

# Restarts
kube_pod_container_status_restarts_total
```

Expected:
- ✔ Non-zero results

#### 🎯 FINAL RESULT

- ✔ Alerts loaded from GitOps
- ✔ PrometheusRule active
- ✔ Alerts firing on real load
- ✔ Alertmanager receiving alerts
- ✔ Grafana visualizing alerts
- ✔ Auto-healing verified

#### ❌ IF SOMETHING FAILS

- No alerts → PrometheusRule not loaded
- No firing → thresholds too high
- No metrics → ServiceMonitor missing
- No alert UI → Alertmanager not connected
- No logs → Prometheus scraping issue