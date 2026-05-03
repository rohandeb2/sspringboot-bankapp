def pipelineScript

node {
    checkout scm
    pipelineScript = load 'vars/devSecOpsPipeline.groovy'
}

pipelineScript.call(
    appName: 'springboot-bankapp',
    repoName: 'sspringboot-bankapp',
    awsAccountId: '959589242185',
    awsRegion: 'us-east-1',
    emailRecipient: 'ruhondeb28@gmail.com'
)