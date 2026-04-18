# Production Deployment Troubleshooting Guide
## Banking Platform on AWS EKS — Real Issues & Fixes

> Documented by a senior DevOps engineer during a fresh production deployment.
> Every error listed here was encountered, debugged, and resolved in sequence.

---

## Table of Contents

- [Environment](#environment)
- [Layer 1 — Terraform Infrastructure](#layer-1--terraform-infrastructure)
- [Layer 2 — EKS Add-ons](#layer-2--eks-add-ons)
- [Layer 3 — Docker Image & ECR](#layer-3--docker-image--ecr)
- [Layer 4 — Application Deployment via Helm](#layer-4--application-deployment-via-helm)
- [Key Lessons Learned](#key-lessons-learned)

---

## Environment

| Component | Version |
|-----------|---------|
| Kubernetes | v1.31 (EKS) |
| Terraform | 1.9.0 |
| Helm | 3.x |
| Argo Rollouts | latest |
| AWS Region | us-east-1 |
| App | Spring Boot 3.3 (Java 17) |

---

## Layer 1 — Terraform Infrastructure

### Issue 1.1 — KMS Key Must Exist Before Bootstrap

**Error:**
```
Error: error creating S3 Bucket server side encryption configuration
KMS key ARN not found
```

**Root Cause:**
The S3 bootstrap module requires a KMS key ARN via `terraform.tfvars` but the key didn't exist yet.

**Fix:**
Create the KMS key manually before running bootstrap:
```bash
aws kms create-key \
  --description "KMS key for Banking Platform" \
  --region us-east-1 \
  --tags TagKey=Project,TagValue=Banking-System
```
Copy the `KeyArn` from the output and update `terraform/bootstrap/s3-backend/terraform.tfvars`:
```hcl
kms_key_arn = "arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID"
```

---

### Issue 1.2 — Route53 Hosted Zone Must Exist Before ACM Validation

**Error:**
```
Error: error creating Route53 Record: InvalidChangeBatch
No hosted zone found for domain rohandevops.co.in
```

**Root Cause:**
The ACM module tries to create DNS validation records in Route53, but the hosted zone didn't exist.

**Fix:**
Create the hosted zone first, update nameservers at domain registrar, then run Terraform:
```bash
aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s)
```
Copy the 4 `NameServers` from the output and update them at your domain registrar (GoDaddy, Namecheap, etc.). Wait 5–30 minutes for propagation before running Terraform.

---

### Issue 1.3 — RDS Secrets Must Exist in Secrets Manager Before Terraform Apply

**Error:**
```
Error: error reading Secrets Manager Secret: ResourceNotFoundException
Secret banking-prod-db-secret not found
```

**Root Cause:**
The RDS module reads DB credentials from AWS Secrets Manager at plan/apply time. The secret must exist before running `terraform apply`.

**Fix:**
Create the secret before running Terraform:
```bash
aws secretsmanager create-secret \
  --name "banking-prod-db-secret" \
  --region us-east-1 \
  --secret-string '{"db_username":"bankappdb","db_password":"YourSecurePassword"}'
```

> **Important:** The `db_username` value you put here becomes the actual RDS master username. Choose it carefully — it cannot be changed after RDS creation without destroying and recreating the instance.

---

### Issue 1.4 — `db_name` Variable Used as Both Database Name and Master Username

**Root Cause:**
The Terraform `rds/main.tf` reads both `username` and the database name from the same Secrets Manager secret. The secret was created with `db_username: "bankappdb"` which is actually the database name, not a separate admin user.

**Impact:**
The RDS master username ended up being `bankappdb` (same as the database name). While functional, this is not ideal for security.

**Fix (for future deployments):**
Use separate values:
```json
{
  "db_username": "bankadmin",
  "db_password": "SecurePassword",
  "db_name": "bankappdb"
}
```
Update `rds/variables.tf` and `rds/main.tf` to read `db_username` and `db_name` as separate fields.

---

## Layer 2 — EKS Add-ons

### Issue 2.1 — AWS Load Balancer Controller Not Installing

**Symptom:**
```bash
kubectl get pods -n kube-system | grep aws-load-balancer
# Returns empty — no pods found
```

**Root Cause:**
The IAM service account (`aws-load-balancer-controller`) was not created before running the Helm install. The controller silently fails to start without the correct IRSA annotation.

**Fix:**
Run in this exact order:

```bash
# Step 1: Create IAM policy
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Step 2: Create IRSA service account
eksctl create iamserviceaccount \
  --cluster=bankapp-prod-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region us-east-1

# Step 3: Install controller (serviceAccount.create=false is critical)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=bankapp-prod-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

**Verification:**
```bash
kubectl get pods -n kube-system | grep aws-load-balancer
# Must show 2 pods, both 1/1 Running
```

---

### Issue 2.2 — External Secrets Main Controller Pod Missing

**Symptom:**
```
NAME                                                READY   STATUS
external-secrets-cert-controller-xxx                1/1     Running
external-secrets-webhook-xxx                        1/1     Running
# Main external-secrets pod is MISSING
```

**Root Cause:**
The IRSA service account for External Secrets was not created, so the main controller pod failed to start and wasn't visible in the pod list.

**Fix:**
```bash
eksctl create iamserviceaccount \
  --cluster=bankapp-prod-eks \
  --namespace=external-secrets \
  --name=external-secrets \
  --attach-policy-arn=arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve \
  --override-existing-serviceaccounts \
  --region us-east-1

kubectl rollout restart deployment external-secrets -n external-secrets
```

**Verification:**
```bash
kubectl get pods -n external-secrets
# Must show 3 pods: main controller + cert-controller + webhook, all Running
```

---

### Issue 2.3 — ClusterSecretStore Showing Empty STATUS and READY

**Symptom:**
```
NAME                 AGE   STATUS   CAPABILITIES   READY
aws-secretsmanager   24s
# STATUS and READY columns are completely empty
```

**Root Cause:**
The External Secrets main controller (Issue 2.2) was not running, so nothing could validate and update the ClusterSecretStore status.

**Fix:**
Fix Issue 2.2 first (get all 3 External Secrets pods running), then delete and recreate the ClusterSecretStore:
```bash
kubectl delete clustersecretstore aws-secretsmanager

cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF

sleep 30
kubectl get clustersecretstore
# Must show: STATUS=Valid  CAPABILITIES=ReadWrite  READY=True
```

---

## Layer 3 — Docker Image & ECR

### Issue 3.1 — No Issues

Layer 3 completed without errors. The multi-stage Docker build and ECR push worked as expected.

```bash
# Commands that worked cleanly
aws ecr create-repository --repository-name banking-app --region us-east-1
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
docker build -t banking-app:v1.0.2 .
docker tag banking-app:v1.0.2 ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/banking-app:v1.0.2
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/banking-app:v1.0.2
```

---

## Layer 4 — Application Deployment via Helm

### Issue 4.1 — Helm Fails: CRD Not Found for Istio, VPA, Prometheus

**Error:**
```
Error: unable to build kubernetes objects from release manifest:
- no matches for kind "DestinationRule" in version "networking.istio.io/v1alpha3"
- no matches for kind "Gateway" in version "networking.istio.io/v1alpha3"
- no matches for kind "VirtualService" in version "networking.istio.io/v1alpha3"
- no matches for kind "VerticalPodAutoscaler" in version "autoscaling.k8s.io/v1"
- no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
```

**Root Cause:**
The Helm chart templates for Istio (`Gateway`, `VirtualService`, `DestinationRule`), VPA, and ServiceMonitor are rendered unconditionally — they have no `{{- if .Values.feature.enabled }}` guards. Since Istio, VPA, and Prometheus are not installed yet at this layer, their CRDs don't exist.

**Fix — Add if-guards to all 4 affected templates:**

```bash
# 12_gateway.yaml
cat > k8s-manifests/banking-platform/templates/12_gateway.yaml << 'EOF'
{{- if .Values.istio.enabled }}
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
...
{{- end }}
EOF

# 13_virtual-service.yaml
cat > k8s-manifests/banking-platform/templates/13_virtual-service.yaml << 'EOF'
{{- if .Values.istio.enabled }}
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
...
{{- end }}
EOF

# 14_destination-rule.yaml
cat > k8s-manifests/banking-platform/templates/14_destination-rule.yaml << 'EOF'
{{- if .Values.istio.enabled }}
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
...
{{- end }}
EOF

# 15_predictive-vpa.yaml
cat > k8s-manifests/banking-platform/templates/15_predictive-vpa.yaml << 'EOF'
{{- if .Values.vpa.enabled }}
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
...
{{- end }}
EOF
```

Also add to `values-prod.yaml`:
```yaml
istio:
  enabled: false   # enable when Layer 6 (Istio) is installed
  host: "api.yourdomain.com"

vpa:
  enabled: false   # enable when Layer 14 (VPA) is installed
```

And disable `serviceMonitor` until Prometheus is installed (Layer 9):
```yaml
serviceMonitor:
  enabled: false
```

---

### Issue 4.2 — Helm Fails: `namespaces "istio-system" not found`

**Error:**
```
Error: 2 errors occurred:
  * namespaces "banking-prod" already exists
  * namespaces "istio-system" not found
```

**Root Cause:**
The `11_ingress.yaml` template has `namespace: istio-system` hardcoded instead of using the Helm values namespace. Since Istio isn't installed yet, the `istio-system` namespace doesn't exist.

**Fix:**
Update `11_ingress.yaml` to use `{{ .Values.namespace }}` and wrap with an if-guard:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: banking-ingress
  namespace: {{ .Values.namespace }}   # was hardcoded as "istio-system"
  ...
{{- end }}
```

Also set `ingress.enabled: false` in `values-prod.yaml` until Istio is installed.

The `namespaces "banking-prod" already exists` error is harmless — remove `--create-namespace` from the Helm command since the namespace was already created.

---

### Issue 4.3 — Invalid Field `allowPrivilegeEscalation` in Pod-level SecurityContext

**Warning:**
```
Warning: unknown field "spec.template.spec.securityContext.allowPrivilegeEscalation"
```

**Root Cause:**
`allowPrivilegeEscalation` is a container-level security context field, not a pod-level field. It was incorrectly placed in both `spec.template.spec.securityContext` (pod level — wrong) and `spec.template.spec.containers[].securityContext` (container level — correct).

**Fix:**
Remove `allowPrivilegeEscalation: false` from the pod-level `securityContext` in `6_rollout.yaml`. Keep it only at the container level:

```yaml
# Pod level - securityContext (remove allowPrivilegeEscalation from here)
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 2000
  seccompProfile:
    type: RuntimeDefault

# Container level - securityContext (keep allowPrivilegeEscalation here)
containers:
  - name: banking-api
    securityContext:
      allowPrivilegeEscalation: false   # correct placement
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop: ["ALL"]
```

---

### Issue 4.4 — Rollout Degraded: AnalysisTemplate Not Found

**Error:**
```
The Rollout "bankapp-banking-platform" is invalid:
spec.strategy.blueGreen.prePromotionAnalysis.templates:
Invalid value: "banking-success-rate-check": AnalysisTemplate not found
Phase: Degraded
```

**Root Cause:**
The Rollout spec references an `AnalysisTemplate` called `banking-success-rate-check` which queries Prometheus metrics. But Prometheus isn't installed yet (that's Layer 9), so the AnalysisTemplate doesn't exist.

**Fix:**
Remove the `prePromotionAnalysis` block from `6_rollout.yaml` until Prometheus is installed in Layer 9. The simplified blueGreen strategy:

```yaml
strategy:
  blueGreen:
    activeService: {{ include "banking.fullname" . }}-active
    previewService: {{ include "banking.fullname" . }}-preview
    autoPromotionEnabled: false
    scaleDownDelaySeconds: 60
    # prePromotionAnalysis removed — will be re-added in Layer 9 after Prometheus
```

> **Note:** Re-add the `prePromotionAnalysis` block after Layer 9 (Prometheus) is installed and verified. The full block is:
> ```yaml
> prePromotionAnalysis:
>   templates:
>     - templateName: banking-success-rate-check
>   args:
>     - name: app-name
>       value: {{ include "banking.fullname" . }}
> ```

---

### Issue 4.5 — IRSA Role ARN Typo in values-prod.yaml

**Symptom:**
Pod starts but AWS API calls fail silently. IRSA role not assumed.

**Root Cause:**
The IAM Role ARN was missing a colon in the `values-prod.yaml`:

```yaml
# WRONG — missing :: after iam
eks.amazonaws.com/role-arn: arn:aws:iam:959589242185:role/banking-prod-app-irsa-role

# CORRECT
eks.amazonaws.com/role-arn: arn:aws:iam::959589242185:role/banking-prod-app-irsa-role
```

**Fix:**
```bash
sed -i 's|arn:aws:iam:959589242185|arn:aws:iam::959589242185|g' \
  k8s-manifests/banking-platform/values-prod.yaml
```

**Prevention:**
Always verify the IRSA ARN format after writing it. The correct format is always:
```
arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
          ^^
          two colons here
```

---

### Issue 4.6 — Pod CrashLoopBackOff: DB Connection Timeout

**Symptom:**
```
NAME                                       READY   STATUS    RESTARTS
bankapp-banking-platform-xxx               0/1     Running   1 (85s ago)
```

**Crash log:**
```
Caused by: java.net.SocketTimeoutException: Connect timed out
  at com.mysql.cj.protocol.a.NativeSocketConnection.connect
```

**Root Cause:**
The RDS security group was configured to allow port 3306 from `sg-095360fcbae2537aa` (the Terraform-created EKS nodes SG), but the actual EKS node was using a different security group `sg-05139ba7d6438db53`.

This happens because Terraform creates the security group rule referencing the SG it manages, but the actual EC2 node may be in a different SG depending on the EKS node group configuration.

**Diagnosis:**
```bash
# Get RDS SG
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier bankapp-prod-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Get actual EKS node SG
EKS_NODE_SG=$(aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=<NODE_INTERNAL_IP>" \
  --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
  --output text)

# Check what SG the RDS rule allows
aws ec2 describe-security-groups \
  --group-ids $RDS_SG \
  --query 'SecurityGroups[0].IpPermissions[*].UserIdGroupPairs[*].GroupId'

# If EKS_NODE_SG is not in the list above, that's the problem
```

**Fix:**
Add the actual EKS node security group to the RDS inbound rules:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 3306 \
  --source-group $EKS_NODE_SG \
  --region us-east-1
```

**Verification:**
```bash
# Test MySQL connectivity from inside the cluster
kubectl run mysql-test \
  --image=mysql:8.0 \
  --restart=Never \
  --rm -it \
  -n banking-prod \
  -- mysql \
  -h <RDS_ENDPOINT> \
  -u <DB_USERNAME> \
  -p<DB_PASSWORD> \
  <DB_NAME> \
  -e "SELECT 1;"
# Must return: 1
```

**Prevention:**
In Terraform, always use a `data` source to get the actual node group SG rather than referencing a module-created SG:
```hcl
# In security/main.tf, tag the RDS SG rule source more carefully
# Or output the node group SG from the EKS module and reference it directly
```

---

### Issue 4.7 — Network CIDR Too Restrictive in NetworkPolicy

**Symptom:**
Even after fixing the AWS security group, DB connections might still fail from the pod if the Kubernetes NetworkPolicy is too restrictive.

**Root Cause:**
`values-prod.yaml` had `databaseCidr: "10.10.0.0/24"` but the RDS was deployed in `10.0.x.x` subnets. The NetworkPolicy was blocking egress to the DB.

**Fix:**
```yaml
# WRONG — RDS is not in this CIDR
network:
  databaseCidr: "10.10.0.0/24"

# CORRECT — matches actual VPC CIDR where RDS lives
network:
  databaseCidr: "10.0.0.0/16"
```

---

### Issue 4.8 — `actuator/health` Returns Login Page Instead of JSON

**Symptom:**
```bash
curl http://localhost:8080/actuator/health
# Returns HTML login page instead of {"status":"UP"}
```

**Root Cause:**
Spring Security is configured to protect all endpoints including `/actuator/health`. When accessed without authentication, it redirects to the login page.

**This is not actually an error** — the app is healthy. The redirect proves Spring Security is working correctly.

**Verification (use liveness endpoint instead):**
```bash
kubectl exec $POD -n banking-prod -- wget -qO- http://localhost:8080/actuator/health/liveness
# Returns: {"status":"UP"}
```

Or verify via Argo Rollouts which uses the readiness probe internally:
```bash
kubectl argo rollouts get rollout bankapp-banking-platform -n banking-prod
# Status: ✔ Healthy confirms DB is connected and app is running
```

**Prevention:**
In `SecurityConfig.java`, expose specific actuator endpoints publicly for health checks:
```java
.authorizeHttpRequests(authz -> authz
    .requestMatchers("/actuator/health/**").permitAll()
    .requestMatchers("/register").permitAll()
    .anyRequest().authenticated()
)
```

---

## Key Lessons Learned

### 1. Install order matters — dependencies must exist before referencing them
Every Helm chart template that references a CRD must be wrapped in an `{{- if .Values.feature.enabled }}` guard. Install components in layers and only enable features once the prerequisite layer is running.

### 2. Always verify security group alignment
When Terraform creates a security group rule referencing another SG, verify that the actual EC2 instances are using that exact SG. EKS node groups often have additional SGs attached that Terraform doesn't know about.

### 3. AWS Secrets Manager key names must match exactly
The property names in your AWS secret (`db_username`, `db_password`) must match what your `ExternalSecret` manifest references in `remoteRef.property`. A single character difference means the secret syncs successfully but with empty values.

### 4. IRSA ARN format has two colons after `iam`
```
arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
           ^^ two colons
```
Always double-check this when writing ARNs manually.

### 5. Bootstrap must run before main Terraform
The S3 bucket and DynamoDB table for Terraform state must exist before `terraform init` can succeed in the prod directory. Always run bootstrap first, note the resource names, and verify they match `backend.tf`.

### 6. Helm dry-run before every deploy
```bash
helm template bankapp ./k8s-manifests/banking-platform \
  --values values-prod.yaml 2>&1 | grep -iE "error|warning"
```
This catches CRD issues, missing values, and template errors before they hit the cluster.

### 7. Pod readiness probe passing = DB connected
If a Spring Boot pod shows `1/1 Ready`, the readiness probe at `/actuator/health/readiness` is passing. That endpoint checks the DB connection. A `Ready` pod means the database is reachable and the connection pool is healthy — even if `/actuator/health` returns a login page.

---

## Quick Reference — Verification Commands

```bash
# Full layer-by-layer health check
echo "=== NODES ===" && kubectl get nodes
echo "=== EKS ADD-ONS ===" && kubectl get pods -n kube-system | grep -E "ebs-csi|aws-load"
echo "=== EXTERNAL SECRETS ===" && kubectl get pods -n external-secrets
echo "=== SECRET STORE ===" && kubectl get clustersecretstore
echo "=== ECR IMAGE ===" && aws ecr list-images --repository-name banking-app --region us-east-1
echo "=== APP POD ===" && kubectl get pods -n banking-prod
echo "=== ROLLOUT ===" && kubectl argo rollouts get rollout bankapp-banking-platform -n banking-prod
echo "=== EXTERNAL SECRET SYNC ===" && kubectl get externalsecret -n banking-prod
echo "=== DB SG CHECK ===" && \
  RDS_SG=$(aws rds describe-db-instances --db-instance-identifier bankapp-prod-db --region us-east-1 --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text) && \
  aws ec2 describe-security-groups --group-ids $RDS_SG --query 'SecurityGroups[0].IpPermissions[*].UserIdGroupPairs[*].GroupId' --output text
```

--- 
# 🏦 Banking Platform — Deployment Troubleshooting Guide

> **Real-world issues encountered and solved while deploying a production-grade banking platform on AWS EKS**
>
> This document captures every error faced during layer-by-layer deployment and the exact fix applied.
> Use this as a reference when deploying on a fresh VM to avoid repeating the same mistakes.

---

## 📋 Table of Contents

- [Layer 6 — Istio Service Mesh](#layer-6--istio-service-mesh)
  - [Issue 1: ArgoCD CLI Permission Denied](#issue-1-argocd-cli-permission-denied)
  - [Issue 2: Istio Gateway Chart Schema Bug](#issue-2-istio-gateway-chart-schema-bug)
  - [Issue 3: Istio Gateway Chart Version Not Found in Repo](#issue-3-istio-gateway-chart-version-not-found-in-repo)
  - [Issue 4: Istio Sidecar Not Injecting into Pods](#issue-4-istio-sidecar-not-injecting-into-pods)
  - [Issue 5: Gateway and VirtualService Not Created](#issue-5-gateway-and-virtualservice-not-created)
- [Layer 7 — Kyverno Policy Engine](#layer-7--kyverno-policy-engine)
  - [Issue 6: Helm Install Conflict with ArgoCD Managed Kyverno](#issue-6-helm-install-conflict-with-argocd-managed-kyverno)
  - [Issue 7: Kyverno Pods Pending — Insufficient CPU](#issue-7-kyverno-pods-pending--insufficient-cpu)
  - [Issue 8: Stale CronJob Pod Showing ImagePullBackOff](#issue-8-stale-cronjob-pod-showing-imagepullbackoff)
- [Layer 8 — Karpenter Autoscaler](#layer-8--karpenter-autoscaler)
  - [Issue 9: Karpenter Chart Version Not Found](#issue-9-karpenter-chart-version-not-found)
  - [Issue 10: Kyverno Blocking Karpenter Helm Install](#issue-10-kyverno-blocking-karpenter-helm-install)
  - [Issue 11: Helm Cannot Reuse Release Name](#issue-11-helm-cannot-reuse-release-name)
  - [Issue 12: Karpenter IRSA AccessDenied — Wrong Service Account Name](#issue-12-karpenter-irsa-accessdenied--wrong-service-account-name)

---

## Layer 6 — Istio Service Mesh

---

### Issue 1: ArgoCD CLI Permission Denied

**Layer:** 6 — Istio  
**Severity:** Low — Not a real error, just CLI session issue

**Error:**
```
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied","time":"2026-04-11T11:52:48Z"}
```

**Full Command That Failed:**
```bash
argocd app get infra-istio-istio-base
```

**Root Cause:**
ArgoCD CLI was not logged in. The `kubectl apply` of the ArgoCD Application
succeeded, but the `argocd` CLI command failed because there was no active session.

**Fix:**
```bash
# Get ArgoCD admin password
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Port forward ArgoCD server (if not already running)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Login
argocd login localhost:8080 \
  --username admin \
  --password $ARGOCD_PASS \
  --insecure
```

**Verification:**
```bash
argocd app list
# Should show all apps without permission error
```

**Key Lesson:**
> Always login to ArgoCD CLI before running any `argocd` commands.
> The `PermissionDenied` is purely a CLI session issue — the actual
> `kubectl apply` worked fine. Check `kubectl get application -n argocd`
> to verify the resource was created regardless of CLI errors.

---

### Issue 2: Istio Gateway Chart Schema Bug

**Layer:** 6 — Istio  
**Severity:** High — Blocks gateway deployment completely

**Error:**
```
ComparisonError: Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = Manifest generation error (cached):
failed to execute helm template command:
Error: values don't meet the specifications of the schema(s) in the following chart(s):
gateway:
- at '': additional properties 'gateways', 'defaults' not allowed
```

**What Was Tried (All Failed):**

Attempt 1 — Old operator format:
```yaml
# ❌ WRONG
values: |
  gateways:
    istio-ingressgateway:
      enabled: true
      service:
        type: LoadBalancer
```

Attempt 2 — Direct top-level keys:
```yaml
# ❌ WRONG
values: |
  service:
    type: LoadBalancer
  autoscaling:
    enabled: true
  resources:
    requests:
      cpu: 100m
```

Attempt 3 — Using `defaults` key (from chart's own values.yaml):
```yaml
# ❌ WRONG — even though chart's own values.yaml uses 'defaults'
values: |
  defaults:
    service:
      type: LoadBalancer
```

Attempt 4 — Empty values:
```yaml
# ❌ WRONG — even no values fails
values: |
  global: {}
```

**Root Cause:**
The Istio `gateway` chart version `1.22.0` has a **confirmed schema validation bug**
where its own `values.schema.json` rejects its own default `values.yaml`.
This was confirmed by running:
```bash
helm template test-gateway istio/gateway --version 1.22.0 --dry-run
# Error: values don't meet the specifications of the schema(s)
# gateway: - at '': additional properties 'defaults' not allowed
# Fails even with ZERO custom values — the chart itself is broken
```

**Fix:**
Skip ArgoCD for the gateway entirely. Install directly via Helm using a working version:

```bash
# Step 1 — Add Istio repo and find working version
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm search repo istio/gateway --versions | head -10
# Use 1.26.8 — confirmed working

# Step 2 — Install gateway directly via Helm
helm install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --version 1.26.8

# Step 3 — Add NLB annotations to the service
kubectl annotate svc istio-ingressgateway -n istio-system \
  service.beta.kubernetes.io/aws-load-balancer-type="external" \
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type="instance" \
  service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
  --overwrite

# Step 4 — Delete broken ArgoCD app to avoid conflicts
argocd app delete istio-ingressgateway --cascade=false

# Step 5 — Update yaml file for future reference
sed -i 's/targetRevision: 1.22.0/targetRevision: 1.26.8/' \
  k8s-manifests/argocd-infra/networking/2_istio-gateway.yaml
```

**Verification:**
```bash
kubectl get pods -n istio-system | grep gateway
# Expected: istio-ingressgateway-xxx   1/1   Running

kubectl get svc istio-ingressgateway -n istio-system
# Expected: EXTERNAL-IP = NLB DNS name
```

**Key Lesson:**
> The Istio 1.22.0 `gateway` chart is broken — do not use it.
> When an ArgoCD app has a `ComparisonError` on a Helm chart, always
> test the chart locally first with `helm template --dry-run` before
> spending time fixing your values. If the chart itself fails with no
> custom values, the chart is broken — not your config.

---

### Issue 3: Istio Gateway Chart Version Not Found in Repo

**Layer:** 6 — Istio  
**Severity:** Medium

**Error:**
```
Error: chart "karpenter" version "0.37.0" not found in https://charts.karpenter.sh repository
```

**Root Cause:**
Istio 1.22.x charts are no longer published in the Helm repo.
The repo only keeps recent versions. Running `helm search repo` confirmed
the oldest available version was `1.26.x`.

**Diagnosis:**
```bash
helm search repo istio/gateway --versions | head -10
# NAME              CHART VERSION   APP VERSION
# istio/gateway     1.29.1          1.29.1
# istio/gateway     1.28.5          1.28.5
# ...
# 1.22.x does not exist
```

**Fix:**
Use the latest available compatible version:
```bash
# Confirmed working version
helm install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --version 1.26.8 \
  --wait
```

**Key Lesson:**
> Before committing any chart version to your yaml files, always run
> `helm search repo <chart> --versions` to verify the version actually
> exists. Helm chart repos regularly drop old versions.

---

### Issue 4: Istio Sidecar Not Injecting into Pods

**Layer:** 6 — Istio  
**Severity:** Medium

**Symptom:**
```bash
kubectl get pods -n banking-prod
NAME                                       READY   STATUS    RESTARTS   AGE
bankapp-banking-platform-7964465c4-dgg8n   1/1     Running   0          109m
# Expected 2/2 — istio-proxy sidecar missing
```

**Root Cause:**
The banking app pod was created before Istio was installed.
Existing pods do not automatically get the Istio sidecar injected.
The `istio-sidecar-injector` MutatingWebhook only injects into
**new pods** at creation time.

**Fix:**
```bash
# Verify namespace has the injection label
kubectl get namespace banking-prod --show-labels | grep istio-injection
# Must show: istio-injection=enabled

# If missing, add it
kubectl label namespace banking-prod istio-injection=enabled --overwrite

# Restart the rollout to trigger new pod creation
kubectl argo rollouts restart bankapp-banking-platform -n banking-prod
sleep 30

# If rollout restart is slow, force pod deletion
kubectl delete pod -n banking-prod \
  $(kubectl get pods -n banking-prod -o name | head -1 | cut -d/ -f2)

# Watch new pod — must show 2/2
kubectl get pods -n banking-prod -w
```

**Verification:**
```bash
# Confirm both containers are present
kubectl get pod -n banking-prod \
  $(kubectl get pods -n banking-prod -o name | head -1 | cut -d/ -f2) \
  -o jsonpath='{.spec.containers[*].name}'
# Expected: banking-api istio-proxy
```

**Key Lesson:**
> Istio sidecar injection is a webhook that fires at pod creation time.
> Any pod that existed before Istio was installed will never get the sidecar
> unless it is restarted. Always restart all pods in injection-enabled
> namespaces after installing Istio.

---

### Issue 5: Gateway and VirtualService Not Created

**Layer:** 6 — Istio  
**Severity:** High — Traffic routing will not work without these

**Symptom:**
```bash
kubectl get gateway -n banking-prod
# No resources found in banking-prod namespace.

kubectl get virtualservice -n banking-prod
# No resources found in banking-prod namespace.
```

**Root Cause:**
The Helm chart templates for `Gateway` and `VirtualService` have a
conditional block `{{- if .Values.istio.enabled }}`. This value was
set to `false` in the deployed values, so the templates were skipped.

**Diagnosis:**
```bash
helm get values bankapp -n banking-prod | grep -A3 istio
# istio:
#   enabled: false    ← This is why Gateway/VirtualService were not created
#   host: api.rohandevops.co.in
```

**Fix:**
```bash
# Get cert ARN
CERT_ARN=$(aws acm list-certificates --region us-east-1 \
  --query 'CertificateSummaryList[0].CertificateArn' --output text)

# Upgrade Helm with istio.enabled=true
helm upgrade bankapp ./k8s-manifests/banking-platform \
  --namespace banking-prod \
  --values ./k8s-manifests/banking-platform/values-prod.yaml \
  --set ingress.enabled=true \
  --set ingress.host="api.rohandevops.co.in" \
  --set ingress.certificateArn="$CERT_ARN" \
  --set istio.enabled=true \
  --set istio.host="api.rohandevops.co.in"
```

**Verification:**
```bash
kubectl get gateway -n banking-prod
# Expected: bankapp-banking-platform-gateway   1d

kubectl get virtualservice -n banking-prod
# Expected: bankapp-banking-platform-vs   1d
```

**Key Lesson:**
> Always check Helm values after deployment using `helm get values <release> -n <namespace>`.
> Conditional templates in Helm charts (`{{- if .Values.xxx.enabled }}`) silently
> skip resource creation when the flag is false. If a resource is missing,
> check the template file for conditions and the deployed values for the flag status.

---

## Layer 7 — Kyverno Policy Engine

---

### Issue 6: Helm Install Conflict with ArgoCD Managed Kyverno

**Layer:** 7 — Kyverno  
**Severity:** Medium

**Error:**
```
Error: INSTALLATION FAILED: Unable to continue with install:
ServiceAccount "kyverno-admission-controller" in namespace "kyverno" exists
and cannot be imported into the current release:
invalid ownership metadata;
annotation validation error: missing key "meta.helm.sh/release-name": must be set to "kyverno";
annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "kyverno"
```

**What Happened:**
```bash
# Step 1 — Applied ArgoCD app (correct)
kubectl apply -f k8s-manifests/argocd-infra/governance/1_kyverno.yaml
# ArgoCD immediately started installing Kyverno via Helm

# Step 2 — Also ran helm install manually (WRONG)
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --version 3.3.3
# This failed because ArgoCD already created the ServiceAccount
```

**Root Cause:**
When you apply an ArgoCD `Application` resource that points to a Helm chart,
ArgoCD **immediately** starts installing that Helm chart into the cluster.
Running `helm install` separately for the same chart creates a conflict
because ArgoCD-managed resources have different ownership annotations
than Helm-managed resources.

**Fix:**
Do NOT run `helm install` when ArgoCD is managing the installation.
Just wait for ArgoCD to finish:

```bash
# CORRECT approach — ArgoCD only
kubectl apply -f k8s-manifests/argocd-infra/governance/1_kyverno.yaml

# Wait and monitor ArgoCD sync
argocd app get kyverno
kubectl get pods -n kyverno -w
# ArgoCD handles everything — no helm install needed
```

**Key Lesson:**
> **Golden Rule:** If ArgoCD is managing a component, NEVER run `helm install`
> for the same component. ArgoCD IS the Helm installer. Running both
> causes ownership conflicts that are painful to resolve.
> Only use `helm install` directly when ArgoCD is NOT managing that component
> (like we did for the Istio gateway).

---

### Issue 7: Kyverno Pods Pending — Insufficient CPU

**Layer:** 7 — Kyverno  
**Severity:** High — Nothing works until nodes have capacity

**Symptom:**
```bash
kubectl get pods -n kyverno
NAME                                             READY   STATUS    RESTARTS   AGE
kyverno-admission-controller-768cff6447-k74fh    0/1     Pending   0          60s
kyverno-background-controller-849858b7fb-5bbjb   0/1     Pending   0          60s
kyverno-cleanup-controller-56fc6c64c-dvkqx       0/1     Pending   0          60s
kyverno-reports-controller-645c564d7-nbm7p       0/1     Pending   0          60s
```

**Diagnosis:**
```bash
kubectl describe pod -n kyverno \
  $(kubectl get pods -n kyverno -o name | head -1 | cut -d/ -f2) | grep -A5 "Events:"
# Warning  FailedScheduling  0/1 nodes are available: 1 Insufficient cpu.
```

**Root Cause:**
The cluster had only 1 node which was already running ArgoCD, External Secrets,
banking app, and Istio components. Kyverno requires 4 pods with CPU requests
that exceeded the remaining capacity on the single node.

**Fix:**
```bash
# Scale up node group to 2 nodes
aws eks update-nodegroup-config \
  --cluster-name bankapp-prod-eks \
  --nodegroup-name general-purpose \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --region us-east-1

# Wait for second node to be Ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes
# Must show 2 nodes Ready

# Kyverno pods will automatically schedule on the new node
kubectl get pods -n kyverno -w
# All 4 pods should go Running within 2 minutes
```

**Key Lesson:**
> Before installing heavy components like Kyverno, Prometheus, or Loki,
> always check node capacity first. A single `t3.medium` or `m7i-flex.large`
> node fills up quickly with all the platform components. Scale to at least
> 2 nodes before Layer 7 to avoid scheduling failures.

---

### Issue 8: Stale CronJob Pod Showing ImagePullBackOff

**Layer:** 7 — Kyverno  
**Severity:** Low — Does not affect functionality

**Symptom:**
```bash
kubectl get pods -n kyverno
NAME                                             READY   STATUS
kyverno-admission-controller-768cff6447-k74fh    1/1     Running
kyverno-background-controller-849858b7fb-5bbjb   1/1     Running
kyverno-clean-reports-svhwz                      0/1     ImagePullBackOff   ← This one
kyverno-cleanup-controller-56fc6c64c-dvkqx       1/1     Running
kyverno-reports-controller-645c564d7-nbm7p       1/1     Running
```

**Root Cause:**
`kyverno-clean-reports-xxxxx` is a one-time CronJob pod that Kyverno creates
to clean up old policy reports. It is **not** one of the 4 main Kyverno
controller pods. The `ImagePullBackOff` on this pod does not affect
Kyverno's policy enforcement functionality at all.

**Fix:**
```bash
# Simply delete the failed CronJob pod
kubectl delete pod kyverno-clean-reports-svhwz -n kyverno

# Verify the 4 main pods are still Running
kubectl get pods -n kyverno | grep -v clean-reports
```

**Key Lesson:**
> Not every failing pod is a problem. CronJob pods are one-time execution pods
> that may fail due to timing or image issues without affecting the main workload.
> Always identify whether a failing pod is a core controller pod or a
> one-time job pod before raising an alarm.

---

## Layer 8 — Karpenter Autoscaler

---

### Issue 9: Karpenter Chart Version Not Found

**Layer:** 8 — Karpenter  
**Severity:** High — Blocks installation completely

**Error:**
```
ComparisonError: Failed to load target state:
error fetching chart: failed to fetch chart:
`helm pull --version 0.37.0 --repo https://charts.karpenter.sh karpenter`
failed exit status 1:
Error: chart "karpenter" version "0.37.0" not found in https://charts.karpenter.sh repository
```

**Root Cause:**
Two problems combined:
1. The `3_karpenter.yaml` file references version `0.37.0` which never existed
   in the `charts.karpenter.sh` repo
2. The `charts.karpenter.sh` repo only has versions up to `0.16.3` which use
   old `v1alpha5` CRDs — incompatible with the `v1beta1` CRDs used in
   `4_karpenter-nodeclass.yaml` and `5_karpenter-nodepool.yaml`

**Diagnosis:**
```bash
helm repo add karpenter https://charts.karpenter.sh
helm search repo karpenter/karpenter --versions
# NAME                    CHART VERSION
# karpenter/karpenter     0.16.3    ← Latest — uses old v1alpha5 CRDs
# karpenter/karpenter     0.16.2
# ...
# 0.37.0 does not exist anywhere
```

**Fix:**
Karpenter moved to OCI registry. Install from the correct source:

```bash
# Set required variables
CLUSTER_NAME="bankapp-prod-eks"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_ENDPOINT=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --query "cluster.endpoint" --output text)

# Install from OCI registry (correct source for modern Karpenter)
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=$CLUSTER_NAME" \
  --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/bankapp-karpenter-controller-irsa" \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=512Mi \
  --set controller.resources.limits.cpu=1000m \
  --set controller.resources.limits.memory=1Gi \
  --wait

# Delete broken ArgoCD app to avoid conflicts
argocd app delete karpenter --cascade=false
```

**Key Lesson:**
> Karpenter v1beta1 (versions 1.x) is only available from the OCI registry
> at `oci://public.ecr.aws/karpenter/karpenter`. The old `charts.karpenter.sh`
> repo only has legacy v1alpha5 versions (0.16.x and below).
> If your manifests use `EC2NodeClass` and `NodePool` CRDs, you need v1beta1
> from the OCI registry — not the old Helm repo.

---

### Issue 10: Kyverno Blocking Karpenter Helm Install

**Layer:** 8 — Karpenter  
**Severity:** High

**Error:**
```
Error: INSTALLATION FAILED: 1 error occurred:
* admission webhook "validate.kyverno.svc-fail" denied the request:
resource Deployment/karpenter/karpenter was blocked due to the following policies

banking-guardrails:
  autogen-disallow-root-user: 'validation error: Running as root is forbidden in the
    Banking Cluster. rule autogen-disallow-root-user failed at path
    /spec/template/spec/securityContext/runAsNonRoot/'
```

**Root Cause:**
The Kyverno `banking-guardrails` ClusterPolicy was in `Enforce` mode,
blocking any pod that does not explicitly set `runAsNonRoot: true`.
The Karpenter Helm chart does not set this security context by default,
so Kyverno rejected the Deployment.

**Fix:**
Temporarily switch Kyverno to `Audit` mode, install Karpenter, then restore `Enforce`:

```bash
# Step 1 — Switch to Audit mode
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Audit"}]'

kubectl get clusterpolicy
# Verify: banking-guardrails shows Audit

# Step 2 — Install Karpenter (will succeed now)
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=$CLUSTER_NAME" \
  --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/bankapp-karpenter-controller-irsa" \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=512Mi \
  --set controller.resources.limits.cpu=1000m \
  --set controller.resources.limits.memory=1Gi \
  --wait

# Step 3 — Restore Enforce mode immediately
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Enforce"}]'

kubectl get clusterpolicy
# Verify: banking-guardrails shows Enforce
```

**Key Lesson:**
> Kyverno `Enforce` mode will block ANY deployment that violates policies —
> including infrastructure tools like Karpenter that you are trying to install.
> The correct approach is to temporarily switch to `Audit` mode for the install,
> then immediately restore `Enforce`. Never leave it in `Audit` mode permanently.

---

### Issue 11: Helm Cannot Reuse Release Name

**Layer:** 8 — Karpenter  
**Severity:** Medium

**Error:**
```
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```

**Root Cause:**
A previous failed Helm install left a broken release in `failed` state.
Helm tracks releases in a Secret inside the namespace. Even though the
pods were not running, the release metadata still existed, preventing
a fresh install.

**Diagnosis:**
```bash
helm list -n karpenter
# NAME        NAMESPACE   REVISION    STATUS      CHART
# karpenter   karpenter   1           failed      karpenter-1.3.3
```

**Fix:**
```bash
# Remove the failed release
helm uninstall karpenter -n karpenter

# Verify it's gone
helm list -n karpenter
# Should show empty table

# Now install fresh
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  ...
```

**Key Lesson:**
> When a Helm install fails, always run `helm uninstall` before retrying.
> Failed releases leave metadata in the cluster that blocks subsequent installs.
> Always check `helm list -n <namespace>` before retrying a failed install.

---

### Issue 12: Karpenter IRSA AccessDenied — Wrong Service Account Name

**Layer:** 8 — Karpenter  
**Severity:** Critical — Karpenter cannot provision any nodes

**Error:**
```json
{
  "level": "ERROR",
  "message": "ec2 api connectivity check failed",
  "error": "operation error EC2: DescribeInstanceTypes,
    get identity: get credentials: failed to refresh cached credentials,
    operation error STS: AssumeRoleWithWebIdentity,
    api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"
}
```

**Root Cause:**
The IAM role trust policy was configured for the service account name
`karpenter-sa` (from the Terraform Karpenter IRSA module), but the
Karpenter Helm chart creates a service account named `karpenter` (no `-sa` suffix).

The trust policy `StringEquals` condition did not match, so AWS STS
rejected the token exchange.

**Diagnosis:**
```bash
# Check the IAM role trust policy
aws iam get-role \
  --role-name bankapp-karpenter-controller-irsa \
  --query "Role.AssumeRolePolicyDocument" \
  --output json

# Found this in the trust policy — WRONG service account name:
# "system:serviceaccount:karpenter:karpenter-sa"
#                                            ^^^
# But Helm creates SA named "karpenter" not "karpenter-sa"

# Verify actual SA name created by Helm
kubectl get sa -n karpenter
# NAME        SECRETS   AGE
# karpenter   0         5m    ← Name is "karpenter" not "karpenter-sa"
```

**Fix:**
```bash
# Get OIDC URL
OIDC_URL=$(aws eks describe-cluster \
  --name bankapp-prod-eks \
  --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create corrected trust policy with right SA name
cat > /tmp/karpenter-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com",
          "${OIDC_URL}:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
EOF

# Apply the fix
aws iam update-assume-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-document file:///tmp/karpenter-trust-policy.json

echo "Trust policy updated successfully"

# Restart Karpenter to pick up new credentials
kubectl rollout restart deployment/karpenter -n karpenter

# Watch pods recover
kubectl get pods -n karpenter -w
```

**Verification:**
```bash
# Confirm no more AccessDenied in logs
kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  --tail=20
# Should show only INFO level messages
# Should show controllers starting successfully
```

**Key Lesson:**
> IRSA trust policies are the most common source of `AccessDenied` errors.
> The `sub` condition in the trust policy must match **exactly**:
> `system:serviceaccount:<namespace>:<service-account-name>`
>
> Always verify the actual service account name created by Helm:
> ```bash
> kubectl get sa -n <namespace>
> ```
> And compare it with what is in your IAM role trust policy.
> A single character difference (`karpenter` vs `karpenter-sa`) causes
> complete authentication failure.

---

## 📊 Quick Reference — All Issues Summary

| # | Layer | Issue | Root Cause | Fix |
|---|-------|-------|------------|-----|
| 1 | 6 — Istio | ArgoCD CLI Permission Denied | CLI not logged in | `argocd login localhost:8080` |
| 2 | 6 — Istio | Gateway chart schema bug | Istio 1.22.0 chart is broken | Install via Helm with version 1.26.8 |
| 3 | 6 — Istio | Chart version not found | 1.22.x removed from repo | Use `helm search repo` to find available versions |
| 4 | 6 — Istio | Sidecar not injecting | Pod existed before Istio install | Delete pod to force recreation |
| 5 | 6 — Istio | Gateway/VirtualService missing | `istio.enabled=false` in Helm values | `helm upgrade --set istio.enabled=true` |
| 6 | 7 — Kyverno | Helm conflicts with ArgoCD | Ran `helm install` when ArgoCD manages it | Never use `helm install` for ArgoCD-managed apps |
| 7 | 7 — Kyverno | Pods Pending | Insufficient CPU on single node | Scale node group to 2 nodes |
| 8 | 7 — Kyverno | ImagePullBackOff on clean-reports | Stale CronJob pod — not a real issue | `kubectl delete pod` the stale pod |
| 9 | 8 — Karpenter | Chart version not found | Wrong repo and version | Use OCI registry `oci://public.ecr.aws/karpenter/karpenter` |
| 10 | 8 — Karpenter | Kyverno blocking install | Enforce mode blocks non-compliant deployments | Switch to Audit temporarily, install, restore Enforce |
| 11 | 8 — Karpenter | Cannot reuse release name | Previous failed install left broken release | `helm uninstall` before retrying |
| 12 | 8 — Karpenter | IRSA AccessDenied | Trust policy had wrong SA name (`karpenter-sa` vs `karpenter`) | Update IAM trust policy with correct SA name |

---

## 🔑 Golden Rules Learned

1. **ArgoCD manages Helm — never run both.** If ArgoCD deploys a chart, do not run `helm install` for the same chart.

2. **Always verify chart versions exist** before committing to yaml files. Run `helm search repo <chart> --versions`.

3. **Broken charts fail with no values.** Test with `helm template --dry-run` before blaming your config.

4. **IRSA trust policy SA name must match exactly.** Always verify with `kubectl get sa -n <namespace>`.

5. **Kyverno Enforce blocks everything** — including infrastructure tools. Switch to Audit for installs, then restore Enforce.

6. **Scale nodes before heavy components.** Always check capacity before installing Kyverno, Prometheus, Loki.

7. **Pod restarts are required after Istio install.** Sidecar injection only happens at pod creation time.

8. **Failed Helm installs leave broken releases.** Always run `helm uninstall` before retrying a failed install.

9. **Modern Karpenter lives on OCI registry.** Use `oci://public.ecr.aws/karpenter/karpenter` — not the old `charts.karpenter.sh` repo.

10. **Check `helm get values` after deployment.** Conditional templates silently skip resources when flags are false.

---


# Karpenter Layer 8 — Troubleshooting Guide

> **Environment:** EKS 1.31 | Karpenter 1.3.3 | Kyverno 3.3.3 | AWS us-east-1  
> **Project:** Banking Platform on EKS  
> **Author:** Documented from real production debugging session

---

## Table of Contents

1. [Error 1 — Wrong Helm Chart Version (0.37.0 not found)](#error-1--wrong-helm-chart-version)
2. [Error 2 — Kyverno Blocking Karpenter Install](#error-2--kyverno-blocking-karpenter-install)
3. [Error 3 — IRSA Trust Policy Wrong Service Account Name](#error-3--irsa-trust-policy-wrong-service-account-name)
4. [Error 4 — CRD API Version Mismatch (v1beta1 vs v1)](#error-4--crd-api-version-mismatch)
5. [Error 5 — NodePool v1 Schema Breaking Changes](#error-5--nodepool-v1-schema-breaking-changes)
6. [Error 6 — Missing IAM Permissions (eks:DescribeCluster, iam:GetInstanceProfile)](#error-6--missing-iam-permissions)
7. [Error 7 — Missing iam:PassRole Permission](#error-7--missing-iampassrole-permission)
8. [Error 8 — Wrong Node Role Name in EC2NodeClass](#error-8--wrong-node-role-name-in-ec2nodeclass)
9. [Error 9 — EC2NodeClass role Field is Immutable](#error-9--ec2nodeclass-role-field-is-immutable)
10. [Error 10 — Stale Instance Profile in IAM](#error-10--stale-instance-profile-in-iam)
11. [Error 11 — Stale Pod Not Picking Up New IAM Permissions](#error-11--stale-pod-not-picking-up-new-iam-permissions)
12. [Error 12 — Helm Release Name Conflict (cannot re-use a name)](#error-12--helm-release-name-conflict)
13. [Final Working Configuration](#final-working-configuration)

---

## Error 1 — Wrong Helm Chart Version

### What Happened

The ArgoCD application manifest `3_karpenter.yaml` referenced chart version `0.37.0` from `https://charts.karpenter.sh`. This version does not exist in that repository.

```
ComparisonError: Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = error fetching chart: failed to fetch chart:
`helm pull --version 0.37.0 --repo https://charts.karpenter.sh karpenter`
failed exit status 1: Error: chart "karpenter" version "0.37.0" not found
```

### Root Cause

Karpenter moved its Helm chart distribution. The old `https://charts.karpenter.sh` repository only has versions up to `0.16.x`. Version `0.37.0` and later are distributed via OCI registry at `public.ecr.aws/karpenter/karpenter`.

### Fix

Skip the ArgoCD app for Karpenter and install directly via OCI:

```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=$CLUSTER_NAME" \
  --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/bankapp-karpenter-controller-irsa" \
  --wait
```

> **Lesson:** Karpenter 1.x is OCI-only. Never reference `https://charts.karpenter.sh` for versions above `0.16.x`.

---

## Error 2 — Kyverno Blocking Karpenter Install

### What Happened

Kyverno's `banking-guardrails` ClusterPolicy was set to `Enforce` mode and blocked the Karpenter Deployment from being created because it does not set `runAsNonRoot: true` in its pod security context.

```
Error: INSTALLATION FAILED: 1 error occurred:
  * admission webhook "validate.kyverno.svc-fail" denied the request:

resource Deployment/karpenter/karpenter was blocked due to the following policies

banking-guardrails:
  autogen-disallow-root-user: 'validation error: Running as root is forbidden in the
    Banking Cluster. rule autogen-disallow-root-user failed at path
    /spec/template/spec/securityContext/runAsNonRoot/'
```

### Root Cause

The `banking-guardrails` Kyverno policy enforces that all Deployments must set `runAsNonRoot: true`. Karpenter's official Helm chart does not set this field because it runs as a non-root user internally but does not declare it explicitly in the pod spec.

### Fix

Temporarily switch Kyverno to `Audit` mode before installing Karpenter, then restore `Enforce` after:

```bash
# Step 1 — Switch to Audit
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Audit"}]'

# Step 2 — Install Karpenter
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=$CLUSTER_NAME" \
  --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/bankapp-karpenter-controller-irsa" \
  --wait

# Step 3 — Restore Enforce
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Enforce"}]'
```

> **Lesson:** Always temporarily disable strict admission webhooks when installing third-party system components that may not meet your internal security policies. Re-enable immediately after.

---

## Error 3 — IRSA Trust Policy Wrong Service Account Name

### What Happened

After installing Karpenter, pods were crashing in `CrashLoopBackOff` with this error:

```json
{
  "level": "ERROR",
  "message": "ec2 api connectivity check failed",
  "error": "operation error EC2: DescribeInstanceTypes,
    get identity: get credentials: failed to refresh cached credentials,
    failed to retrieve credentials,
    operation error STS: AssumeRoleWithWebIdentity,
    StatusCode: 403,
    api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"
}
```

### Root Cause

The IAM role trust policy was configured with the wrong Kubernetes service account name. The trust policy had:

```json
"StringEquals": {
  "...oidc...:sub": "system:serviceaccount:karpenter:karpenter-sa"
}
```

But the Helm chart creates a service account named `karpenter` (not `karpenter-sa`).

### Fix

Update the trust policy to use the correct service account name:

```bash
OIDC_URL=$(aws eks describe-cluster \
  --name bankapp-prod-eks \
  --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

cat > /tmp/karpenter-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com",
          "${OIDC_URL}:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
EOF

aws iam update-assume-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-document file:///tmp/karpenter-trust-policy.json

kubectl rollout restart deployment/karpenter -n karpenter
```

> **Lesson:** Always verify the exact service account name the Helm chart creates before configuring IRSA. Use `helm template` to preview before installing.

---

## Error 4 — CRD API Version Mismatch

### What Happened

After Karpenter was running, applying `4_karpenter-nodeclass.yaml` and `5_karpenter-nodepool.yaml` failed:

```
error: resource mapping not found for name: "default" namespace: "" 
from "4_karpenter-nodeclass.yaml": no matches for kind "EC2NodeClass" 
in version "karpenter.k8s.aws/v1beta1"
ensure CRDs are installed first

error: resource mapping not found for name: "default" 
from "5_karpenter-nodepool.yaml": no matches for kind "NodePool" 
in version "karpenter.sh/v1beta1"
ensure CRDs are installed first
```

### Root Cause

The manifest files were written for Karpenter `v0.x` which used `v1beta1` API version. Karpenter `1.x` promoted these APIs to `v1`.

| Karpenter Version | API Version |
|---|---|
| 0.x | `karpenter.sh/v1beta1`, `karpenter.k8s.aws/v1beta1` |
| 1.x | `karpenter.sh/v1`, `karpenter.k8s.aws/v1` |

### Fix

```bash
sed -i 's|karpenter.k8s.aws/v1beta1|karpenter.k8s.aws/v1|g' \
  k8s-manifests/argocd-infra/governance/4_karpenter-nodeclass.yaml

sed -i 's|karpenter.sh/v1beta1|karpenter.sh/v1|g' \
  k8s-manifests/argocd-infra/governance/5_karpenter-nodepool.yaml
```

> **Lesson:** When upgrading Karpenter from 0.x to 1.x, all manifests referencing `v1beta1` must be updated to `v1`. Check the [Karpenter migration guide](https://karpenter.sh/docs/upgrading/upgrade-guide/) before upgrading.

---

## Error 5 — NodePool v1 Schema Breaking Changes

### What Happened

After fixing the API version, applying the NodePool still failed with two errors:

```
The NodePool "default" is invalid:
* spec.disruption.expireAfter: unknown field
* spec.disruption.consolidationPolicy: Unsupported value: "WhenUnderutilized":
  supported values: "WhenEmpty", "WhenEmptyOrUnderutilized"
```

### Root Cause

Karpenter `v1` introduced breaking schema changes to `NodePool`:

1. `spec.disruption.expireAfter` was moved to `spec.template.spec.expireAfter`
2. `WhenUnderutilized` was renamed to `WhenEmptyOrUnderutilized`

### Fix

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      expireAfter: 720h          # MOVED HERE from spec.disruption.expireAfter
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["t", "m", "c"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized   # RENAMED
    consolidateAfter: 30s
```

> **Lesson:** Karpenter v1 has several breaking schema changes from v1beta1. Read the full changelog at https://karpenter.sh/docs/upgrading/v1-migration/

---

## Error 6 — Missing IAM Permissions

### What Happened

EC2NodeClass showed `READY=False` with this in Karpenter logs:

```json
{
  "error": "operation error IAM: GetInstanceProfile, StatusCode: 403,
    api error AccessDenied: ...assumed-role/bankapp-karpenter-controller-irsa...
    is not authorized to perform: iam:GetInstanceProfile",
  "error": "operation error EKS: DescribeCluster, StatusCode: 403,
    api error AccessDeniedException: ...is not authorized to perform: eks:DescribeCluster"
}
```

### Root Cause

The Terraform-created IAM policy `bankapp-prod-karpenter-controller-policy` was missing permissions required by Karpenter 1.x. These permissions were not needed in older versions but are required in 1.x for instance profile management.

### Fix

```bash
aws iam put-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-name karpenter-extra-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "eks:DescribeCluster",
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:PassRole"
        ],
        "Resource": "*"
      }
    ]
  }'

kubectl rollout restart deployment/karpenter -n karpenter
```

> **Lesson:** Karpenter 1.x manages EC2 instance profiles itself (unlike older versions where you pre-created them). This requires additional IAM permissions that older Terraform modules don't include.

---

## Error 7 — Missing iam:PassRole Permission

### What Happened

Even after adding the permissions in Error 6, a new error appeared:

```json
{
  "error": "creating instance profile, adding role \"bankapp-karpenter-node-role\"
    to instance profile \"bankapp-prod-eks_15843455441266977890\",
    operation error IAM: AddRoleToInstanceProfile, StatusCode: 403,
    api error AccessDenied: ...is not authorized to perform: iam:PassRole
    on resource: arn:aws:iam::959589242185:role/bankapp-karpenter-node-role"
}
```

### Root Cause

`iam:PassRole` was not included in the first policy update. It is a separate permission from `iam:AddRoleToInstanceProfile` and must be explicitly granted.

### Fix

Update the inline policy to include `iam:PassRole`:

```bash
aws iam put-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-name karpenter-extra-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "eks:DescribeCluster",
          "iam:GetInstanceProfile",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:PassRole"
        ],
        "Resource": "*"
      }
    ]
  }'
```

> **Lesson:** `iam:PassRole` is always required separately when a service needs to attach a role to another AWS resource. It is easy to miss because it doesn't show up in the same error as the other IAM actions.

---

## Error 8 — Wrong Node Role Name in EC2NodeClass

### What Happened

After all IAM fixes, a new error appeared:

```json
{
  "error": "creating instance profile,
    adding role \"bankapp-karpenter-node-role\" to instance profile
    \"bankapp-prod-eks_15843455441266977890\",
    operation error IAM: AddRoleToInstanceProfile, StatusCode: 404,
    NoSuchEntity: The role with name bankapp-karpenter-node-role cannot be found."
}
```

### Root Cause

The EC2NodeClass was configured with `role: "bankapp-karpenter-node-role"` but this role does not exist. The actual roles created by Terraform were:

```
bankapp-karpenter-controller-irsa   ← controller role (IRSA)
bankapp-prod-eks-node-role          ← EKS managed node group role
bankapp-prod-karpenter-node-role    ← correct Karpenter node role
```

### Fix

First identify the correct role:

```bash
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'karpenter') || contains(RoleName, 'node')].RoleName" \
  --output table
```

Then update EC2NodeClass with the correct role name:

```yaml
spec:
  role: "bankapp-prod-karpenter-node-role"   # was "bankapp-karpenter-node-role"
```

> **Lesson:** Always verify exact IAM role names from AWS before putting them in manifests. Never guess — use `aws iam list-roles` to confirm.

---

## Error 9 — EC2NodeClass role Field is Immutable

### What Happened

Trying to `kubectl apply` the fixed EC2NodeClass returned:

```
The EC2NodeClass "default" is invalid:
  spec.role: Invalid value: "string": immutable field changed
```

### Root Cause

The `spec.role` field in `EC2NodeClass` is immutable once created. It cannot be changed via `kubectl apply` or `kubectl patch`.

### Fix

Delete and recreate:

```bash
kubectl delete ec2nodeclass default
kubectl apply -f k8s-manifests/argocd-infra/governance/4_karpenter-nodeclass.yaml
```

> **Lesson:** Several Karpenter fields are immutable by design. When you need to change them, you must delete and recreate the resource. This is safe as long as no nodes are currently provisioned by that NodeClass.

---

## Error 10 — Stale Instance Profile in IAM

### What Happened

Even after recreating EC2NodeClass with the correct role, the error persisted because the old instance profile `bankapp-prod-eks_15843455441266977890` still existed in IAM with the wrong role attached to it.

### Root Cause

When the EC2NodeClass was first created with the wrong role name, Karpenter partially created the instance profile in IAM before failing. When the EC2NodeClass was recreated, Karpenter tried to reuse the existing instance profile but couldn't add the correct role to it.

### Fix

```bash
# Remove the stale instance profile from IAM
aws iam delete-instance-profile \
  --instance-profile-name bankapp-prod-eks_15843455441266977890

# Restart Karpenter to trigger fresh reconciliation
kubectl rollout restart deployment/karpenter -n karpenter
```

> **Lesson:** Karpenter creates IAM instance profiles dynamically. If a reconciliation fails partway through, it can leave orphaned IAM resources. Always check for stale instance profiles in IAM when debugging EC2NodeClass issues.

---

## Error 11 — Stale Pod Not Picking Up New IAM Permissions

### What Happened

After updating IAM permissions and restarting the deployment, the logs still showed the old errors. The pod age showed `45m` — the restart had not actually replaced the pod.

### Root Cause

`kubectl rollout restart` creates new pods but the old pod was not terminating because the deployment only had 1 replica running (the other was in a failed state). The `--wait` flag on the install had been cancelled mid-execution, leaving the deployment in an inconsistent state.

### Fix

Force delete all pods to trigger fresh scheduling:

```bash
kubectl delete pod -n karpenter --all
kubectl get pods -n karpenter -w
# Wait for new pods to reach Running state
```

> **Lesson:** After IAM permission changes, always verify that truly new pods (not old ones) are running by checking pod age with `kubectl get pods -n karpenter`. New pods = new IRSA token = new IAM session with updated permissions.

---

## Error 12 — Helm Release Name Conflict

### What Happened

After multiple failed install attempts, trying to `helm install` again returned:

```
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```

### Root Cause

A previous failed `helm install` left a release in `failed` status. Helm tracks release state and prevents reinstalling over a failed release using the same name.

### Fix

```bash
# Check release status
helm list -n karpenter

# Uninstall the failed release
helm uninstall karpenter -n karpenter

# Then install fresh
helm install karpenter oci://public.ecr.aws/karpenter/karpenter ...
```

> **Lesson:** Always run `helm list -n <namespace>` before reinstalling. A failed Helm release must be explicitly uninstalled before you can reuse the release name.

---

## Final Working Configuration

### EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  amiFamily: AL2023
  role: "bankapp-prod-karpenter-node-role"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: bankapp-prod
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: bankapp-prod
  tags:
    Name: karpenter-node
    Project: Banking-System
```

### NodePool

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      expireAfter: 720h
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["t", "m", "c"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

### Required IAM Inline Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "iam:GetInstanceProfile",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### Correct IRSA Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC_URL"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "OIDC_URL:aud": "sts.amazonaws.com",
          "OIDC_URL:sub": "system:serviceaccount:karpenter:karpenter"
        }
      }
    }
  ]
}
```

### Verification Commands

```bash
# All three must return healthy results
kubectl get pods -n karpenter              # 2/2 Running
kubectl get ec2nodeclass                   # READY=True
kubectl get nodepool                       # READY=True

# No errors in logs
kubectl logs -n karpenter \
  -l app.kubernetes.io/name=karpenter \
  --tail=20 | grep -i "error\|ERR"
# Should return empty
```

---

## Quick Reference — Error → Fix Mapping

| Error | Root Cause | Fix |
|---|---|---|
| Chart version not found | Wrong repo for Karpenter 1.x | Use OCI: `public.ecr.aws/karpenter/karpenter` |
| Kyverno blocks install | `runAsNonRoot` not set in Karpenter chart | Switch to Audit mode, install, restore Enforce |
| `AssumeRoleWithWebIdentity 403` | Trust policy has wrong SA name | Fix to `system:serviceaccount:karpenter:karpenter` |
| CRD `v1beta1` not found | Old manifests, Karpenter 1.x uses `v1` | `sed` replace `v1beta1` → `v1` in all manifests |
| `expireAfter` unknown field | Field moved in v1 schema | Move to `spec.template.spec.expireAfter` |
| `WhenUnderutilized` unsupported | Renamed in v1 | Use `WhenEmptyOrUnderutilized` |
| `GetInstanceProfile 403` | Missing IAM permissions | Add `eks:DescribeCluster` + IAM instance profile perms |
| `PassRole 403` | Missing `iam:PassRole` | Add `iam:PassRole` to controller role policy |
| Role `NoSuchEntity 404` | Wrong role name in EC2NodeClass | Use `bankapp-prod-karpenter-node-role` |
| Immutable field error | `spec.role` cannot be patched | Delete and recreate EC2NodeClass |
| Stale instance profile | IAM leftover from failed reconcile | `aws iam delete-instance-profile` |
| Old pod serving stale logs | Rollout restart didn't terminate old pod | `kubectl delete pod -n karpenter --all` |
| Helm name already in use | Previous failed release not cleaned up | `helm uninstall karpenter -n karpenter` |