🔥 0. Golden Rule (Before Everything)

Run this first:

kubectl get nodes

✅ PASS: Nodes = Ready
❌ FAIL: Nothing else matters if cluster is down

🐳 1. Docker (Local Runtime)
✅ Check:
docker run -d -p 8080:80 nginx
docker ps
✅ PASS:
Container is running
Port mapped
❌ FAIL:
Container exits immediately
🔥 Deep Check:
docker logs <container>

👉 Must NOT show crash / error

☸️ 2. Kubernetes (Core)
✅ Check Pods:
kubectl get pods -A
✅ PASS:
STATUS = Running
READY = 1/1 or 2/2
❌ FAIL:
CrashLoopBackOff
Pending
🔥 Deep Check:
kubectl get events --sort-by=.lastTimestamp

👉 Detect hidden issues (image pull, scheduling)

📦 3. Helm
✅ Check Releases:
helm list -A
✅ PASS:
STATUS = deployed
🔥 Verify Chart:
helm status <release>

👉 Must show:

deployed
no errors
🚀 4. ArgoCD (GitOps)
✅ Check Apps:
argocd app list
✅ PASS:
HEALTH = Healthy
SYNC = Synced
🔥 CRITICAL:
argocd app diff <app>
✅ PASS:
No diff
❌ FAIL:
Drift exists → Git != Cluster
🧠 5. Jenkins (on K8s)
✅ Pod Check:
kubectl get pods -n jenkins
✅ Build Test:

👉 Trigger job

kubectl get pods -n jenkins -w
✅ PASS:
New agent pod created
🔥 IAM Check:
kubectl exec -it <agent-pod> -n jenkins -- aws sts get-caller-identity
✅ PASS:
Returns IAM role
🪣 6. MinIO
✅ Check Pod:
kubectl get pods -n velero
🔥 Port Forward:
kubectl port-forward svc/minio 9001:9001 -n velero

👉 Open UI

✅ PASS:
Bucket exists (velero)
♻️ 7. Velero (BACKUP = MOST IMPORTANT)
✅ Check:
velero backup get
🔥 REAL TEST:
velero backup create test-backup --include-namespaces default
✅ PASS:
STATUS = Completed
🔥 Restore Test:
velero restore create --from-backup test-backup

👉 THIS = real verification

🌐 8. Istio (Service Mesh)
✅ Sidecar Check:
kubectl get pods -n banking-prod
✅ PASS:
2/2 containers
🔥 Proxy Health:
istioctl proxy-status
✅ PASS:
SYNCED
🔥 Traffic Test:
curl <your-api>

Check header:

server: istio-envoy
📊 9. Prometheus
✅ Check:
kubectl get pods -n monitoring
🔥 Port Forward:
kubectl port-forward svc/prometheus 9090 -n monitoring

Go to:

/targets
✅ PASS:
All targets = UP
📈 10. Grafana
✅ Check:
kubectl get svc -n monitoring
🔥 UI:
Open Grafana
Check dashboards
✅ PASS:
Metrics visible
📜 11. Loki (Logs)
✅ Check:
kubectl logs -l app=loki -n monitoring
🔥 Query (Grafana):
{namespace="banking-prod"}
✅ PASS:
Logs visible
🔍 12. OpenTelemetry (OTEL)
✅ Collector:
kubectl get pods -n monitoring
🔥 Logs:
kubectl logs -l app=otel-collector -n monitoring
✅ PASS:
Receiving spans
🧵 13. Tempo (Tracing)
🔥 REAL TEST:
Generate request:
curl <your-api>
Open Grafana → Traces
✅ PASS:
Trace appears
🕸️ 14. Kiali
🔥 Launch:
istioctl dashboard kiali
✅ PASS:
Graph shows services
Green edges (healthy)



terraform:

    ask chatgpt: for terraform to run we need a access and secret key but in produciton what approach they used to configure aws in vm so that terraform can be used

    install awscli
    install terraform,kubectl,helm and git

    create a kms key in the aws cli and add it into the terraform.tfvars before running terraform bootstrap so that it can run wihtout any error
        Define the Key: Create a kms.tf file in a terraform/global/security folder or within your bootstrap directory.
        Enable Key Rotation: For banking compliance (PCI-DSS), always set enable_key_rotation = true.
        Reference the ARN: Once created, you pass the aws_kms_key.terraform_backend_key.arn into your aws_s3_bucket_server_side_encryption_configuration resource.
        2. Manual Creation via AWS CLI (Fastest for Day 1)
        If you want to ensure your S3 bucket is encrypted from the very first second of its existence, you can create the key manually or via CLI and then "hardcode" the ARN into your variables.
        CLI Command:
        aws kms create-key --description "KMS key for Terraform State Encryption" --tags TagKey=Project,TagValue=Banking-System
        Capture the ARN: Take the ARN from the output
        Update Variables: Place this ARN in your terraform.tfvars or pass it as a -var="kms_key_arn=..." during the terraform apply of your bootstrap code.


    the github actions will be trigger for terraform:

Dokcer:
    # Build the production image (verifies OTel agent download and Maven compilation)
    docker build -t banking-api:test .

    # Run the container locally to verify JVM startup and OTel integration
    docker run -p 8080:8080 banking-api:test

    # Start the App, MySQL, and Nginx stack
    docker-compose up -d

    # Verify the application health status
    curl http://localhost:8080/actuator/health

Jenkins:
    1. Test AWS & ECR Connectivity
    Verify that Jenkins has the correct IAM permissions (via IRSA) to push images to your private repository:

    Bash
    # Get login token and authenticate Docker with ECR
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

    # Verify the repository exists
    aws ecr describe-repositories --repository-names springboot-bankapp
    2. Test Maven & SonarQube Manual Trigger
    Verify that your source code can be analyzed before running the full pipeline:

    Bash
    # Run local compilation and Sonar analysis (Requires SONAR_TOKEN env var)
    ./mvnw clean verify sonar:sonar \
    -Dsonar.projectKey=banking-platform \
    -Dsonar.host.url=http://sonarqube-server:9000 \
    -Dsonar.login=$SONAR_TOKEN
    3. Test Security Scanning (Trivy)
    Verify that your container security gate is functional:

    Bash
    # Scan your local build for CRITICAL vulnerabilities
    trivy image --severity CRITICAL springboot-bankapp:latest
    4. Test K8s/ArgoCD GitOps Sync
    Verify that Jenkins can communicate with your GitOps repository to update the image tag:

    Bash
    # Check if the deployment key/token has push access
    git ls-remote https://github.com/rohandeb2/sspringboot-bankapp.git

    # Verify ArgoCD can see the cluster
    kubectl get pods -n argocd
    5. AI RCA Script Verification
    Verify that your custom AI error analysis script can execute:

    Bash
    # Test the Python RCA script with a dummy log file
    python3 scripts/ai_rca.py --log build_failure.log --output analysis.txt

    To verify that your **ArgoCD-managed infrastructure** and **Jenkins-on-Kubernetes** setup are correctly configured and functional, you need to validate the GitOps sync, the pod-level persistence, and the dynamic agent scaling.

    Here are the commands to verify each layer of that specific infrastructure:

    ### 1. Verify ArgoCD GitOps Synchronization
    First, ensure ArgoCD has successfully reconciled your manifests from the Git repository to the EKS cluster.

    ```bash
    # Check the status of the 'cicd' application in ArgoCD
    argocd app get cicd

    # Or via kubectl to see if the Application resource is 'Synced'
    kubectl get application cicd -n argocd -o jsonpath='{.status.sync.status}'

    # Verify that all resources managed by ArgoCD are created
    kubectl get all -n jenkins
    ```


    ### 2. Verify Jenkins Master Installation & Persistence
    Since your manifests include a **PersistentVolumeClaim (1_jenkins-pvc.yaml)**, you must verify that Jenkins is not only running but also storing data correctly.

    ```bash
    # Check if the Jenkins Master pod is 'Running' and 'Ready'
    kubectl get pods -n jenkins -l app.kubernetes.io/name=jenkins

    # Verify the PVC is 'Bound' to a storage class (EBS)
    kubectl get pvc -n jenkins

    # Check Jenkins Master logs for successful startup
    kubectl logs -f deployment/jenkins -n jenkins
    ```

    ### 3. Verify Jenkins Agent Scaling (The Pod-in-Pod Test)
    In your `6_jenkins-agent-sa.yaml`, you configured a Service Account for agents. You need to verify that when a build starts, a new pod is dynamically created in Kubernetes.

    * **Trigger a Build** in the Jenkins UI.
    * **Run this command immediately:**
    ```bash
    # Watch for the dynamic agent pod (usually named 'jenkins-agent-xxxx')
    kubectl get pods -n jenkins -w
    ```
    * **Verify Agent Permissions:** Once the agent pod is running, verify it can "talk" to AWS (ECR/S3) using the IRSA role:
    ```bash
    # Exec into the running agent and check identity
    kubectl exec -it <agent-pod-name> -n jenkins -- aws sts get-caller-identity
    ```


    ### 4. Verify External Secrets & Configuration
    You are using **0_jenkins-external-secret.yaml** to pull sensitive data. Verify that the Secret Operator successfully injected these into Kubernetes.

    ```bash
    # Check if the ExternalSecret resource is 'SecretSynced'
    kubectl get externalsecret jenkins-secrets -n jenkins

    # Verify the resulting Kubernetes Secret contains your data (encoded)
    kubectl get secret jenkins-secrets -n jenkins -o yaml
    ```

    ### 5. Verify Network Policies
    Your `5_jenkins-network-policy.yaml` restricts traffic. Verify that the Jenkins Master can reach the internet but is protected from unauthorized internal pods.

    ```bash
    # Run a temporary pod to see if it can "talk" to Jenkins (should be blocked if not allowed)
    kubectl run access-test --image=busybox -n default --rm -it -- restart=Never -- wget -qO- jenkins.jenkins.svc.cluster.local:8080
    ```


kubernetes:
    To verify that your **Banking Platform** (the actual Spring Boot application and its Kubernetes ecosystem) is running correctly in production, you need to check the application health, the network exposure, and the service mesh (Istio) configuration.

    Here are the commands to verify each layer of your application deployment:

    ### 1. Verify Pod Status and Readiness
    Ensure that your Spring Boot pods are running and have passed their liveness/readiness probes.

    ```bash
    # Check if pods are 'Running' and 'Ready' in the banking namespace
    kubectl get pods -n banking-prod -l app=banking-platform

    # Check the logs of a specific pod to ensure the JVM and OTel agent started
    kubectl logs -l app=banking-platform -n banking-prod --tail=100

    # Verify the Rollout status (Argo Rollouts)
    kubectl argo rollouts get rollout banking-platform -n banking-prod
    ```


    ### 2. Verify Application Health (Actuator)
    Since you are using Spring Boot, you should verify the internal health of the app, including its database connection.

    ```bash
    # Port-forward to the service to test locally
    kubectl port-forward svc/banking-platform-service 8080:80 -n banking-prod

    # In a new terminal, check the health endpoint
    curl http://localhost:8080/actuator/health
    ```
    *Look for: `{"status":"UP","components":{"db":{"status":"UP",...}}}`. This confirms the app can talk to your RDS instance.*

    ### 3. Verify Istio Service Mesh & Networking
    Your project uses Istio for secure communication. You need to verify that the **VirtualService** and **Gateway** are correctly routing traffic.

    ```bash
    # Verify Istio Ingress Gateway has a public IP (LoadBalancer)
    kubectl get svc istio-ingressgateway -n istio-system

    # Check if the VirtualService is correctly linked to the Gateway
    kubectl get virtualservice banking-vs -n banking-prod -o yaml

    # Verify Mutual TLS (mTLS) is enabled for the namespace
    kubectl get peerauthentication -n banking-prod
    ```


    ### 4. Verify Autoscaling (HPA & VPA)
    You have both Horizontal and Vertical autoscalers defined to handle banking traffic spikes.

    ```bash
    # Check Horizontal Pod Autoscaler status
    kubectl get hpa banking-platform-hpa -n banking-prod

    # Check Vertical Pod Autoscaler recommendations
    kubectl get vpa banking-platform-vpa -n banking-prod
    ```

    ### 5. Verify Observability (Metrics & Traces)
    Ensure your application is successfully sending data to your LGTM stack (Prometheus/Tempo).

    ```bash
    # Verify the ServiceMonitor is discovered by Prometheus
    kubectl get servicemonitor banking-monitor -n banking-prod

    # Check if the OTel Collector is receiving spans from the app
    kubectl logs -l app=otel-collector -n monitoring --tail=50
    ```

Sonarqube:
    To verify the **SonarQube stack** within your `devsecops` folder, you need to ensure that the persistent storage is bound, the server is reachable via the Load Balancer, and that the "Quality Gate" integration with Jenkins is active.

    ### 1. Verify ArgoCD Deployment
    First, confirm that ArgoCD has successfully synchronized the Sonarqube manifests from your repository to the cluster.

    * **Check Sync Status**:
        ```bash
        kubectl get application sonarqube -n argocd
        ```
    * **Verify Namespace Resources**:
        ```bash
        kubectl get all -n devsecops
        ```
    

    ### 2. Verify Database Persistence
    SonarQube requires a PostgreSQL database with persistent storage to save your project analysis history.

    * **Check PersistentVolumeClaims (PVC)**:
        ```bash
        kubectl get pvc -n devsecops
        ```
        *Ensure the status is `Bound`. If it is `Pending`, check your EBS CSI driver status.*

    ### 3. Verify Network Connectivity & SSL
    Your configuration likely uses an **Ingress** or **LoadBalancer** to expose the dashboard at `sonarqube.rohandevops.co.in`.

    * **Check Ingress/Service**:
        ```bash
        kubectl get ingress sonarqube-ingress -n devsecops
        ```
    * **Connectivity Test**:
        ```bash
        curl -I https://sonarqube.rohandevops.co.in/api/system/status
        ```
        *Look for a `HTTP/1.1 200 OK` response.*

    ### 4. Verify Jenkins Integration (The Quality Gate)
    For your `devSecOpsPipeline` to work, Jenkins must be able to communicate with SonarQube to check if the code passed the security scan.

    * **Check Jenkins Logs**: Look for the `SAST - SonarQube` stage in your Jenkins console output.
        ```text
        [Pipeline] withSonarQubeEnv
        Injecting SonarQube environment variables...
        [Pipeline] sh
        + mvn sonar:sonar ...
        ```
    
    * **Webhook Verification**: Log into the SonarQube UI (`Administration > Configuration > Webhooks`) and ensure there is a webhook pointing to your Jenkins URL (`https://jenkins.rohandevops.co.in/sonarqube-webhook/`). This is what allows the `waitForQualityGate()` command in your Groovy script to receive the "OK" status.

    ### 5. Manual Scan Test
    Run a manual scan from your VM to verify the server is accepting reports:

    ```bash
    mvn sonar:sonar \
    -Dsonar.projectKey=banking-platform \
    -Dsonar.host.url=https://sonarqube.rohandevops.co.in \
    -Dsonar.login=<your-sonar-token>
    ```

argocd:
    DR (MinIO + velero):
        To verify the **Disaster Recovery (DR)** stack consisting of **MinIO** and **Velero**, you must ensure that the backup storage is reachable, the schedules are active, and—most importantly—that you can actually perform a data restoration. In a production banking environment, a backup that hasn't been tested for restoration is considered non-existent.

        ### 1. Verify Infrastructure Sync (ArgoCD)
        First, confirm that ArgoCD has successfully deployed the DR components to the cluster.
        * **Check Application Status**: 
            ```bash
            argocd app get disaster-recovery
            ```
        * **Verify Namespace Resources**:
            ```bash
            kubectl get all -n velero
            ```
            Ensure the Velero deployment and the MinIO statefulset are both in a `Running` state.

        ### 2. Verify MinIO (Backup Storage)
        MinIO acts as the S3-compatible storage layer for your backups.
        * **Check Persistence**: Verify the Persistent Volume Claim (PVC) for MinIO is `Bound`.
            ```bash
            kubectl get pvc -n velero
            ```
        
        * **Access the UI**: Port-forward to the MinIO console to verify the `velero` bucket exists.
            ```bash
            kubectl port-forward svc/minio 9001:9001 -n velero
            ```
            Log in to `http://localhost:9001` and confirm that the bucket defined in your configuration is present.

        ### 3. Verify Velero Configuration
        Velero must be correctly linked to MinIO to store the cluster metadata and snapshots.
        * **Check Backup Storage Location**:
            ```bash
            velero backup-location get
            ```
            The status must be `Available`. If it shows `Unavailable`, check the credentials in your `0_jenkins-external-secret.yaml` or the MinIO service endpoint.
        * **Verify the Schedule**:
            ```bash
            velero schedule get
            ```
            Confirm the `banking-repo-backup` schedule is active and shows a "Last Backup" timestamp.



        ### 4. The "100% Verification" Restoration Test
        To truly verify the `velero.yaml` configuration, you must perform a manual backup and restore drill.
        * **Create a Manual Backup**:
            ```bash
            velero backup create verify-backup --include-namespaces banking-prod
            ```
        * **Simulate Failure**: Delete a non-critical resource in the banking namespace (e.g., a ConfigMap).
            ```bash
            kubectl delete configmap banking-platform-config -n banking-prod
            ```
        * **Perform Restoration**:
            ```bash
            velero restore create --from-backup verify-backup
            ```
        * **Confirm Success**: Check if the resource has reappeared and Velero reports the restoration as `Completed`.

        ### 5. Verify IAM & EBS Integration (Cloud DR)
        Your configuration includes an IRSA role for Velero to handle AWS-level snapshots.
        * **Check EBS Snapshots**:
            ```bash
            velero backup describe verify-backup --details
            ```
            Verify that the "Volume Snapshots" section shows successful snapshots for your RDS or persistent EBS volumes.
    Governace:
        To verify the **Governance and Scaling** layer of your platform, you must ensure that **Kyverno** is actively blocking non-compliant resources and that **Karpenter** is dynamically managing your cloud hardware based on real-time demand.

        ### 1. Verify Kyverno (Policy Engine)
        Kyverno ensures your banking cluster stays compliant by enforcing security "guardrails."

        * **Verify Installation**:
            ```bash
            kubectl get pods -n kyverno
            ```
        * **Check Policies**: Verify that your ClusterPolicies (like "No Root User" or "Required Labels") are active.
            ```bash
            kubectl get clusterpolicy
            ```
        * **The "Violation" Test**: Try to deploy a pod that violates your security policy (e.g., an Nginx pod without resource limits).
            ```bash
            kubectl run non-compliant-pod --image=nginx --restart=Never
            ```
            **Verification**: If Kyverno is working, the API server should **reject** the request with an error message. If the pod starts, your governance layer is not enforcing rules.



        ### 2. Verify Karpenter (Just-in-Time Scaling)
        Unlike the old Cluster Autoscaler, Karpenter talks directly to the AWS EC2 fleet to provision nodes in seconds.

        * **Verify Controller**:
            ```bash
            kubectl get pods -n karpenter
            ```
        * **Check Provisioning Logic**: Verify your NodePool and EC2NodeClass are successfully synchronized with AWS.
            ```bash
            kubectl get nodepool
            kubectl get ec2nodeclass
            ```
        
        * **The "Scale-Up" Test**: Scale your banking app to a high number of replicas to force a hardware shortage.
            ```bash
            kubectl scale deployment banking-platform --replicas=50 -n banking-prod
            ```
        * **Monitor Logs**: Watch the Karpenter logs to see it "discover" the pending pods and request a new EC2 instance from AWS.
            ```bash
            kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter
            ```
            **Verification**: A new node should appear in `kubectl get nodes` within 30–60 seconds.



        ### 3. Verify IRSA for Karpenter
        Karpenter needs permission to launch EC2 instances. You must verify that the IRSA role is working.

        * **Check Identity**:
            ```bash
            kubectl exec -it <karpenter-pod-name> -n karpenter -- aws sts get-caller-identity
            ```
            The output must show the IAM role created in your `terraform/modules/iam/main.tf`.

        ### 4. Verify "Interruption" Handling
        Karpenter is configured to handle Spot terminations and "Node Expiry."
        * **Check the Log**: Look for "disruption" events where Karpenter automatically consolidates small nodes into one large node to save costs for the bank.
            ```bash
            kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep "disrupting"
            ```


    Monitoring:
        To verify your **Observability (LGTM) Stack** and the **AIOps** layer, you must confirm that data is not just being collected, but also correlated across traces, logs, and metrics. In a Big 4 banking environment, "verification" means proving you can trace a single failed transaction from a user's click down to a specific line of code or a database latency spike.

        ### 1. Verify Metrics (Prometheus & Grafana)
        Prometheus collects the "Health" of your cluster, while Grafana visualizes it.
        * **Verify Service Discovery**:
            ```bash
            # Ensure Prometheus is successfully scraping your Spring Boot app
            kubectl get servicemonitor banking-monitor -n banking-prod
            ```
        * **Verify Grafana Dashboards**: Access the Grafana UI (usually via an Ingress at `grafana.rohandevops.co.in`) and verify that the **"Spring Boot Statistics"** and **"EKS Cluster"** dashboards are populated with real-time data.
        * **Test Alertmanager**: Manually lower an alert threshold (e.g., CPU usage) and verify that Alertmanager sends a notification to your configured channel (Slack/Email).

        ### 2. Verify Logging (Loki)
        Loki handles your log aggregation with a focus on cost-efficiency.
        * **Verify Persistence**: Since you are using **IRSA**, verify that the Loki pods can write to your S3 bucket without using static keys.
            ```bash
            kubectl logs -l app.kubernetes.io/name=loki -n monitoring | grep "bucket"
            ```
        * **Log Streaming**: In Grafana "Explore", select the **Loki** datasource and run a query like `{namespace="banking-prod"}`. You should see live logs from your Spring Boot application.



        ### 3. Verify Tracing & Correlation (Tempo & OpenTelemetry)
        This is the most critical part of your "Production-Ready" verification.
        * **Verify OTel Collector**: Ensure the collector is receiving spans from your app and forwarding them to Tempo.
            ```bash
            kubectl logs -l app=otel-collector -n monitoring --tail=50
            ```
        * **Verify Trace Correlation**: In Grafana, find a log entry in Loki. If your OTel agent is working, the log will contain a `trace_id`. Click on that ID; it should instantly open the corresponding span in **Tempo**. This "Log-to-Trace" jump is the gold standard of observability.



        ### 4. Verify Service Mesh Observability (Kiali)
        Kiali provides a visual map of your **Istio Service Mesh**.
        * **Verify Traffic Graph**: Access the Kiali UI and look at the **Graph** view for the `banking-prod` namespace. 
        * **Verification**: You should see visual arrows showing traffic flowing from the `istio-ingressgateway` to your `banking-platform` service. If the lines are green, mTLS is healthy; if they are red, Istio is detecting 5xx errors.



        ### 5. Verify AIOps (AI Alerts)
        Your project includes an advanced `ai-alerts.yaml` and a Python script for Root Cause Analysis (RCA).
        * **Verify Alert Trigger**: When a Prometheus alert fires (e.g., `HighErrorRate`), verify that the **AI Alerting Webhook** is triggered.
        * **Verify RCA Output**: Check the logs of your AI-service or the output folder in your Jenkins agent.
            ```bash
            # Verify the AI RCA script can process a log file and generate a summary
            python3 scripts/ai_rca.py --log sample_error.log --output rca_report.txt
            ```
            *Verification: The `rca_report.txt` should contain an "AI Analysis" section explaining the error in plain English*.


        No, the manual `kubectl` and UI checks we discussed are the **technical verification**, but in a 10+ year senior role at a Big 4 firm, we use a much more rigorous framework. Technical "uptime" is only about 60% of the job; the remaining 40% is **Functional, Security, and Resilience verification**.

        Here are the three advanced ways to verify your ArgoCD-managed tools beyond just checking if the pods are "Running."

        ### 1. Functional "End-to-End" Verification (The Real Test)
        A tool is only verified if it performs its business function.
        * **SonarQube:** Don't just check the UI. Break the code (e.g., add a hardcoded password) and verify that the **Quality Gate** turns Red and blocks the Jenkins pipeline.
        * **Velero:** A backup is useless unless it can restore. Delete the `banking-prod` namespace entirely and run `velero restore`. If the app comes back with all its data, it is verified.
        * **Prometheus/Alertmanager:** Kill a pod manually. Verify that an alert fires, the **AI RCA** script triggers, and you receive a notification. If you don't get the alert, the monitoring tool is "running" but not "working."



        ### 2. Automated "Health Checks" (The Platform Way)
        In large-scale companies, we don't run manual commands. We use **ArgoCD Health Checks** and **Resource Hooks**.
        * **Custom Health Checks:** You can write Lua scripts inside ArgoCD to define what "Healthy" means for complex tools like Istio or Karpenter. For example, Karpenter is only "Healthy" if it can successfully talk to the AWS EC2 API.
        * **Post-Sync Hooks:** You can configure a Kubernetes `Job` that runs immediately after ArgoCD syncs. This job can run a suite of integration tests (e.g., a script that pings the SonarQube API) and report back to ArgoCD. If the test fails, ArgoCD marks the sync as "Failed."

        ### 3. Compliance & Governance Audit (The "Big 4" Way)
        Since this is a banking app, you must verify that the tools are **Compliant**.
        * **Kyverno Audit:** Run `kubectl get policyreports`. This shows you which pods are violating your governance rules. Even if the pod is "Running," if it has a "Fail" status in the policy report, your governance is verified and doing its job by flagging risks.
        * **Istio mTLS Verification:** Run `istioctl analyze`. This tool scans your entire service mesh and tells you if there are any security holes or misconfigurations in your VirtualServices or Gateways.


    Networking:
        As a senior DevOps engineer, I treat **Istio** as the "nervous system" of your banking platform. It doesn’t just route traffic; it enforces security (mTLS), provides deep observability, and ensures resilience.

        To verify the networking part is truly "production-grade," you must follow this specialized four-layered audit:

        ### 1. The "Sidecar" Injection Audit
        If a pod doesn't have the **istio-proxy** sidecar, it’s not part of the mesh and will fail your security policies.

        * **Namespace Check**: Ensure the `banking-prod` namespace is labeled for injection.
            ```bash
            kubectl get namespace banking-prod -L istio-injection
            ```
            *Result: Should show `enabled`.*
        * **Pod Verification**: Confirm your banking app pods have **2/2** containers.
            ```bash
            kubectl get pods -n banking-prod
            ```
            *Verification: Use `kubectl get pod <pod-name> -n banking-prod -o jsonpath='{.spec.containers[*].name}'` to see `istio-proxy` in the list.*

        ### 2. The "Ingress & Routing" Audit
        Verify that traffic flows from the internet through the **AWS NLB** to your **Istio Gateway** and finally to your app.

        * **Gateway Status**: Check if the Gateway is programmed and has an IP.
            ```bash
            kubectl get gateway -n banking-prod
            ```
        * **VirtualService Sync**: Ensure the routing rules (timeouts, retries) are applied to the gateway.
            ```bash
            istioctl analyze -n banking-prod
            ```
            *Expert Tip: If `istioctl analyze` returns any warnings, your traffic might be hitting a "dead end."*
        * **End-to-End Ping**: Test the public URL.
            ```bash
            curl -I https://api.rohandevops.co.in/actuator/health
            ```
            *Look for the header `server: istio-envoy` to prove Istio handled the request.*

        ### 3. The "Zero Trust" mTLS Audit (Critical for Banking)
        You must prove that pod-to-pod traffic is encrypted and that plaintext traffic is **blocked**.

        * **Policy Verification**: Ensure your **PeerAuthentication** is set to `STRICT`.
            ```bash
            kubectl get peerauthentication -n banking-prod
            ```
        
        * **The mTLS "Lock" Test**: Use `istioctl` to check the actual security handshake.
            ```bash
            istioctl proxy-config secret <banking-pod-name> -n banking-prod
            ```
            *Verification: You should see active certificates with an expiration date. This proves the sidecar is rotated with fresh keys.*
        * **The "Spoof" Test**: Try to `curl` the banking app from a namespace *without* Istio. It should be **rejected** by the proxy because it lacks an mTLS certificate.

        ### 4. The "Mesh Visualizer" Audit (Kiali)
        Kiali is the only way to see the "live" topology of your banking microservices.

        * **Launch Dashboard**:
            ```bash
            istioctl dashboard kiali
            ```
        * **Verification**: Go to the **Graph** view. You should see a **padlock icon** on the traffic lines between services. This is your visual confirmation of 100% mTLS adoption across the banking platform.


    argocd:
        As a senior DevOps engineer, I treat **Istio** as the "nervous system" of your banking platform. It doesn’t just route traffic; it enforces security (mTLS), provides deep observability, and ensures resilience.

        To verify the networking part is truly "production-grade," you must follow this specialized four-layered audit:

        ### 1. The "Sidecar" Injection Audit
        If a pod doesn't have the **istio-proxy** sidecar, it’s not part of the mesh and will fail your security policies.

        * **Namespace Check**: Ensure the `banking-prod` namespace is labeled for injection.
            ```bash
            kubectl get namespace banking-prod -L istio-injection
            ```
            *Result: Should show `enabled`.*
        * **Pod Verification**: Confirm your banking app pods have **2/2** containers.
            ```bash
            kubectl get pods -n banking-prod
            ```
            *Verification: Use `kubectl get pod <pod-name> -n banking-prod -o jsonpath='{.spec.containers[*].name}'` to see `istio-proxy` in the list.*

        ### 2. The "Ingress & Routing" Audit
        Verify that traffic flows from the internet through the **AWS NLB** to your **Istio Gateway** and finally to your app.

        * **Gateway Status**: Check if the Gateway is programmed and has an IP.
            ```bash
            kubectl get gateway -n banking-prod
            ```
        * **VirtualService Sync**: Ensure the routing rules (timeouts, retries) are applied to the gateway.
            ```bash
            istioctl analyze -n banking-prod
            ```
            *Expert Tip: If `istioctl analyze` returns any warnings, your traffic might be hitting a "dead end."*
        * **End-to-End Ping**: Test the public URL.
            ```bash
            curl -I https://api.rohandevops.co.in/actuator/health
            ```
            *Look for the header `server: istio-envoy` to prove Istio handled the request.*

        ### 3. The "Zero Trust" mTLS Audit (Critical for Banking)
        You must prove that pod-to-pod traffic is encrypted and that plaintext traffic is **blocked**.

        * **Policy Verification**: Ensure your **PeerAuthentication** is set to `STRICT`.
            ```bash
            kubectl get peerauthentication -n banking-prod
            ```
        
        * **The mTLS "Lock" Test**: Use `istioctl` to check the actual security handshake.
            ```bash
            istioctl proxy-config secret <banking-pod-name> -n banking-prod
            ```
            *Verification: You should see active certificates with an expiration date. This proves the sidecar is rotated with fresh keys.*
        * **The "Spoof" Test**: Try to `curl` the banking app from a namespace *without* Istio. It should be **rejected** by the proxy because it lacks an mTLS certificate.

        ### 4. The "Mesh Visualizer" Audit (Kiali)
        Kiali is the only way to see the "live" topology of your banking microservices.

        * **Launch Dashboard**:
            ```bash
            istioctl dashboard kiali
            ```
        * **Verification**: Go to the **Graph** view. You should see a **padlock icon** on the traffic lines between services. This is your visual confirmation of 100% mTLS adoption across the banking platform.


script(python):
    To verify your **AI Root Cause Analysis (RCA)** script, you need to simulate a failure and confirm that the script can successfully communicate with the Google Gemini API to return a meaningful fix. 

    In a Big 4 environment, we call this **Integration Testing for AIOps**. Here is the step-by-step guide to confirm it is working:

    ### 1. The Environment Check
    The script relies on an Environment Variable for security (so you don't hardcode keys in Git). You must ensure this is set on your VM or Jenkins Agent.

    **Command to Verify Variable:**
    ```bash
    # Check if the key is present in your session
    echo $GEMINI_API_KEY
    ```
    *If it returns empty, run: `export GEMINI_API_KEY="your_actual_key_here"`*

    ### 2. The Manual "Dry Run" (CLI)
    You don't need to run a 20-minute Jenkins pipeline to test this. You can "pipe" a dummy error log directly into the script to see if the AI responds.

    **Command to Test:**
    ```bash
    # We echo a classic Spring Boot error and pipe it into the python script
    echo "ERROR: org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'dataSource' defined in class path resource. Property 'url' is required" | python3 scripts/ai_rca.py
    ```

    **What "Working" Looks Like:**
    If successful, the terminal should print:
    > `--- AI ROOT CAUSE ANALYSIS ---`
    > `The root cause is a missing database URL in your application.properties. Fix: Add 'spring.datasource.url' to your configuration.`



    ### 3. Verifying the "Post-Failure" Hook in Jenkins
    The script is designed to run only when the pipeline fails. To verify this integration:

    * **Go to your Jenkinsfile / Pipeline:** Temporarily sabotage your build (e.g., change the Maven command to `mvn clean package-typo`).
    * **Run the Pipeline**: Let it fail.
    * **Check the "Post" Stage Logs**: Look for the following in the Jenkins console:
        ```text
        [Pipeline] { (Post Actions)
        [Pipeline] sh
        + cat jenkins.log | python3 scripts/ai_rca.py
        --- AI ROOT CAUSE ANALYSIS ---
        The command 'package-typo' is not a valid Maven goal...
        ```

    ### 4. Common Failure Points (What to check if it's NOT working)
    * **403 Forbidden:** Your `GEMINI_API_KEY` is invalid or expired.
    * **ModuleNotFoundError:** You haven't installed the `requests` library.
        * *Fix:* `pip install requests`
    * **KeyError: 'candidates'**: The AI returned an error (likely due to safety filters or reaching quota).
        * *Fix:* Check `response.json()` before returning to see the raw error message from Google.

    ### 🧠 Strategic Guidance for Mentorship
    When you show this to a candidate or an interviewer, emphasize that this script implements **"Self-Healing Infrastructure"** principles. By sending only the last 2000 characters (`log_text[-2000:]`), you are optimizing for **Token Cost** and **Context Window** accuracy, which is exactly how we manage high-volume logging in production environments at scale.

    **Final 100% Verification Step:**
    Check your email (configured in the Jenkins `post` block). If the email contains the AI analysis text, the integration between **GitHub → Jenkins → Gemini API → Mail Server** is officially verified.



check github-actions for any issue
