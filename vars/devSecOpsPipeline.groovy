def call(Map config = [:]) {
    pipeline {
        agent any
        
        environment {
            AWS_ACCOUNT_ID = "${config.awsAccountId}"
            AWS_REGION     = "${config.awsRegion}"
            IMAGE_REPO     = "${config.appName}"
            IMAGE_TAG      = "${env.BUILD_NUMBER}"
            SCANNER_HOME   = tool 'SonarScanner' // Matches Jenkins Global Tool Config
        }

        stages {
            stage('Initialize & Build') {
                steps {
                    println "🚀 Starting Pipeline for ${config.appName}"
                    sh "mvn clean package -DskipTests"
                }
            }

            stage('SAST - SonarQube') {
                steps {
                    script {
                        withSonarQubeEnv('SonarQube-Server') {
                            sh "mvn sonar:sonar -Dsonar.projectKey=${config.appName}"
                        }
                        // 12 LPA LOGIC: Wait for Quality Gate
                        timeout(time: 5, unit: 'MINUTES') {
                            def qg = waitForQualityGate()
                            if (qg.status != 'OK') {
                                error "Pipeline aborted due to quality gate failure: ${qg.status}"
                            }
                        }
                    }
                }
            }

            stage('SCA - OWASP FS Scan') {
                steps {
                    // Scans for vulnerable libraries (Log4j, etc.)
                    dependencyCheck additionalArguments: "--scan ./ --disableYarnAudit --format HTML", odcInstallation: 'DP-Check'
                    dependencyCheckPublisher pattern: 'dependency-check-report.html'
                }
            }

            stage('Docker Build & Security Scan') {
                steps {
                    script {
                        def fullImageName = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}"
                        
                        // Build using your Multi-Stage OTel Dockerfile
                        sh "docker build -t ${fullImageName} ."
                        
                        // TRIVY: Industry standard container scanning
                        // --exit-code 1 breaks the build if CRITICAL issues found
                        sh "trivy image --exit-code 1 --severity CRITICAL --light ${fullImageName}"
                    }
                }
            }

            stage('Push to ECR') {
                steps {
                    sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}"
                }
            }

            stage('DAST - OWASP ZAP') {
                steps {
                    // Running a baseline scan against the Preview service in K8s
                    sh "docker run --rm -t owasp/zap2docker-stable zap-baseline.py -t http://${config.appName}-preview.dev.svc.cluster.local"
                }
            }

            stage('GitOps Trigger') {
                steps {
                    script {
                        // Standard GitOps flow: Update the manifest repo
                        withCredentials([string(credentialsId: 'github-token', variable: 'GIT_TOKEN')]) {
                            sh """
                                git clone https://${GIT_TOKEN}@github.com/rohan/k8s-manifests.git
                                cd k8s-manifests/banking-app/
                                sed -i 's/tag: .*/tag: \"${IMAGE_TAG}\"/' values.yaml
                                git add values.yaml
                                git commit -m 'chore: bump ${config.appName} to ${IMAGE_TAG} [skip ci]'
                                git push origin main
                            """
                        }
                    }
                }
            }
        }
        
        post {
            always {
                cleanWs()
            }
            failure {
                println "❌ Pipeline failed for ${config.appName}. Checking logs..."
            }
        }
    }
}