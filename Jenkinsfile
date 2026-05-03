pipeline {
    agent any

    environment {
        AWS_ACCOUNT_ID              = "959589242185"
        AWS_REGION                  = "us-east-1"
        IMAGE_REPO                  = "springboot-bankapp"
        IMAGE_TAG                   = "${env.BUILD_NUMBER}"
        ECR_URL                     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        AWS_SHARED_CREDENTIALS_FILE = "/var/lib/jenkins/.aws/credentials"
        AWS_CONFIG_FILE             = "/var/lib/jenkins/.aws/config"
        SONAR_URL                   = "http://localhost:9000"
        SONAR_PROJECT_KEY           = "springboot-bankapp"
    }

    // ─────────────────────────────────────────
    // AUTO TRIGGER — on every GitHub push
    // ─────────────────────────────────────────
    triggers {
        githubPush()
    }

    stages {

        // ─────────────────────────────────────────
        // STAGE 0 — Pull all secrets from AWS
        // ─────────────────────────────────────────
        stage('0. Configure AWS + Pull Secrets') {
            steps {
                script {
                    def awsSecret = sh(
                        script: "aws secretsmanager get-secret-value --secret-id jenkins-aws-creds --region ${AWS_REGION} --query SecretString --output text",
                        returnStdout: true
                    ).trim()
                    def awsCreds = readJSON text: awsSecret
                    env.AWS_ACCESS_KEY_ID     = awsCreds.aws_access_key_id
                    env.AWS_SECRET_ACCESS_KEY = awsCreds.aws_secret_access_key

                    def jenkinsSecret = sh(
                        script: "aws secretsmanager get-secret-value --secret-id jenkins-secret --region ${AWS_REGION} --query SecretString --output text",
                        returnStdout: true
                    ).trim()
                    def jenkinsCreds = readJSON text: jenkinsSecret
                    env.SONAR_TOKEN = jenkinsCreds.'sonar-token'
                    env.GEMINI_KEY  = jenkinsCreds.gemini_api_key

                    def githubSecret = sh(
                        script: "aws secretsmanager get-secret-value --secret-id banking-github-creds --region ${AWS_REGION} --query SecretString --output text",
                        returnStdout: true
                    ).trim()
                    def githubCreds = readJSON text: githubSecret
                    env.GIT_TOKEN = githubCreds.git_password

                    echo "All credentials pulled successfully"
                    sh "aws sts get-caller-identity"
                }
            }
        }

        // ─────────────────────────────────────────
        // STAGE 1 — Build
        // ─────────────────────────────────────────
        stage('1. Build & Package') {
            steps {
                sh """
                    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
                    export PATH=\$JAVA_HOME/bin:\$PATH
                    mvn clean package -DskipTests -Dmaven.wagon.http.retryHandler.count=3
                """
            }
        }

        // ─────────────────────────────────────────
        // STAGE 2 — SAST: SonarQube (disabled until pod is stable)
        // Uncomment this entire stage once SonarQube is running:
        //   kubectl get pods -n devsecops → sonarqube-sonarqube-0 1/1 Running
        //   kubectl port-forward svc/sonarqube-sonarqube -n devsecops 9000:9000 &
        //   curl http://localhost:9000/api/system/status → {"status":"UP"}
        // ─────────────────────────────────────────
        /*
        stage('2. SAST — SonarQube') {
            steps {
                script {
                    def sonarStatus = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' ${SONAR_URL}/api/system/status",
                        returnStdout: true
                    ).trim()

                    if (sonarStatus != '200') {
                        error "SonarQube not reachable at ${SONAR_URL} (HTTP ${sonarStatus}). Is the pod running and port-forwarded?"
                    }

                    sh """
                        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
                        export PATH=\$JAVA_HOME/bin:\$PATH
                        mvn sonar:sonar \
                          -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                          -Dsonar.projectName=${SONAR_PROJECT_KEY} \
                          -Dsonar.host.url=${SONAR_URL} \
                          -Dsonar.login=${env.SONAR_TOKEN} \
                          -Dsonar.java.binaries=target/classes \
                          -Dsonar.sources=src/main/java \
                          -Dsonar.tests=src/test/java
                    """

                    sleep(time: 30, unit: 'SECONDS')

                    def qgResponse = sh(
                        script: """
                            curl -s -u ${env.SONAR_TOKEN}: \
                            "${SONAR_URL}/api/qualitygates/project_status?projectKey=${SONAR_PROJECT_KEY}" \
                            | python3 -c "import sys,json; print(json.load(sys.stdin)['projectStatus']['status'])"
                        """,
                        returnStdout: true
                    ).trim()

                    echo "SonarQube Quality Gate: ${qgResponse}"

                    if (qgResponse == 'ERROR') {
                        error "SonarQube Quality Gate FAILED. Fix code issues before proceeding."
                    }
                }
            }
        }
        */

        // ─────────────────────────────────────────
        // STAGE 3 — SCA: OWASP Dependency Check
        // ─────────────────────────────────────────
        stage('3. SCA — OWASP Dependency Check') {
            steps {
                sh 'mkdir -p dependency-check-report'

                dependencyCheck(
                    additionalArguments: """
                        --scan ./
                        --format HTML
                        --format JSON
                        --out dependency-check-report
                        --prettyPrint
                    """,
                    odcInstallation: 'DP-Check'
                )

                dependencyCheckPublisher(
                    pattern: 'dependency-check-report/dependency-check-report.xml',
                    failedTotalCritical: 1,
                    unstableTotalHigh: 5
                )

                archiveArtifacts artifacts: 'dependency-check-report/**', allowEmptyArchive: true
            }
        }

        // ─────────────────────────────────────────
        // STAGE 4 — Docker Build + Trivy Scan
        // ─────────────────────────────────────────
        stage('4. Docker Build + Trivy Scan') {
            steps {
                script {
                    def fullImage = "${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}"

                    sh "docker build -t ${fullImage} ."

                    // Block pipeline if CRITICAL vulnerabilities found
                    sh """
                        trivy image \
                          --exit-code 1 \
                          --severity CRITICAL \
                          --no-progress \
                          --format table \
                          --timeout 10m \
                          ${fullImage}
                    """

                    // Full report for all severities — archived for review
                    sh """
                        trivy image \
                          --exit-code 0 \
                          --severity LOW,MEDIUM,HIGH,CRITICAL \
                          --no-progress \
                          --format json \
                          --output trivy-report.json \
                          --timeout 10m \
                          ${fullImage}
                    """

                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                    echo "Trivy scan passed — no CRITICAL vulnerabilities found"
                }
            }
        }

        // ─────────────────────────────────────────
        // STAGE 5 — Push to ECR + ECR Native Scan
        // ─────────────────────────────────────────
        stage('5. Push to ECR') {
            steps {
                script {
                    def fullImage = "${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}"

                    // Create ECR repo if it doesn't exist yet
                    sh """
                        aws ecr describe-repositories \
                          --repository-names ${IMAGE_REPO} \
                          --region ${AWS_REGION} >/dev/null 2>&1 || \
                        aws ecr create-repository \
                          --repository-name ${IMAGE_REPO} \
                          --region ${AWS_REGION}
                    """

                    // Enable ECR native scan on push
                    sh """
                        aws ecr put-image-scanning-configuration \
                          --repository-name ${IMAGE_REPO} \
                          --image-scanning-configuration scanOnPush=true \
                          --region ${AWS_REGION}
                    """

                    // Login and push
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_URL}
                        docker push ${fullImage}
                    """

                    // Wait for ECR native scan to complete
                    echo "Waiting 60s for ECR native scan..."
                    sleep(time: 60, unit: 'SECONDS')

                    // Print ECR scan results (informational only)
                    sh """
                        SCAN_STATUS=\$(aws ecr describe-image-scan-findings \
                          --repository-name ${IMAGE_REPO} \
                          --image-id imageTag=${IMAGE_TAG} \
                          --region ${AWS_REGION} \
                          --query 'imageScanFindings.findingSeverityCounts' \
                          --output json 2>/dev/null || echo '{}')
                        echo "ECR Scan Results: \$SCAN_STATUS"
                    """
                }
            }
        }

        // ─────────────────────────────────────────
        // STAGE 6 — GitOps: Update image tag
        // ─────────────────────────────────────────
        stage('6. GitOps — Update Image Tag') {
            steps {
                sh """
                    git config --global user.email "jenkins@rohandevops.co.in"
                    git config --global user.name "Jenkins-CI"

                    rm -rf sspringboot-bankapp

                    git clone https://${env.GIT_TOKEN}@github.com/rohandeb2/sspringboot-bankapp.git
                    cd sspringboot-bankapp

                    sed -i 's/tag: .*/tag: "${IMAGE_TAG}"/' banking-app/values-prod.yaml

                    grep "tag:" banking-app/values-prod.yaml

                    git add banking-app/values-prod.yaml
                    git commit -m "chore: bump image tag to ${IMAGE_TAG} [skip ci]"
                    git push origin main
                """
            }
        }

    }

    // ─────────────────────────────────────────
    // POST — Notifications + AI RCA on failure
    // ─────────────────────────────────────────
    post {

        success {
            echo "Pipeline completed — image ${IMAGE_TAG} pushed, ArgoCD will deploy automatically"
            emailext(
                subject: "SUCCESS: ${env.JOB_NAME} [Build #${env.BUILD_NUMBER}]",
                body: """
                    <h3>Build Successful</h3>
                    <p><b>Job:</b> ${env.JOB_NAME}</p>
                    <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
                    <p><b>Image:</b> ${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}</p>
                    <p><b>Triggered by:</b> GitHub push to main</p>
                    <p><b>Console:</b> <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>
                    <p>ArgoCD will automatically detect the new image tag and deploy to EKS.</p>
                """,
                to: "ruhondeb28@gmail.com",
                from: "jenkins@rohandevops.co.in",
                mimeType: 'text/html'
            )
        }

        failure {
            script {
                sh """
                    curl -s "${env.BUILD_URL}consoleText" | \
                    GEMINI_API_KEY=${env.GEMINI_KEY} \
                    python3 scripts/ai_rca.py > ai_report.txt 2>/dev/null || \
                    echo "AI RCA unavailable" > ai_report.txt
                """
                def aiReport = readFile('ai_report.txt').take(2000)

                emailext(
                    subject: "FAILURE: ${env.JOB_NAME} [Build #${env.BUILD_NUMBER}]",
                    body: """
                        <h3>Build Failed</h3>
                        <p><b>Job:</b> ${env.JOB_NAME}</p>
                        <p><b>Build:</b> #${env.BUILD_NUMBER}</p>
                        <p><b>Triggered by:</b> GitHub push to main</p>
                        <p><b>Console:</b> <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>
                        <hr>
                        <h4>AI Root Cause Analysis</h4>
                        <pre>${aiReport}</pre>
                    """,
                    to: "ruhondeb28@gmail.com",
                    from: "jenkins@rohandevops.co.in",
                    mimeType: 'text/html'
                )
            }
        }

        always {
            cleanWs()
        }
    }
}