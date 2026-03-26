def call(Map config = [:]) {
    pipeline {
        agent { label 'maven' }
        
        options {
            githubProjectProperty(projectUrlStr: "https://github.com/rohandeb2/${config.repoName}/")
            buildDiscarder(logRotator(numToKeepStr: '10'))   # Keep only the last 10 builds to save space
        }
    
        triggers {
            githubPush()
        }

        environment {
            AWS_ACCOUNT_ID = "${config.awsAccountId}"
            AWS_REGION     = "${config.awsRegion}"
            IMAGE_REPO     = "${config.appName}"
            IMAGE_TAG      = "${env.BUILD_NUMBER}"
        }

        stages {
            stage('Initialize & Build') {
                steps {
                    container('maven') {
                        println "🚀 Starting Build for ${config.appName}"
                        sh "mvn clean package -DskipTests"
                    }
                }
            }

            stage('SAST - SonarQube') {
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

            stage('SCA - OWASP Scan') {
                steps {
                    // This uses the Jenkins Plugin directly, no container block needed
                    dependencyCheck additionalArguments: "--scan ./ --format HTML", odcInstallation: 'DP-Check'
                    dependencyCheckPublisher pattern: 'dependency-check-report.html'
                }
            }

            stage('Docker Build & Security Scan') {
                steps {
                    container('tools') { // Uses the container with Docker & Trivy installed
                        script {
                            def fullImageName = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}"
                            
                            sh "docker build -t ${fullImageName} ."
                            
                            // Trivy Scan - Will fail build if CRITICAL vulnerabilities are found
                            sh "trivy image --exit-code 1 --severity CRITICAL ${fullImageName}"
                        }
                    }
                }
            }

            stage('Push to ECR') {
                steps {
                    container('tools') { // Uses the container with AWS CLI
                        sh """
                            aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                            
                            docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}
                        """
                    }
                }
            }

            stage('GitOps Trigger') {
                steps {
                    container('tools') {
                        script {
                            withCredentials([string(credentialsId: 'github-token', variable: 'GIT_TOKEN')]) {
                                sh """
                                    git clone https://${GIT_TOKEN}@github.com/rohandeb2/sspringboot-bankapp.git
                                    cd sspringboot-bankapp/k8s-manifests/banking-platform/
                                    sed -i 's/tag: .*/tag: "${IMAGE_TAG}"/' values.yaml
                                    
                                    git config user.email "jenkins@rohandevops.co.in"
                                    git config user.name "Jenkins CI"
                                    git add values.yaml
                                    git commit -m "chore: bump ${config.appName} to ${IMAGE_TAG} [skip ci]"
                                    git push origin main
                                """
                            }
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
                    to: "rohan-admin@example.com", // Replace with your email
                    from: "jenkins@rohandevops.co.in"
                )
            }
            failure {
                emailext (
                    subject: "❌ FAILURE: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                    body: """<p>FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'</p>
                        <p>Check console output at: <a href='${env.BUILD_URL}'>${env.BUILD_URL}</a></p>""",
                    to: "rohan-admin@example.com",
                    from: "jenkins@rohandevops.co.in"
                )
            }
            always {
                cleanWs()
            }
        }
    }
}