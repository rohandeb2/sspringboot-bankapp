// Jenkinsfile
node {
    // 1. Checkout the current repo so Jenkins can see the 'vars' folder
    checkout scm
    
    // 2. Load the script file
    def pipelineScript = load 'vars/devSecOpsPipeline.groovy'

    // 3. Execute the function inside the script
    pipelineScript.call(
        appName: 'springboot-bankapp',
        repoName: 'sspringboot-bankapp',
        awsAccountId: '123456789012', 
        awsRegion: 'us-east-1',
        emailRecipient: 'ruhondeb28@gmail.com'
    )
}