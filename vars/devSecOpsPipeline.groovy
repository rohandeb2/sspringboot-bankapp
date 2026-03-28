def call(Map config = [:]) {  # create a function that can take some key value pairs and if nothing is given, use empty strings as defaults
    pipeline {
        agent { label 'maven' }
        
        # it link the jenkins job with the github repository and keep only the last 10 builds to save space
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
                        sh "mvn clean package -DskipTests"   # -DskipTests is used to skip the tests during the build phase, we will run them in a separate stage for better visibility and control
                    }
                }
            }

            stage('SAST - SonarQube') {
                steps {
                    container('maven') { # run inside container
                        script {   # Allows writing custom Groovy logic (like variables, conditions, etc.)
                            withSonarQubeEnv('SonarQube-Server') {   #Use SonarQube server configuration stored in Jenkins
                                sh "mvn sonar:sonar -Dsonar.projectKey=${config.appName}"
                            }
                            timeout(time: 5, unit: 'MINUTES') {
                                def qg = waitForQualityGate()  # wait for sonarqube to finish and get the quality gate result
                                if (qg.status != 'OK') {
                                    error "Pipeline aborted due to quality gate failure: ${qg.status}"
                                }
                            }
                        }
                    }
                }
            }
            # It checks your project’s dependencies (libraries) for known security vulnerabilities using OWASP Dependency Check
            stage('SCA - OWASP Scan') {
                steps {
                    // This uses the Jenkins Plugin directly, no container block needed
                    dependencyCheck additionalArguments: "--scan ./ --format HTML", odcInstallation: 'DP-Check'  #Scan this project and generate a vulnerability report
                    dependencyCheckPublisher pattern: 'dependency-check-report.html'   # Show the generated report in Jenkins UI
                }
            }

            stage('Docker Build & Security Scan') {
                steps {
                    container('tools') { // Uses the container with Docker & Trivy installed
                        script {
                            def fullImageName = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}" # Construct the full ECR image name using environment variables
                            
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
                            withCredentials([string(credentialsId: 'github-token', variable: 'GIT_TOKEN')]) { #Fetch GitHub token securely from Jenkins
                                sh """
                                    git clone https://${GIT_TOKEN}@github.com/rohandeb2/sspringboot-bankapp.git
                                    cd sspringboot-bankapp/k8s-manifests/banking-platform/
                                    sed -i 's/tag: .*/tag: "${IMAGE_TAG}"/' values.yaml
                                    
                                    # when jenkins makes a commit it require author name and email so that it can show in git history
                                    git config user.email "jenkins@rohandevops.co.in"
                                    git config user.name "Jenkins CI"

                                    git add values.yaml
                                    git commit -m "chore: bump ${config.appName} to ${IMAGE_TAG} [skip ci]" #chore means non feature change and bump means increase/decrease version
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