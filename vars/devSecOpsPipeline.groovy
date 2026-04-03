// devSecOpsPipeline.groovy
def call(Map config = [:]) {
    pipeline {
        agent { label 'banking-agent' }

        environment {
            AWS_ACCOUNT_ID = "${config.awsAccountId}"
            AWS_REGION     = "${config.awsRegion}"
            IMAGE_REPO     = "${config.appName}"
            IMAGE_TAG      = "${env.BUILD_NUMBER}"
            ECR_URL        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        }

        stages {
            stage('1. Build & Test') {
                steps {
                    container('maven') {
                        echo "🚀 Building ${config.appName}..."
                        sh "mvn clean package -DskipTests"
                    }
                }
            }

            stage('2. Static Analysis (SAST)') {
                steps {
                    container('maven') {
                        script {
                            withSonarQubeEnv('SonarQube-Server') {
                                sh "mvn sonar:sonar -Dsonar.projectKey=${config.appName}"
                            }
                            timeout(time: 5, unit: 'MINUTES') {
                                def qg = waitForQualityGate()
                                if (qg.status != 'OK') {
                                    error "Pipeline aborted due to quality gate failure: ${qg.status}"
                                }
                            }
                        }
                    }
                }
            }

            stage('3. Vulnerability Scan (SCA)') {
                steps {
                    // Plugin-based SCA doesn't need a container block
                    dependencyCheck additionalArguments: "--scan ./ --format HTML", odcInstallation: 'DP-Check'
                    dependencyCheckPublisher pattern: 'dependency-check-report.html'
                }
            }

            stage('4. Docker Build & Security') {
                steps {
                    script {
                        def fullImage = "${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}"
                        
                        container('docker-client') {
                            sh "docker build -t ${fullImage} ."
                        }
                        container('trivy') {
                            sh "trivy image --exit-code 1 --severity CRITICAL ${fullImage}"
                        }
                    }
                }
            }

            stage('5. Push to ECR') {
                steps {
                    script {
                        def loginPass = ""
                        container('aws-cli') {
                            loginPass = sh(script: "aws ecr get-login-password --region ${AWS_REGION}", returnStdout: true).trim()
                        }
                        container('docker-client') {
                            sh "echo ${loginPass} | docker login --username AWS --password-stdin ${ECR_URL}"
                            sh "docker push ${ECR_URL}/${IMAGE_REPO}:${IMAGE_TAG}"
                        }
                    }
                }
            }

            stage('6. GitOps: Update Manifests') {
                steps {
                    container('docker-client') { 
                        withCredentials([string(credentialsId: 'github-token', variable: 'GIT_TOKEN')]) {
                            sh """
                                git config --global user.email "jenkins@rohandevops.co.in"
                                git config --global user.name "Jenkins-CI"
                                
                                git clone https://${GIT_TOKEN}@github.com/${config.gitUser}/${config.gitOpsRepo}.git
                                cd ${config.gitOpsRepo}
                                
                                # Targeted update for your specific app tag
                                sed -i "s/tag: .*/tag: ${IMAGE_TAG}/" values-prod.yaml
                                
                                git add values-prod.yaml
                                git commit -m "chore: bump ${config.appName} to ${IMAGE_TAG} [skip ci]"
                                git push origin main
                            """
                        }
                    }
                }
            }
        }
        
        post {
            success {
                emailext (
                    subject: "✅ SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: """<p>SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'</p>
                        <p>Check console output at: <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>""",
                    to: "ruhondeb28@gmail.com", // Replace with your email
                    from: "jenkins@rohandevops.co.in"
                )
            }
            failure {
                withCredentials([string(credentialsId: 'GEMINI_API_KEY', variable: 'GEMINI_API_KEY')]) {
                    script {
                        // Fetch logs and pipe to AI script
                        sh "curl -u admin:password ${env.BUILD_URL}consoleText | python3 scripts/ai_rca.py > ai_report.txt"
                        def aiReport = readFile('ai_report.txt')
                        
                        emailext (
                            subject: "❌ FAILURE: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                            body: """<p>FAILED: ${env.JOB_NAME}</p>
                                    <p>AI ANALYSIS: ${aiReport}</p>""",
                            to: "ruhondeb28@gmail.com", // From your Jenkinsfile
                            from: "jenkins@rohandevops.co.in"
                        )
                    }
                }
            }
            always {
                cleanWs() # Clean up workspace after every build to save space and avoid conflicts
            }
        }
    }
}