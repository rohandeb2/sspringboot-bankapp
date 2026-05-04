# 🏦 Banking Platform — Master Troubleshooting Runbook

> **Project:** Banking Platform on AWS EKS (Production Deployment)
> **Author:** Rohan Deb
> **Environment:** EKS 1.31 | Terraform 1.9.0 | Helm 3.x | Karpenter 1.3.3 | Kyverno 3.3.3 | AWS us-east-1
> **App:** Spring Boot 3.3 (Java 17) | Argo Rollouts
>
> This is a complete record of every real error encountered across the full deployment lifecycle — from Terraform infrastructure bootstrap all the way through observability and disaster recovery.
> Every error, root cause, and fix in this document was executed against a live EKS cluster.

---

## Table of Contents

### Deployment Layers
- [Layer 1 — Terraform Infrastructure](#layer-1--terraform-infrastructure)
- [Layer 2 — EKS Add-ons](#layer-2--eks-add-ons)
- [Layer 3 — Docker Image & ECR](#layer-3--docker-image--ecr)
- [Layer 4 — Application Deployment via Helm](#layer-4--application-deployment-via-helm)
- [Layer 6 — Istio Service Mesh](#layer-6--istio-service-mesh)
- [Layer 7 — Kyverno Policy Engine](#layer-7--kyverno-policy-engine)
- [Layer 8 — Karpenter Autoscaler](#layer-8--karpenter-autoscaler)

### Post-Deployment Operations
- [Velero + MinIO Setup Issues](#velero--minio-setup-issues)
- [ArgoCD Sync Errors (OutOfSync / SyncError)](#argocd-sync-errors-outsync--syncerror)
- [Jenkins Installation & Port Conflicts](#jenkins-installation--port-conflicts)
- [SonarQube Deployment Issues](#sonarqube-deployment-issues)
- [Istio / TLS / DNS Issues (Post-Deploy)](#istio--tls--dns-issues-post-deploy)
- [Kyverno Policy Conflicts (Post-Deploy)](#kyverno-policy-conflicts-post-deploy)
- [Karpenter Node Provisioning (Post-Deploy)](#karpenter-node-provisioning-post-deploy)
- [Observability Stack (OTel / Tempo / Grafana / Kiali)](#observability-stack-otel--tempo--grafana--kiali)
- [ResourceQuota Blocking Pod Scheduling](#resourcequota-blocking-pod-scheduling)
- [Velero Backup Verification & Restore](#velero-backup-verification--restore)

### Reference
- [Golden Rules Learned](#golden-rules-learned)
- [Quick Reference — All Issues](#quick-reference--all-issues)
- [Quick Debug Commands](#quick-debug-commands)

---

## Layer 1 — Terraform Infrastructure

---

### Issue 1.1 — KMS Key Must Exist Before Bootstrap

**Error:**
```
Error: error creating S3 Bucket server side encryption configuration
KMS key ARN not found
```

**Root Cause:**
The S3 bootstrap module requires a KMS key ARN in `terraform.tfvars` but the key didn't exist yet when `terraform apply` was run.

**Fix:**
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

> **Key Lesson:** Bootstrap must always run before main Terraform. The S3 bucket and DynamoDB table for state must exist before `terraform init` works in the prod directory.

---

### Issue 1.2 — Route53 Hosted Zone Must Exist Before ACM Validation

**Error:**
```
Error: error creating Route53 Record: InvalidChangeBatch
No hosted zone found for domain rohandevops.co.in
```

**Root Cause:**
The ACM module tries to create DNS validation records in Route53 during `terraform apply`, but the hosted zone didn't exist yet.

**Fix:**
```bash
aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s)
```

Copy the 4 `NameServers` from the output, update them at your domain registrar, wait 5–30 minutes for propagation, then re-run Terraform.

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
```bash
aws secretsmanager create-secret \
  --name "banking-prod-db-secret" \
  --region us-east-1 \
  --secret-string '{"db_username":"bankappdb","db_password":"YourSecurePassword"}'
```

> **Important:** The `db_username` value becomes the actual RDS master username. It cannot be changed after RDS creation without destroying and recreating the instance.

---

### Issue 1.4 — `db_name` Used as Both Database Name and Master Username

**Root Cause:**
The Terraform RDS module read both `username` and database name from the same Secrets Manager key. The database name ended up as the master username — functional but not ideal for security.

**Fix (for future deployments):**
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

---

### Issue 2.1 — AWS Load Balancer Controller Not Installing

**Symptom:**
```bash
kubectl get pods -n kube-system | grep aws-load-balancer
# Returns empty — no pods found
```

**Root Cause:**
The IRSA service account was not created before Helm install. The controller silently fails to start without the correct IRSA annotation.

**Fix — Run in this exact order:**
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
external-secrets-cert-controller-xxx    1/1   Running
external-secrets-webhook-xxx            1/1   Running
# Main external-secrets pod is completely MISSING
```

**Root Cause:**
IRSA service account for External Secrets was not created. The main controller pod failed to start and wasn't visible in pod list at all.

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
# All columns after AGE are completely empty
```

**Root Cause:**
The External Secrets main controller (Issue 2.2) wasn't running, so nothing could validate or update the ClusterSecretStore status.

**Fix:**
Resolve Issue 2.2 first, then:
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

No issues encountered. All steps worked as expected.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr create-repository --repository-name banking-app --region us-east-1
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
docker build -t banking-app:v1.0.2 .
docker tag banking-app:v1.0.2 ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/banking-app:v1.0.2
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/banking-app:v1.0.2
```

---

## Layer 4 — Application Deployment via Helm

---

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
Helm chart templates for Istio, VPA, and ServiceMonitor had no `{{- if .Values.feature.enabled }}` guards. Since these components weren't installed yet, their CRDs didn't exist.

**Fix — Add if-guards to all affected templates:**
```yaml
# Wrap gateway, virtual-service, destination-rule templates:
{{- if .Values.istio.enabled }}
...
{{- end }}

# Wrap vpa template:
{{- if .Values.vpa.enabled }}
...
{{- end }}
```

Set all flags to `false` in `values-prod.yaml` until the relevant layer is installed:
```yaml
istio:
  enabled: false   # enable after Layer 6
vpa:
  enabled: false   # enable after Layer 14
serviceMonitor:
  enabled: false   # enable after Layer 9
```

> **Key Lesson:** Always run `helm template bankapp ./chart --values values-prod.yaml 2>&1 | grep -iE "error|warning"` as a dry-run before every deploy.

---

### Issue 4.2 — Helm Fails: `namespaces "istio-system" not found`

**Error:**
```
Error: 2 errors occurred:
  * namespaces "banking-prod" already exists
  * namespaces "istio-system" not found
```

**Root Cause:**
`11_ingress.yaml` had `namespace: istio-system` hardcoded. Istio wasn't installed yet so the namespace didn't exist.

**Fix:**
```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: banking-ingress
  namespace: {{ .Values.namespace }}   # was hardcoded as "istio-system"
{{- end }}
```

Set `ingress.enabled: false` in `values-prod.yaml` until Istio is installed. The `banking-prod already exists` error is harmless — remove `--create-namespace` since the namespace already existed.

---

### Issue 4.3 — Invalid Field `allowPrivilegeEscalation` in Pod-level SecurityContext

**Warning:**
```
Warning: unknown field "spec.template.spec.securityContext.allowPrivilegeEscalation"
```

**Root Cause:**
`allowPrivilegeEscalation` is a container-level field, not a pod-level field. Incorrectly placed in `6_rollout.yaml`.

**Fix:**
```yaml
# Pod-level securityContext — remove allowPrivilegeEscalation
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 2000
  seccompProfile:
    type: RuntimeDefault

# Container-level securityContext — keep it here
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
The Rollout referenced an AnalysisTemplate that queries Prometheus. Prometheus wasn't installed yet (Layer 9).

**Fix:**
Remove `prePromotionAnalysis` from `6_rollout.yaml` temporarily:
```yaml
strategy:
  blueGreen:
    activeService: {{ include "banking.fullname" . }}-active
    previewService: {{ include "banking.fullname" . }}-preview
    autoPromotionEnabled: false
    scaleDownDelaySeconds: 60
    # prePromotionAnalysis removed — re-add after Layer 9 (Prometheus)
```

---

### Issue 4.5 — IRSA Role ARN Typo in values-prod.yaml

**Symptom:** Pod starts but AWS API calls fail silently. IRSA role not being assumed.

**Root Cause:**
```yaml
# WRONG — missing :: after iam
eks.amazonaws.com/role-arn: arn:aws:iam:959589242185:role/banking-prod-app-irsa-role

# CORRECT
eks.amazonaws.com/role-arn: arn:aws:iam::959589242185:role/banking-prod-app-irsa-role
#                                       ^^ two colons required
```

**Fix:**
```bash
sed -i 's|arn:aws:iam:959589242185|arn:aws:iam::959589242185|g' \
  k8s-manifests/banking-platform/values-prod.yaml
```

---

### Issue 4.6 — Pod CrashLoopBackOff: DB Connection Timeout

**Crash log:**
```
Caused by: java.net.SocketTimeoutException: Connect timed out
  at com.mysql.cj.protocol.a.NativeSocketConnection.connect
```

**Root Cause:**
The RDS security group allowed port 3306 from the Terraform-managed EKS node SG, but the actual EKS node was using a different SG. Terraform's rule referenced the SG it managed — not the one actually attached to the EC2 node.

**Diagnosis:**
```bash
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier bankapp-prod-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

EKS_NODE_SG=$(aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=<NODE_INTERNAL_IP>" \
  --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --group-ids $RDS_SG \
  --query 'SecurityGroups[0].IpPermissions[*].UserIdGroupPairs[*].GroupId'
# If EKS_NODE_SG is not in this list — that's your problem
```

**Fix:**
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
kubectl run mysql-test \
  --image=mysql:8.0 --restart=Never --rm -it -n banking-prod \
  -- mysql -h <RDS_ENDPOINT> -u <DB_USERNAME> -p<DB_PASSWORD> <DB_NAME> -e "SELECT 1;"
# Must return: 1
```

---

### Issue 4.7 — Network CIDR Too Restrictive in NetworkPolicy

**Symptom:** DB connections still failing from pod even after fixing the AWS security group.

**Root Cause:**
`values-prod.yaml` had `databaseCidr: "10.10.0.0/24"` but RDS was deployed in `10.0.x.x` subnets. The Kubernetes NetworkPolicy was blocking egress to the DB.

**Fix:**
```yaml
network:
  databaseCidr: "10.0.0.0/16"   # was "10.10.0.0/24" — too narrow
```

---

### Issue 4.8 — `actuator/health` Returns Login Page Instead of JSON

**Symptom:**
```bash
curl http://localhost:8080/actuator/health
# Returns HTML login page instead of {"status":"UP"}
```

**Root Cause:**
Spring Security was protecting all endpoints including `/actuator/health`. This is not actually an error — it proves Spring Security is working.

**Verification:**
```bash
kubectl exec $POD -n banking-prod -- \
  wget -qO- http://localhost:8080/actuator/health/liveness
# Returns: {"status":"UP"}
```

**Permanent Fix in `SecurityConfig.java`:**
```java
.authorizeHttpRequests(authz -> authz
    .requestMatchers("/actuator/health/**").permitAll()
    .requestMatchers("/register").permitAll()
    .anyRequest().authenticated()
)
```

---

## Layer 6 — Istio Service Mesh

---

### Issue 6.1 — ArgoCD CLI Permission Denied

**Error:**
```
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied"}
```

**Root Cause:**
ArgoCD CLI was not logged in. The `kubectl apply` succeeded but the `argocd` CLI had no active session.

**Fix:**
```bash
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

kubectl port-forward svc/argocd-server -n argocd 8080:443 &

argocd login localhost:8080 \
  --username admin \
  --password $ARGOCD_PASS \
  --insecure
```

> **Key Lesson:** `PermissionDenied` from ArgoCD CLI is always a session issue. Verify the resource was actually created with `kubectl get application -n argocd`.

---

### Issue 6.2 — Istio Gateway Chart Schema Bug

**Error:**
```
ComparisonError: failed to generate manifest:
Error: values don't meet the specifications of the schema(s) in the following chart(s):
gateway:
- at '': additional properties 'gateways', 'defaults' not allowed
```

**All formats tried and failed:**
```yaml
# ❌ Old operator format
values: |
  gateways:
    istio-ingressgateway:
      enabled: true

# ❌ Direct top-level keys
values: |
  service:
    type: LoadBalancer

# ❌ Chart's own 'defaults' key
values: |
  defaults:
    service:
      type: LoadBalancer

# ❌ Empty values
values: |
  global: {}
```

**Root Cause:**
Istio `gateway` chart version `1.22.0` has a confirmed schema bug — its own `values.schema.json` rejects its own `values.yaml`. Verified:
```bash
helm template test-gateway istio/gateway --version 1.22.0 --dry-run
# Fails even with ZERO custom values — the chart itself is broken
```

**Fix:**
```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm search repo istio/gateway --versions | head -10
# Use 1.26.8 — confirmed working

helm install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --version 1.26.8

# Add NLB annotations
kubectl annotate svc istio-ingressgateway -n istio-system \
  service.beta.kubernetes.io/aws-load-balancer-type="external" \
  service.beta.kubernetes.io/aws-load-balancer-nlb-target-type="instance" \
  service.beta.kubernetes.io/aws-load-balancer-scheme="internet-facing" \
  --overwrite

# Delete the broken ArgoCD app to avoid conflicts
argocd app delete istio-ingressgateway --cascade=false

# Update yaml for future reference
sed -i 's/targetRevision: 1.22.0/targetRevision: 1.26.8/' \
  k8s-manifests/argocd-infra/networking/2_istio-gateway.yaml
```

> **Key Lesson:** When an ArgoCD app shows `ComparisonError`, test the chart locally with `helm template --dry-run` first. If it fails with zero custom values, the chart is broken — not your config.

---

### Issue 6.3 — Istio Gateway Chart Version Not Found in Repo

**Error:**
```
Error: chart "gateway" version "1.22.0" not found in repo
```

**Root Cause:**
Istio 1.22.x charts are no longer published. Helm repos regularly drop old versions.

**Diagnosis:**
```bash
helm search repo istio/gateway --versions | head -10
# 1.22.x does not appear — only 1.26.x and newer exist
```

**Fix:** Use version `1.26.8` as shown in Issue 6.2.

> **Key Lesson:** Always run `helm search repo <chart> --versions` before committing a version to yaml files.

---

### Issue 6.4 — Istio Sidecar Not Injecting into Pods

**Symptom:**
```bash
kubectl get pods -n banking-prod
# Shows 1/1 Running — expected 2/2 (app + istio-proxy sidecar)
```

**Root Cause:**
The banking app pod was created before Istio was installed. The `istio-sidecar-injector` MutatingWebhook only injects into new pods — existing pods are never patched.

**Fix:**
```bash
# Verify namespace has the injection label
kubectl get namespace banking-prod --show-labels | grep istio-injection
# If missing:
kubectl label namespace banking-prod istio-injection=enabled --overwrite

# Restart rollout to force new pod creation
kubectl argo rollouts restart bankapp-banking-platform -n banking-prod
sleep 30
kubectl get pods -n banking-prod -w
```

**Verification:**
```bash
kubectl get pod $(kubectl get pods -n banking-prod -o name | head -1 | cut -d/ -f2) \
  -n banking-prod -o jsonpath='{.spec.containers[*].name}'
# Expected: banking-api istio-proxy
```

---

### Issue 6.5 — Gateway and VirtualService Not Created

**Symptom:**
```bash
kubectl get gateway -n banking-prod       # No resources found
kubectl get virtualservice -n banking-prod # No resources found
```

**Root Cause:**
Templates had `{{- if .Values.istio.enabled }}` guards and this value was `false` in deployed values — resources were silently skipped.

**Diagnosis:**
```bash
helm get values bankapp -n banking-prod | grep -A3 istio
# istio:
#   enabled: false   ← silently skipped Gateway and VirtualService
```

**Fix:**
```bash
CERT_ARN=$(aws acm list-certificates --region us-east-1 \
  --query 'CertificateSummaryList[0].CertificateArn' --output text)

helm upgrade bankapp ./k8s-manifests/banking-platform \
  --namespace banking-prod \
  --values ./k8s-manifests/banking-platform/values-prod.yaml \
  --set ingress.enabled=true \
  --set ingress.host="api.rohandevops.co.in" \
  --set ingress.certificateArn="$CERT_ARN" \
  --set istio.enabled=true \
  --set istio.host="api.rohandevops.co.in"
```

> **Key Lesson:** Always check `helm get values <release> -n <namespace>` after deployment. Conditional templates silently skip creation when flags are false — there is no error or warning.

---

## Layer 7 — Kyverno Policy Engine

---

### Issue 7.1 — Helm Install Conflict with ArgoCD Managed Kyverno

**Error:**
```
Error: INSTALLATION FAILED: Unable to continue with install:
ServiceAccount "kyverno-admission-controller" in namespace "kyverno" exists
and cannot be imported into the current release:
annotation validation error: missing key "meta.helm.sh/release-name"
```

**Root Cause:**
Applied the ArgoCD Application manifest, then also ran `helm install` manually. ArgoCD immediately starts installing Kyverno when you apply the Application resource. Running `helm install` on top created an ownership conflict.

**Fix:**
```bash
# CORRECT — ArgoCD only
kubectl apply -f k8s-manifests/argocd-infra/governance/1_kyverno.yaml

# Wait and monitor — ArgoCD handles everything
argocd app get kyverno
kubectl get pods -n kyverno -w
```

> **Key Lesson — Golden Rule:** If ArgoCD is managing a component, NEVER run `helm install` for the same component. ArgoCD IS the Helm installer.

---

### Issue 7.2 — Kyverno Pods Pending: Insufficient CPU

**Symptom:**
```bash
kubectl get pods -n kyverno
# All 4 Kyverno pods: 0/1 Pending
```

**Diagnosis:**
```bash
kubectl describe pod -n kyverno \
  $(kubectl get pods -n kyverno -o name | head -1 | cut -d/ -f2) | grep -A5 "Events:"
# Warning: FailedScheduling — 0/1 nodes available: 1 Insufficient cpu
```

**Root Cause:**
Only 1 node in the cluster, already saturated with ArgoCD, External Secrets, banking app, and Istio.

**Fix:**
```bash
aws eks update-nodegroup-config \
  --cluster-name bankapp-prod-eks \
  --nodegroup-name general-purpose \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --region us-east-1

kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get pods -n kyverno -w
```

---

### Issue 7.3 — Stale CronJob Pod Showing ImagePullBackOff

**Symptom:**
```bash
kubectl get pods -n kyverno
# kyverno-clean-reports-svhwz    0/1   ImagePullBackOff
# All 4 main Kyverno pods: 1/1 Running
```

**Root Cause:**
`kyverno-clean-reports-xxxxx` is a one-time CronJob pod — not one of the 4 main controller pods. Its failure has zero impact on policy enforcement.

**Fix:**
```bash
kubectl delete pod kyverno-clean-reports-svhwz -n kyverno
kubectl get pods -n kyverno | grep -v clean-reports
```

> **Key Lesson:** Not every failing pod is a real problem. Always identify whether a failing pod is a core controller or a one-time background job.

---

## Layer 8 — Karpenter Autoscaler

---

### Issue 8.1 — Chart Version Not Found in Repo

**Error:**
```
Error: chart "karpenter" version "0.37.0" not found in https://charts.karpenter.sh repository
```

**Root Cause:**
`charts.karpenter.sh` only has versions up to `0.16.3` using old `v1alpha5` CRDs. Version `0.37.0` never existed there. Modern Karpenter (1.x) moved to OCI registry.

**Fix:**
```bash
CLUSTER_NAME="bankapp-prod-eks"
AWS_REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_ENDPOINT=$(aws eks describe-cluster \
  --name $CLUSTER_NAME --region $AWS_REGION \
  --query "cluster.endpoint" --output text)

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

argocd app delete karpenter --cascade=false
```

> **Key Lesson:** Karpenter 1.x is OCI-only. Use `oci://public.ecr.aws/karpenter/karpenter`. Never reference `charts.karpenter.sh` for versions above 0.16.x.

---

### Issue 8.2 — Kyverno Blocking Karpenter Helm Install

**Error:**
```
Error: INSTALLATION FAILED:
admission webhook "validate.kyverno.svc-fail" denied the request:
banking-guardrails:
  autogen-disallow-root-user: 'validation error: Running as root is forbidden.
    rule failed at path /spec/template/spec/securityContext/runAsNonRoot/'
```

**Root Cause:**
`banking-guardrails` ClusterPolicy in `Enforce` mode blocked Karpenter's Deployment because its Helm chart doesn't explicitly set `runAsNonRoot: true`.

**Fix:**
```bash
# Step 1 — Switch to Audit
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Audit"}]'

# Step 2 — Install Karpenter
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 --namespace karpenter --create-namespace \
  --set "settings.clusterName=$CLUSTER_NAME" \
  --set "settings.clusterEndpoint=$CLUSTER_ENDPOINT" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT_ID}:role/bankapp-karpenter-controller-irsa" \
  --wait

# Step 3 — Restore Enforce IMMEDIATELY
kubectl patch clusterpolicy banking-guardrails \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/validationFailureAction", "value": "Enforce"}]'

kubectl get clusterpolicy   # Verify: shows Enforce
```

---

### Issue 8.3 — Helm Cannot Reuse Release Name

**Error:**
```
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
```

**Root Cause:**
A previous failed Helm install left a release in `failed` state, blocking reinstall.

**Fix:**
```bash
helm list -n karpenter   # Shows: failed
helm uninstall karpenter -n karpenter
helm list -n karpenter   # Verify empty
# Now install fresh
```

---

### Issue 8.4 — IRSA AccessDenied: Wrong Service Account Name in Trust Policy

**Error:**
```json
{
  "error": "operation error STS: AssumeRoleWithWebIdentity,
    api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"
}
```

**Root Cause:**
Trust policy had `system:serviceaccount:karpenter:karpenter-sa` but Helm creates a service account named `karpenter` (no `-sa` suffix).

**Diagnosis:**
```bash
aws iam get-role --role-name bankapp-karpenter-controller-irsa \
  --query "Role.AssumeRolePolicyDocument" --output json
# Found: "system:serviceaccount:karpenter:karpenter-sa"  ← WRONG

kubectl get sa -n karpenter
# karpenter   ← actual name, no "-sa"
```

**Fix:**
```bash
OIDC_URL=$(aws eks describe-cluster \
  --name bankapp-prod-eks --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

cat > /tmp/karpenter-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_URL}:aud": "sts.amazonaws.com",
        "${OIDC_URL}:sub": "system:serviceaccount:karpenter:karpenter"
      }
    }
  }]
}
EOF

aws iam update-assume-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-document file:///tmp/karpenter-trust-policy.json

kubectl rollout restart deployment/karpenter -n karpenter
```

---

### Issue 8.5 — CRD API Version Mismatch (v1beta1 vs v1)

**Error:**
```
error: no matches for kind "EC2NodeClass" in version "karpenter.k8s.aws/v1beta1"
error: no matches for kind "NodePool" in version "karpenter.sh/v1beta1"
```

**Root Cause:**
Manifests written for Karpenter 0.x (`v1beta1`). Karpenter 1.x promoted to `v1`.

**Fix:**
```bash
sed -i 's|karpenter.k8s.aws/v1beta1|karpenter.k8s.aws/v1|g' \
  k8s-manifests/argocd-infra/governance/4_karpenter-nodeclass.yaml

sed -i 's|karpenter.sh/v1beta1|karpenter.sh/v1|g' \
  k8s-manifests/argocd-infra/governance/5_karpenter-nodepool.yaml
```

---

### Issue 8.6 — NodePool v1 Schema Breaking Changes

**Error:**
```
The NodePool "default" is invalid:
* spec.disruption.expireAfter: unknown field
* spec.disruption.consolidationPolicy: Unsupported value: "WhenUnderutilized"
```

**Root Cause:**
Karpenter v1 moved `expireAfter` and renamed `WhenUnderutilized`.

**Fix — Correct NodePool manifest:**
```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      expireAfter: 720h    # MOVED here from spec.disruption.expireAfter
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

---

### Issue 8.7 — Missing IAM Permissions (eks:DescribeCluster, iam:GetInstanceProfile)

**Error:**
```json
{
  "error": "operation error IAM: GetInstanceProfile, StatusCode: 403, AccessDenied",
  "error": "operation error EKS: DescribeCluster, StatusCode: 403, AccessDeniedException"
}
```

**Root Cause:**
Terraform-created IAM policy was missing permissions required by Karpenter 1.x for managing EC2 instance profiles dynamically.

**Fix:**
```bash
aws iam put-role-policy \
  --role-name bankapp-karpenter-controller-irsa \
  --policy-name karpenter-extra-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
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
    }]
  }'

kubectl rollout restart deployment/karpenter -n karpenter
```

---

### Issue 8.8 — Wrong Node Role Name in EC2NodeClass

**Error:**
```json
{
  "error": "operation error IAM: AddRoleToInstanceProfile, StatusCode: 404,
    NoSuchEntity: The role with name bankapp-karpenter-node-role cannot be found."
}
```

**Fix:**
```bash
# Find the correct role name
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'karpenter') || contains(RoleName, 'node')].RoleName" \
  --output table
```

Update EC2NodeClass:
```yaml
spec:
  role: "bankapp-prod-karpenter-node-role"   # was "bankapp-karpenter-node-role"
```

---

### Issue 8.9 — EC2NodeClass `spec.role` Field is Immutable

**Error:**
```
The EC2NodeClass "default" is invalid:
  spec.role: Invalid value: "string": immutable field changed
```

**Fix:**
```bash
kubectl delete ec2nodeclass default
kubectl apply -f k8s-manifests/argocd-infra/governance/4_karpenter-nodeclass.yaml
```

---

### Issue 8.10 — Stale Instance Profile in IAM

**Symptom:** Same EC2NodeClass error persisted even after recreating with correct role.

**Root Cause:**
First failed creation left an orphaned instance profile in IAM. Karpenter tried to reuse it but couldn't attach the correct role.

**Fix:**
```bash
aws iam delete-instance-profile \
  --instance-profile-name bankapp-prod-eks_15843455441266977890

kubectl rollout restart deployment/karpenter -n karpenter
```

---

### Issue 8.11 — Stale Pod Not Picking Up New IAM Permissions

**Symptom:** Logs still showed old errors after updating IAM and running `kubectl rollout restart`. Pod age showed `45m`.

**Root Cause:**
`kubectl rollout restart` wasn't replacing the old pod because the deployment was in an inconsistent state from a cancelled `--wait` install.

**Fix:**
```bash
kubectl delete pod -n karpenter --all
kubectl get pods -n karpenter -w
```

> **Key Lesson:** After IAM changes, verify new pods are actually running by checking pod age. Old pod = old IRSA token = old IAM session.

---

## Velero + MinIO Setup Issues

---

### Problem V1 — MinIO Pod Stuck / Failing to Start via ArgoCD

**Symptom:** MinIO pod in `Pending` or `Error` after ArgoCD sync.

**Root Cause:** ArgoCD couldn't sync MinIO Helm chart from `charts.min.io`; leftover PVCs and secrets from failed installs also blocked re-deployment.

**Fix:**
```bash
argocd app delete minio --yes
kubectl delete all --all -n velero
kubectl delete pvc --all -n velero

# Deploy MinIO as a plain Deployment (bypassing Helm/ArgoCD)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: velero
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args: ["server", "/data", "--console-address", ":9001"]
        env:
        - name: MINIO_ROOT_USER
          value: rohan-admin
        - name: MINIO_ROOT_PASSWORD
          value: secure-storage-pass
        ports:
        - containerPort: 9000
        - containerPort: 9001
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: velero
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 9001
    targetPort: 9001
EOF
```

---

### Problem V2 — Velero `upgrade-crds` Job Stuck with Finalizers

**Symptom:** `helm install velero` hung; `velero-upgrade-crds` job stuck forever.

**Fix:**
```bash
# Force delete the stuck job
kubectl delete job velero-upgrade-crds -n velero --force --grace-period=0

# Remove finalizers
kubectl patch job velero-upgrade-crds -n velero \
  --type=json \
  -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true

# Force delete stuck pods
for pod in $(kubectl get pods -n velero --no-headers | awk '{print $1}'); do
  kubectl patch pod $pod -n velero \
    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
done

# Nuclear option — delete via raw API
kubectl proxy &
sleep 2
curl -k -X DELETE \
  "http://localhost:8001/apis/batch/v1/namespaces/velero/jobs/velero-upgrade-crds" \
  -H "Content-Type: application/json" \
  -d '{"kind":"DeleteOptions","apiVersion":"v1","gracePeriodSeconds":0,"propagationPolicy":"Foreground"}'
kill %1

kubectl get jobs -n velero   # Verify clean
```

---

### Problem V3 — Velero BackupStorageLocation Showing `Unavailable`

**Symptom:** `velero backup-location get` showed `Unavailable` even after Velero pod was Running.

**Root Cause:** The `velero-backups` bucket didn't exist in MinIO.

**Fix:**
```bash
kubectl exec -n velero deployment/minio -- \
  /bin/sh -c "mc alias set local http://localhost:9000 rohan-admin secure-storage-pass && mc mb local/velero-backups"

sleep 60
velero backup-location get
# Expected: default   aws   velero-backups   Available
```

**Alternative — Use a temporary AWS CLI pod:**
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: mc-temp
  namespace: velero
spec:
  restartPolicy: Never
  containers:
  - name: aws-cli
    image: amazon/aws-cli
    command: ["aws","s3","mb","s3://velero-backups","--endpoint-url","http://minio.velero.svc.cluster.local:9000","--region","us-east-1"]
    env:
    - name: AWS_ACCESS_KEY_ID
      value: "rohan-admin"
    - name: AWS_SECRET_ACCESS_KEY
      value: "secure-storage-pass"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
EOF
sleep 15
kubectl logs mc-temp -n velero
kubectl delete pod mc-temp -n velero
```

---

### Problem V4 — Helm Release in Stuck `failed` / `pending-install` State

**Fix:**
```bash
helm list -n velero --all
kubectl delete secret -n velero -l owner=helm,name=velero
helm list -n velero --all   # Verify gone

helm install velero vmware-tanzu/velero --namespace velero --version 11.4.0 --no-hooks \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=velero-backups \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set configuration.backupStorageLocation[0].config.s3ForcePathStyle=true \
  --set "configuration.backupStorageLocation[0].config.s3Url=http://minio.velero.svc.cluster.local:9000" \
  --set credentials.useSecret=true \
  --set credentials.existingSecret=velero-minio-secret \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins
```

---

## ArgoCD Sync Errors (OutOfSync / SyncError)

---

### Problem A1 — Kyverno SyncError: `migrate-resources` ClusterRole Conflict

**Root Cause:** Leftover ClusterRole/ClusterRoleBinding from a previous Kyverno version blocking sync.

**Fix:**
```bash
kubectl delete clusterrole kyverno:migrate-resources --ignore-not-found
kubectl delete clusterrolebinding kyverno:migrate-resources --ignore-not-found

cat > /tmp/kyverno-patch.json << 'EOF'
{
  "spec": {
    "ignoreDifferences": [
      {"group": "rbac.authorization.k8s.io", "kind": "ClusterRole", "name": "kyverno:migrate-resources"},
      {"group": "rbac.authorization.k8s.io", "kind": "ClusterRoleBinding", "name": "kyverno:migrate-resources"},
      {"group": "apiextensions.k8s.io", "kind": "CustomResourceDefinition",
       "jqPathExpressions": [".spec.conversion",".spec.preserveUnknownFields",".spec.versions",".status"]}
    ],
    "syncPolicy": {
      "syncOptions": ["CreateNamespace=true","ServerSideApply=true","RespectIgnoreDifferences=true"]
    }
  }
}
EOF
kubectl patch application kyverno -n argocd --type merge --patch-file /tmp/kyverno-patch.json

argocd app sync kyverno --server-side --prune
sleep 30
argocd app get kyverno | grep -E "Sync Status|Health Status"
```

> **Permanent fix:** Commit `ignoreDifferences` and `ServerSideApply=true` to `policy/1_kyverno.yaml` in Git.

---

### Problem A2 — istio-base / istiod OutOfSync: Webhook Drift

**Root Cause:** Kubernetes mutates `ValidatingWebhookConfiguration` at runtime (adds caBundle), causing constant drift vs. Git.

**Fix:**
```bash
cat > /tmp/istio-patch.json << 'EOF'
{
  "spec": {
    "ignoreDifferences": [{
      "group": "admissionregistration.k8s.io",
      "kind": "ValidatingWebhookConfiguration",
      "jsonPointers": ["/webhooks"]
    }]
  }
}
EOF
kubectl patch application istio-base -n argocd --type merge --patch-file /tmp/istio-patch.json
kubectl patch application istiod -n argocd --type merge --patch-file /tmp/istio-patch.json

argocd app sync istio-base --server-side --prune
argocd app sync istiod --server-side --prune
```

---

### Problem A3 — vpa-stack OutOfSync: Self-Referencing Application Object

**Root Cause:** Git path contained an `Application` manifest that referenced itself, causing permanent drift.

**Fix:**
```bash
cat > /tmp/vpa-fix.json << 'EOF'
{
  "spec": {
    "ignoreDifferences": [
      {"group": "argoproj.io", "kind": "Application", "name": "vpa-stack",
       "namespace": "argocd", "jsonPointers": ["/spec"]},
      {"group": "admissionregistration.k8s.io", "kind": "MutatingWebhookConfiguration",
       "name": "vpa-webhook-config", "jsonPointers": ["/webhooks/0/clientConfig/caBundle"]}
    ],
    "syncPolicy": {
      "syncOptions": ["CreateNamespace=true","ServerSideApply=true","RespectIgnoreDifferences=true"]
    }
  }
}
EOF
kubectl patch application vpa-stack -n argocd --type merge --patch-file /tmp/vpa-fix.json
argocd app sync vpa-stack --server-side --prune
```

---

### Problem A4 — Velero OutOfSync: CRD Schema Drift

**Fix:**
```bash
cat > /tmp/velero-patch.json << 'EOF'
{
  "spec": {
    "ignoreDifferences": [
      {"group": "apiextensions.k8s.io", "kind": "CustomResourceDefinition",
       "jqPathExpressions": [".spec.conversion",".spec.preserveUnknownFields",".spec.versions",".status"]},
      {"group": "velero.io", "kind": "BackupStorageLocation",
       "jqPathExpressions": [".spec.accessMode",".status"]}
    ],
    "syncPolicy": {
      "syncOptions": ["CreateNamespace=true","ServerSideApply=true","RespectIgnoreDifferences=true"]
    }
  }
}
EOF
kubectl patch application velero -n argocd --type merge --patch-file /tmp/velero-patch.json

argocd app terminate-op velero 2>/dev/null || true
sleep 5
argocd app sync velero --server-side --prune
```

---

### Problem A5 — tempo-stack OutOfSync: StatefulSet volumeClaimTemplates

**Root Cause:** Kubernetes adds immutable defaults to `volumeClaimTemplates` after creation; ArgoCD sees it as a diff.

**Fix:**
```bash
cat > /tmp/tempo-patch.json << 'EOF'
{
  "spec": {
    "ignoreDifferences": [{
      "group": "apps",
      "kind": "StatefulSet",
      "jsonPointers": ["/spec/volumeClaimTemplates"]
    }]
  }
}
EOF
kubectl patch application tempo-stack -n argocd --type merge --patch-file /tmp/tempo-patch.json
argocd app sync tempo-stack --server-side --prune
```

---

## Jenkins Installation & Port Conflicts

---

### Problem J1 — Jenkins Failing to Start (Port 8080 Already in Use)

**Diagnosis:**
```bash
sudo lsof -i :8080
# Found: kubectl port-forward process occupying the port
```

**Fix — Option A: Kill the conflicting process**
```bash
sudo lsof -ti:8080 | xargs kill -9 2>/dev/null || true
pkill -f "kubectl port-forward"
sudo systemctl start jenkins
```

**Fix — Option B: Change Jenkins port**
```bash
sudo sed -i 's/^HTTP_PORT=.*/HTTP_PORT=8081/' /etc/default/jenkins
sudo systemctl daemon-reload
sudo systemctl restart jenkins
```

---

### Problem J2 — Jenkins systemd Service in `failed` State

**Fix:**
```bash
# Full clean purge
sudo systemctl stop jenkins
sudo apt purge -y jenkins
sudo rm -rf /var/lib/jenkins /var/log/jenkins /var/cache/jenkins
sudo apt autoremove -y

# Fresh install
sudo apt update && sudo apt install -y fontconfig openjdk-21-jre
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/" | \
  sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install -y jenkins

sudo systemctl reset-failed jenkins
sudo systemctl daemon-reload
sudo systemctl start jenkins
sudo systemctl enable jenkins

sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

---

### Problem J3 — Jenkins User Can't Run docker / kubectl / aws

**Fix:**
```bash
# Docker access
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# kubectl access
sudo mkdir -p /var/lib/jenkins/.kube
sudo cp ~/.kube/config /var/lib/jenkins/.kube/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube

# AWS CLI access
sudo mkdir -p /var/lib/jenkins/.aws
sudo cp ~/.aws/credentials /var/lib/jenkins/.aws/credentials
sudo cp ~/.aws/config /var/lib/jenkins/.aws/config
sudo chown -R jenkins:jenkins /var/lib/jenkins/.aws

# Verify all three
sudo -u jenkins docker ps
sudo -u jenkins kubectl get nodes
sudo -u jenkins aws sts get-caller-identity
```

---

## SonarQube Deployment Issues

---

### Problem S1 — SonarQube Helm Install Failing: Leftover Secrets/ConfigMaps

**Fix:**
```bash
kubectl delete all --all -n devsecops
kubectl delete pvc --all -n devsecops
kubectl delete secret --all -n devsecops
kubectl delete configmap --all -n devsecops
kubectl delete serviceaccount --all -n devsecops 2>/dev/null || true
sleep 10

# Verify namespace is clean
kubectl get all -n devsecops

# Fresh install
helm repo add sonarqube https://sonarsource.github.io/helm-chart-sonarqube
helm repo update
helm install sonarqube sonarqube/sonarqube \
  -n devsecops --create-namespace \
  --set community.enabled=true \
  --set monitoringPasscode="define_it_yourself" \
  --set postgresql.enabled=true \
  --set postgresql.postgresqlPassword="rohan-secure-pass" \
  --set postgresql.persistence.size=20Gi \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set resources.requests.memory=2Gi \
  --set resources.requests.cpu=1 \
  --set resources.limits.memory=4Gi \
  --set resources.limits.cpu=2 \
  --timeout 10m

kubectl get pods -n devsecops -w
```

---

### Problem S2 — Kyverno Blocking SonarQube / devsecops Namespace

**Fix:**
```bash
kubectl patch clusterpolicy banking-guardrails --type=json -p='[
  {"op":"add","path":"/spec/rules/1/exclude/any/-","value":{"resources":{"namespaces":["devsecops"]}}}
]'

kubectl get clusterpolicy banking-guardrails -o yaml | grep -A5 "exclude"
```

---

## Istio / TLS / DNS Issues (Post-Deploy)

---

### Problem I1 — `https://api.rohandevops.co.in` Returning Connection Refused

**Diagnosis:**
```bash
kubectl get certificate -n istio-system
kubectl describe certificate banking-tls-cert -n istio-system | grep -A20 "Events|Status"
kubectl get challenges -n istio-system

NLB=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "NLB: $NLB"
```

**Fix:**
```bash
# Update Route53 to point to NLB
ZONE_ID="Z06055482R7Q707WBFMFN"
NLB_ZONE_ID="Z26RNL4JYFTOTI"
NLB_HOSTNAME="k8s-istiosys-istioing-4e0a2a00ba-224d2b64b7613a1c.elb.us-east-1.amazonaws.com"

aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch "{
    \"Changes\": [{\"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"api.rohandevops.co.in\", \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$NLB_ZONE_ID\",
          \"DNSName\": \"$NLB_HOSTNAME\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }"

# Delete stuck ACME challenges and re-issue cert
kubectl delete challenge --all -n istio-system
kubectl delete certificate banking-tls-cert -n istio-system
kubectl delete certificaterequest --all -n istio-system
sleep 10
kubectl apply -f service-mesh/networking/6_tls_cert.yaml

sleep 60
kubectl get certificate -n istio-system
```

---

### Problem I2 — VirtualService Routing to Wrong Service (404 from Istio)

**Root Cause:** After ArgoCD ApplicationSet renamed the Helm release, service name changed from `bankapp-banking-platform-active` to `prod-banking-platform-banking-platform-active`.

**Fix:**
```bash
kubectl patch virtualservice banking-vs -n banking-prod --type=merge -p '{
  "spec": {
    "http": [{
      "route": [{
        "destination": {
          "host": "prod-banking-platform-banking-platform-active.banking-prod.svc.cluster.local",
          "port": {"number": 80}
        }
      }]
    }]
  }
}'

# Fix in Git to prevent ArgoCD from reverting
sed -i 's/bankapp-banking-platform-active/prod-banking-platform-banking-platform-active/g' \
  service-mesh/networking/5_gateway-vs.yaml

git add service-mesh/networking/5_gateway-vs.yaml
git commit -m "fix: update VirtualService host to prod-banking-platform service name"
git push origin main
```

---

## Kyverno Policy Conflicts (Post-Deploy)

---

### Problem K1 — Pods Blocked by `banking-guardrails` ClusterPolicy

**Fix — Add namespace exceptions:**
```bash
# velero exception
kubectl patch clusterpolicy banking-guardrails --type=json -p='[
  {"op":"add","path":"/spec/rules/1/exclude/any/-","value":{"resources":{"namespaces":["velero"]}}}
]'

# devsecops exception
kubectl patch clusterpolicy banking-guardrails --type=json -p='[
  {"op":"add","path":"/spec/rules/1/exclude/any/-","value":{"resources":{"namespaces":["devsecops"]}}}
]'
```

---

### Problem K2 — Kyverno Admission Controller Accidentally Deleted

**Fix:**
```bash
kubectl annotate application kyverno -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl get pods -n kyverno -w
```

---

## Karpenter Node Provisioning (Post-Deploy)

---

### Problem KP1 — Test Pod Stuck in Pending, No Node Provisioned

**Root Cause:** Kyverno policy blocked the pod (missing `runAsNonRoot`). Once fixed, NodePool instance types were too restrictive.

**Fix — Step 1: Compliant pod spec**
```bash
kubectl run karpenter-test --image=busybox \
  --overrides='{
    "spec":{
      "securityContext":{"runAsNonRoot":true,"runAsUser":1000},
      "containers":[{
        "name":"karpenter-test",
        "image":"busybox",
        "resources":{"requests":{"cpu":"1"}},
        "args":["sleep","3600"],
        "securityContext":{"runAsNonRoot":true,"runAsUser":1000}
      }]
    }
  }'
```

**Fix — Step 2: Expand NodePool instance types**
```bash
kubectl patch nodepool default --type=merge -p '{
  "spec": {
    "template": {
      "spec": {
        "requirements": [
          {"key": "karpenter.sh/capacity-type", "operator": "In", "values": ["on-demand"]},
          {"key": "node.kubernetes.io/instance-type", "operator": "In",
           "values": ["c7i-flex.large", "m7i-flex.large"]}
        ]
      }
    }
  }
}'

kubectl delete nodeclaim default-hphxg
kubectl get nodes -w
```

---

## Observability Stack (OTel / Tempo / Grafana / Kiali)

---

### Problem O1 — App Traces Not Reaching Tempo (OTel Endpoint Misconfigured)

**Diagnosis:**
```bash
kubectl exec -n banking-prod \
  $(kubectl get pod -n banking-prod -l app=bankapp-banking-platform -o jsonpath='{.items[0].metadata.name}') \
  -c banking-api -- env | grep OTEL_EXPORTER

kubectl logs -n monitoring \
  -l app.kubernetes.io/name=opentelemetry-collector \
  --tail=20 | grep -i "error\|grpc\|415"
```

**Fix:**
```bash
# Set correct gRPC endpoint
kubectl patch rollout bankapp-banking-platform -n banking-prod --type=json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env/1/value",
   "value": "http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317"}
]'

# Fix HTTP 415 errors by explicitly setting gRPC protocol
kubectl patch rollout bankapp-banking-platform -n banking-prod --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-",
   "value": {"name": "OTEL_EXPORTER_OTLP_PROTOCOL", "value": "grpc"}}
]'

kubectl get pods -n banking-prod -w
```

---

### Problem O2 — Grafana Showing Duplicate/Stale Pods

**Fix:**
```bash
kubectl get replicaset -n monitoring | grep grafana
kubectl scale replicaset kube-prometheus-stack-grafana-5c494c7d9 -n monitoring --replicas=0
# Or force delete:
kubectl delete replicaset kube-prometheus-stack-grafana-5c494c7d9 -n monitoring --force --grace-period=0
kubectl get pods -n monitoring | grep grafana
```

---

### Problem O3 — Tempo Datasource Not Loading in Grafana (ConfigMap Approach Failing)

**Root Cause:** ConfigMap-based provisioning had YAML formatting errors and Grafana sidecar label selector wasn't matching.

**Fix — Add directly via Grafana API:**
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
sleep 3

kubectl delete configmap tempo-datasource -n monitoring 2>/dev/null || true

curl -X POST http://admin:prom-operator@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Tempo",
    "type": "tempo",
    "url": "http://tempo-stack.monitoring.svc.cluster.local:3100",
    "access": "proxy",
    "isDefault": false,
    "jsonData": {
      "nodeGraph": {"enabled": true},
      "lokiSearch": {"datasourceUid": "loki"},
      "serviceMap": {"datasourceUid": "prometheus"}
    }
  }'

# Verify
curl -s http://admin:prom-operator@localhost:3000/api/datasources | \
  python3 -m json.tool | grep '"name"'
# Expected: Alertmanager, Loki, Prometheus, Tempo
```

---

### Problem O4 — Kiali Not Showing Service Graph

**Root Cause:** Kiali ConfigMap had wrong Prometheus URL — couldn't pull Istio metrics.

**Fix:**
```bash
kubectl patch application kiali-server -n argocd --type=merge -p '{
  "spec": {
    "source": {
      "helm": {
        "values": "auth:\n  strategy: anonymous\nexternal_services:\n  prometheus:\n    url: \"http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090\"\n  grafana:\n    enabled: true\n    url: \"http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80\"\n  tracing:\n    enabled: true\n    url: \"http://tempo-stack.monitoring.svc.cluster.local:3100\"\n"
      }
    }
  }
}'

kubectl annotate application kiali-server -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
sleep 30
kubectl rollout restart deployment kiali -n istio-system
```

---

## ResourceQuota Blocking Pod Scheduling

---

### Problem R1 — Velero Pods Stuck in Pending Due to Quota Exhaustion

**Diagnosis:**
```bash
kubectl describe resourcequota velero-resource-quota -n velero
kubectl get pods -n velero | grep minio
```

**Fix:**
```bash
kubectl scale statefulset minio -n velero --replicas=1  # if StatefulSet
kubectl delete resourcequota velero-resource-quota -n velero

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: velero-resource-quota
  namespace: velero
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
EOF

kubectl rollout restart deployment velero -n velero
kubectl get pods -n velero -w
```

---

## Velero Backup Verification & Restore

### End-to-End Backup Chain Verification

```bash
# 1. Check backup location is Available
velero backup-location get
# Expected: default   aws   velero-backups   Available

# 2. Check schedule exists
velero schedule get
# Expected: banking-prod-daily-backup   0 */6 * * *   Enabled

# 3. Create a test backup
velero backup create test-backup \
  --include-namespaces banking-prod \
  --wait

# 4. Verify backup completed
velero backup get
# Expected: test-backup   Completed

# 5. Verify files exist in MinIO
kubectl exec -n velero deployment/minio -- \
  sh -c "mc alias set local http://localhost:9000 rohan-admin secure-storage-pass && \
         mc ls local/velero-backups/backups/"

# 6. Test restore
velero restore create --from-backup test-backup
watch velero restore get

# 7. Check restore logs if issues
velero restore logs <restore-name>

# 8. Cleanup test backups
velero backup delete test-backup --confirm
```

---

## Golden Rules Learned

1. **Bootstrap before main Terraform.** S3 and DynamoDB must exist before `terraform init`.

2. **ArgoCD manages Helm — never run both.** If ArgoCD deploys a chart, NEVER also run `helm install` for it. ArgoCD IS the Helm installer.

3. **Test chart versions before committing.** Run `helm search repo <chart> --versions` and `helm template --dry-run` before writing any version to yaml.

4. **Broken charts fail with no values.** If `helm template --dry-run` fails with zero custom values, the chart is broken — stop fixing your values and find a working version.

5. **IRSA trust policy SA name must match exactly.** Format: `system:serviceaccount:<namespace>:<sa-name>`. Verify with `kubectl get sa -n <namespace>` before writing the trust policy.

6. **IRSA ARN has two colons after `iam`.** Always: `arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>`.

7. **Kyverno Enforce blocks everything** — including infra tools. Switch to Audit for installs, then immediately restore Enforce.

8. **Scale nodes before heavy components.** Always check capacity before Kyverno, Prometheus, or Loki.

9. **Pod restarts required after Istio install.** Sidecar injection is a create-time webhook only.

10. **Failed Helm installs leave broken releases.** Always `helm uninstall` before retrying. Check `helm list -n <namespace>` first.

11. **Modern Karpenter lives on OCI registry.** Use `oci://public.ecr.aws/karpenter/karpenter` — not `charts.karpenter.sh`.

12. **Check `helm get values` after deployment.** Conditional templates silently skip resources when flags are false.

13. **After IAM changes, check pod age.** New pods = new IRSA session. Old pod age = stale IAM session.

14. **Kubernetes mutates webhook configs at runtime.** Use `ignoreDifferences` in ArgoCD for `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` to stop constant OutOfSync on Istio/VPA/Kyverno apps.

15. **Always verify exact IAM role names.** Use `aws iam list-roles` — never guess names in manifests.

---

## Quick Reference — All Issues

| # | Layer | Issue | Root Cause | Fix |
|---|-------|-------|------------|-----|
| 1.1 | Terraform | KMS key not found | Key didn't exist before bootstrap | Create KMS key manually first |
| 1.2 | Terraform | Route53 zone not found | Hosted zone didn't exist | Create zone + update registrar nameservers |
| 1.3 | Terraform | RDS secret not found | Secret didn't exist before apply | Create secret in Secrets Manager first |
| 1.4 | Terraform | db_name = master username | Same key used for both fields | Use separate `db_username` and `db_name` |
| 2.1 | EKS Add-ons | ALB controller missing | IRSA SA not created before Helm | Create IRSA SA first, `serviceAccount.create=false` |
| 2.2 | EKS Add-ons | External Secrets main pod missing | IRSA SA not created | Create IRSA SA, rollout restart |
| 2.3 | EKS Add-ons | ClusterSecretStore empty status | Main controller not running | Fix 2.2 first, recreate ClusterSecretStore |
| 4.1 | Helm App | CRD not found | Unconditional templates, CRDs not installed | Add `{{- if .Values.x.enabled }}` guards |
| 4.2 | Helm App | istio-system namespace not found | Hardcoded namespace in template | Use `{{ .Values.namespace }}`, `ingress.enabled=false` |
| 4.3 | Helm App | Unknown field warning | `allowPrivilegeEscalation` at pod level | Move to container-level securityContext |
| 4.4 | Helm App | AnalysisTemplate not found | Prometheus not installed yet | Remove `prePromotionAnalysis` temporarily |
| 4.5 | Helm App | IRSA not assuming role | ARN missing `::` double colon | Fix: `arn:aws:iam::<ID>:role/<name>` |
| 4.6 | Helm App | DB connection timeout | RDS SG rule referenced wrong node SG | Add actual EKS node SG to RDS inbound |
| 4.7 | Helm App | DB connection blocked | NetworkPolicy CIDR too narrow | Fix `databaseCidr` to match VPC CIDR |
| 4.8 | Helm App | actuator/health returns login page | Spring Security protecting all endpoints | Not an error — use `/actuator/health/liveness` |
| 6.1 | Istio | ArgoCD CLI PermissionDenied | CLI session not logged in | `argocd login localhost:8080` |
| 6.2 | Istio | Gateway chart schema bug | Istio 1.22.0 chart is broken | Install via Helm with version 1.26.8 |
| 6.3 | Istio | Chart version not in repo | 1.22.x removed from repo | `helm search repo` → use available version |
| 6.4 | Istio | Sidecar not injecting | Pod existed before Istio install | Restart rollout to force new pod creation |
| 6.5 | Istio | Gateway/VirtualService missing | `istio.enabled=false` in values | `helm upgrade --set istio.enabled=true` |
| 7.1 | Kyverno | Helm conflict with ArgoCD | Ran `helm install` when ArgoCD manages it | Never use `helm install` for ArgoCD-managed apps |
| 7.2 | Kyverno | Pods Pending | Insufficient CPU | Scale node group to 2 nodes |
| 7.3 | Kyverno | ImagePullBackOff on CronJob pod | Stale CronJob pod — not a core controller | `kubectl delete pod` the stale pod |
| 8.1 | Karpenter | Chart version not found | Wrong repo for Karpenter 1.x | Use OCI: `public.ecr.aws/karpenter/karpenter` |
| 8.2 | Karpenter | Kyverno blocks install | Enforce mode blocks non-compliant chart | Switch to Audit, install, restore Enforce |
| 8.3 | Karpenter | Cannot reuse release name | Previous failed install not cleaned up | `helm uninstall` before retrying |
| 8.4 | Karpenter | IRSA AssumeRole 403 | Trust policy has wrong SA name | Fix: `system:serviceaccount:karpenter:karpenter` |
| 8.5 | Karpenter | CRD v1beta1 not found | Old manifests, Karpenter 1.x uses `v1` | `sed` replace `v1beta1` → `v1` |
| 8.6 | Karpenter | NodePool schema errors | `expireAfter` moved + field renamed in v1 | Update per v1 migration guide |
| 8.7 | Karpenter | GetInstanceProfile 403 | Missing IAM permissions for 1.x | Add `eks:DescribeCluster` + instance profile perms |
| 8.8 | Karpenter | Role NoSuchEntity 404 | Wrong role name in EC2NodeClass | `aws iam list-roles` to find exact name |
| 8.9 | Karpenter | Immutable field error | `spec.role` cannot be patched | Delete and recreate EC2NodeClass |
| 8.10 | Karpenter | Stale instance profile | IAM leftover from failed reconcile | `aws iam delete-instance-profile` |
| 8.11 | Karpenter | Stale pod serving old errors | Rollout restart didn't replace stuck pod | `kubectl delete pod -n karpenter --all` |
| V1 | Velero | MinIO pod stuck | Helm repo issues + leftover PVCs | Deploy as plain Deployment, bypass Helm |
| V2 | Velero | upgrade-crds job stuck | Stuck finalizers | Force delete + patch finalizers + raw API delete |
| V3 | Velero | BackupStorageLocation Unavailable | `velero-backups` bucket not created | Create bucket via `mc mb` inside MinIO pod |
| V4 | Velero | Helm release stuck | Previous failed install not cleaned up | Delete Helm release Secret, reinstall |
| A1 | ArgoCD | Kyverno SyncError | Leftover migrate-resources ClusterRole | Delete CR/CRB, add ignoreDifferences |
| A2 | ArgoCD | Istio OutOfSync | Webhook caBundle runtime mutation | `ignoreDifferences` for webhook config |
| A3 | ArgoCD | VPA OutOfSync | Self-referencing Application in Git | `ignoreDifferences` for Application spec |
| A4 | ArgoCD | Velero OutOfSync | CRD schema drift | `ignoreDifferences` + `jqPathExpressions` |
| A5 | ArgoCD | Tempo OutOfSync | StatefulSet volumeClaimTemplates drift | `ignoreDifferences` for StatefulSet |
| J1 | Jenkins | Port 8080 conflict | kubectl port-forward occupying port | Kill process or change Jenkins port |
| J2 | Jenkins | systemd failed state | Leftover state from previous install | Full purge + clean reinstall |
| J3 | Jenkins | Can't run docker/kubectl/aws | Missing group membership + missing files | Add to docker group, copy kubeconfig + awscreds |
| S1 | SonarQube | Helm install fails | Leftover secrets/configmaps | Full namespace cleanup before reinstall |
| S2 | SonarQube | Pods blocked by Kyverno | Policy enforced cluster-wide | Add namespace exception to ClusterPolicy |
| I1 | Istio/DNS | HTTPS connection refused | Route53 pointing to wrong LB + stuck ACME | Update Route53 to NLB, re-issue cert |
| I2 | Istio/DNS | VirtualService 404 | Service name changed by ArgoCD ApplicationSet | Update VS host + fix in Git |
| K1 | Kyverno | Pods blocked in velero/devsecops | Policy applied to system namespaces | Add namespace exclusions |
| K2 | Kyverno | Admission controller missing | Accidentally deleted | Force ArgoCD hard refresh |
| KP1 | Karpenter | No node provisioned | Kyverno blocking + restrictive NodePool | Compliant pod spec + expand instance types |
| O1 | OTel | Traces not reaching Tempo | Wrong gRPC endpoint + missing protocol | Fix env vars + add `OTEL_EXPORTER_OTLP_PROTOCOL` |
| O2 | Grafana | Duplicate pods | Old ReplicaSet not cleaned up | Scale down / delete old ReplicaSet |
| O3 | Grafana | Tempo datasource missing | ConfigMap sidecar label mismatch | Add datasource directly via Grafana API |
| O4 | Kiali | Empty service graph | Wrong Prometheus URL in Kiali config | Patch ArgoCD app helm values |
| R1 | Resources | Velero pods Pending | ResourceQuota too small | Delete quota + apply larger one |

---

## Quick Debug Commands

```bash
# ArgoCD — full app status
argocd app list

# ArgoCD — only problem apps
argocd app list | grep -v "Synced.*Healthy"

# ArgoCD — force hard refresh
kubectl annotate application <app-name> -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# Velero full status
velero backup-location get
velero schedule get
velero backup get

# Kyverno policy violations
kubectl get policyreport -A | head -20
kubectl logs -n kyverno deploy/kyverno-admission-controller --tail=20

# Istio proxy sync check
istioctl proxy-status
istioctl analyze -n banking-prod

# Resource quota check across all namespaces
kubectl get resourcequota -A

# Find what's using a port
sudo lsof -i :8080

# Helm release state including failed
helm list -n <namespace> --all

# Check pod age (verify restart happened)
kubectl get pods -n <namespace>

# Verify IRSA is working for a pod
kubectl exec -n <namespace> <pod> -- aws sts get-caller-identity
```

---

*This runbook was built from real debugging sessions across a production EKS deployment. Every error and fix here was executed against a live cluster.*