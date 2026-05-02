// It automates:

// ✔ Build & unit packaging
// ✔ SAST (SonarQube code security scan)
// ✔ SCA (dependency vulnerability scan)
// ✔ Container build + image security scan
// ✔ Push image to AWS ECR
// ✔ GitOps update (ArgoCD sync trigger)
// ✔ Email notification + AI-based failure analysis


// devSecOpsPipeline.groovy
def call(Map config = [:]) {
    pipeline {
        agent any

        environment {
            AWS_ACCOUNT_ID = "${config.awsAccountId}"
            AWS_REGION     = "${config.awsRegion}"
            IMAGE_REPO     = "${config.appName}"
            IMAGE_TAG      = "${env.BUILD_NUMBER}"
            ECR_URL        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        }

        stages {
            stage('0. Configure AWS + Pull All Secrets') {
                steps {
                    script {
                        // Pull AWS credentials
                        def awsSecret = sh(
                            script: """aws secretsmanager get-secret-value \
                              --secret-id jenkins-aws-creds \
                              --region ${AWS_REGION} \
                              --query SecretString \
                              --output text""",
                            returnStdout: true
                        ).trim()

                        def awsCreds = readJSON text: awsSecret
                        env.AWS_ACCESS_KEY_ID     = awsCreds.aws_access_key_id
                        env.AWS_SECRET_ACCESS_KEY = awsCreds.aws_secret_access_key

                        // Pull Jenkins secrets
                        def jenkinsSecret = sh(
                            script: """aws secretsmanager get-secret-value \
                              --secret-id jenkins-secret \
                              --region ${AWS_REGION} \
                              --query SecretString \
                              --output text""",
                            returnStdout: true
                        ).trim()

                        def jenkinsCreds = readJSON text: jenkinsSecret
                        env.SONAR_TOKEN   = jenkinsCreds.'sonar-token'
                        env.GEMINI_KEY    = jenkinsCreds.gemini_api_key

                        // Pull GitHub credentials
                        def githubSecret = sh(
                            script: """aws secretsmanager get-secret-value \
                              --secret-id banking-github-creds \
                              --region ${AWS_REGION} \
                              --query SecretString \
                              --output text""",
                            returnStdout: true
                        ).trim()

                        def githubCreds = readJSON text: githubSecret
                        env.GIT_TOKEN = githubCreds.git_password

                        echo "All credentials pulled from Secrets Manager"
                        sh "aws sts get-caller-identity"
                    }
                }
            }

            stage('1. Build & Test') {
                steps {
                    echo "Building ${config.appName}..."
                    sh "mvn clean package -DskipTests"
                }
            }

            stage('2. Static Analysis (SAST)') {
                steps {
                    script {
                        // Use token pulled from Secrets Manager
                        sh """
                            mvn sonar:sonar \
                              -Dsonar.projectKey=${config.appName} \
                              -Dsonar.host.url=http://localhost:9000 \
                              -Dsonar.login=${env.SONAR_TOKEN}
                        """
                    }
                }
            }

            stage('3. Vulnerability Scan (SCA)') {
                steps {
                    dependencyCheck(
                        additionalArguments: "--scan ./ --format HTML",
                        odcInstallation: 'DP-Check'
                    )
                    dependencyCheckPublisher pattern: 'dependency-check-report.html'
                }
            }

            stage('4. Docker Build & Security') {
                steps {
                    script {
                        def fullImage = "${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}"
                        sh "docker build -t ${fullImage} ."
                        sh "trivy image --exit-code 1 --severity CRITICAL ${fullImage}"
                    }
                }
            }

            stage('5. Push to ECR') {
                steps {
                    script {
                        sh """
                            aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_URL}
                            docker push ${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}
                        """
                    }
                }
            }

            stage('6. GitOps: Update Manifests') {
                steps {
                    sh """
                        git config --global user.email "jenkins@rohandevops.co.in"
                        git config --global user.name "Jenkins-CI"

                        git clone https://${env.GIT_TOKEN}@github.com/rohandeb2/sspringboot-bankapp.git
                        cd sspringboot-bankapp

                        sed -i "s/tag: .*/tag: ${IMAGE_TAG}/" banking-app/values-prod.yaml

                        git add banking-app/values-prod.yaml
                        git commit -m "chore: bump ${config.appName} to ${IMAGE_TAG} [skip ci]"
                        git push origin main
                    """
                }
            }
        }

        post {
            success {
                emailext (
                    subject: "✅ SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: """<p>SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'</p>
                        <p>Check console output at: <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>""",
                    to: "${config.emailRecipient}",
                    from: "jenkins@rohandevops.co.in"
                )
            }
            failure {
                script {
                    sh """
                        curl -s ${env.BUILD_URL}consoleText | \
                        GEMINI_API_KEY=${env.GEMINI_KEY} \
                        python3 scripts/ai_rca.py > ai_report.txt
                    """
                    def aiReport = readFile('ai_report.txt')
                    emailext (
                        subject: "❌ FAILURE: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                        body: """<p>FAILED: ${env.JOB_NAME}</p>
                                <p>AI ANALYSIS: ${aiReport}</p>""",
                        to: "${config.emailRecipient}",
                        from: "jenkins@rohandevops.co.in"
                    )
                }
            }
            always {
                cleanWs()
            }
        }
    }
}