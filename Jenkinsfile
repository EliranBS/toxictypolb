// Jenkins Multibranch Pipeline for a GitHub-hosted Spring Boot application.
//
// Required Jenkins credentials:
// - AWS_CREDENTIALS_ID: AWS access key credential with permission for ECR, ELBv2, and EC2 describe operations.
// - SSH_KEY_CREDENTIAL_ID: SSH private key credential that can connect to the EC2 instances.
//
// Required AWS/Deployment environment variables below are placeholders. Replace them in Jenkins, in a branch
// property strategy, or directly in this file for non-sensitive values only. Do not hardcode secrets.
// EC2 instances should use an IAM instance profile that allows ECR image pulls, or another secure
// non-repository mechanism for AWS CLI authentication on the instances.

def updateInstanceContainer(String instanceId) {
    def instanceIp = sh(
        script: """
            aws ec2 describe-instances \
                --region '${env.AWS_REGION}' \
                --instance-ids '${instanceId}' \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                --output text
        """,
        returnStdout: true
    ).trim()

    sshagent(credentials: [env.SSH_KEY_CREDENTIAL_ID]) {
        sh """
            set -eux
            ssh -o StrictHostKeyChecking=no '${env.SSH_USER}@${instanceIp}' \
                AWS_REGION='${env.AWS_REGION}' \
                ECR_REGISTRY='${env.ECR_REGISTRY}' \
                IMAGE_URI='${env.IMAGE_URI}' \
                'bash -s' <<'REMOTE_COMMANDS'
set -eux
aws ecr get-login-password --region "\${AWS_REGION}" | docker login --username AWS --password-stdin "\${ECR_REGISTRY}"
docker pull "\${IMAGE_URI}"
docker stop toxictypolb || true
docker rm toxictypolb || true
docker run -d --restart unless-stopped --name toxictypolb -p 8080:8080 "\${IMAGE_URI}"
REMOTE_COMMANDS
        """
    }
}

pipeline {
    agent any

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION = 'us-east-1'
        AWS_ACCOUNT_ID = '123456789012'
        AWS_CREDENTIALS_ID = 'jenkins-aws-credentials'
        ECR_REPOSITORY_NAME = 'toxictypolb'
        ALB_TARGET_GROUP_ARN = 'arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/toxictypolb/replace-me'
        EC2_INSTANCE_1_ID = 'i-replaceinstance1'
        EC2_INSTANCE_2_ID = 'i-replaceinstance2'
        SSH_USER = 'ec2-user'
        SSH_KEY_CREDENTIAL_ID = 'jenkins-ec2-ssh-key'
        ECR_IMAGE_TAG = "${BRANCH_NAME}-${BUILD_NUMBER}"
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_URI = "${ECR_REGISTRY}/${ECR_REPOSITORY_NAME}:${ECR_IMAGE_TAG}"
        LOCAL_IMAGE = "toxictypolb:${BUILD_NUMBER}"
        APP_CONTAINER = "toxictypolb-${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout from GitHub') {
            steps {
                // Jenkins Multibranch Pipeline checks out the GitHub branch that triggered the build.
                checkout scm
            }
        }

        stage('Build and test with Maven') {
            steps {
                sh 'chmod +x ./mvnw'
                sh './mvnw verify'
            }
        }

        stage('Build Docker image') {
            steps {
                sh 'docker build -t "${LOCAL_IMAGE}" .'
            }
        }

        stage('Run local container and verify APIs') {
            steps {
                sh '''
                    set -eux
                    docker rm -f "${APP_CONTAINER}" || true
                    docker run -d --name "${APP_CONTAINER}" -p 8080:8080 "${LOCAL_IMAGE}"

                    for attempt in $(seq 1 30); do
                        if curl -fsS http://localhost:8080/ >/dev/null; then
                            break
                        fi
                        sleep 2
                    done

                    curl -fsS http://localhost:8080/
                    curl -fsS http://localhost:8080/api/name | tee /tmp/toxictypolb-get-name.json
                    curl -fsS -X POST http://localhost:8080/api/name -d "name=server1" | tee /tmp/toxictypolb-post-name.json
                    curl -fsS http://localhost:8080/api/name | tee /tmp/toxictypolb-get-name-after-post.json
                    grep -q '"name":"server1"' /tmp/toxictypolb-post-name.json
                    grep -q '"name":"server1"' /tmp/toxictypolb-get-name-after-post.json
                '''
            }
            post {
                always {
                    sh 'docker rm -f "${APP_CONTAINER}" || true'
                }
            }
        }

        stage('Run Python 2.7 E2E tests') {
            steps {
                sh '''
                    set -eux
                    docker rm -f "${APP_CONTAINER}" || true
                    docker run -d --name "${APP_CONTAINER}" -p 8080:8080 "${LOCAL_IMAGE}"

                    docker run --rm --network host \
                        -v "$PWD/src/test:/tests" \
                        -w /tests \
                        python:2.7-slim \
                        sh -c 'pip install --no-cache-dir requests && python e2e_test.py localhost:8080 sanity 10'
                '''
            }
            post {
                always {
                    sh 'docker rm -f "${APP_CONTAINER}" || true'
                }
            }
        }

        stage('Authenticate to AWS ECR') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
                    '''
                }
            }
        }

        stage('Tag and push Docker image to ECR') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        docker tag "${LOCAL_IMAGE}" "${IMAGE_URI}"
                        docker push "${IMAGE_URI}"
                    '''
                }
            }
        }

        stage('Deregister EC2 instance 1 from ALB target group') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        aws elbv2 deregister-targets --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_1_ID}"
                        aws elbv2 wait target-deregistered --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_1_ID}"
                    '''
                }
            }
        }

        stage('Update and restart EC2 instance 1 container') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    script {
                        updateInstanceContainer(env.EC2_INSTANCE_1_ID)
                    }
                }
            }
        }

        stage('Register EC2 instance 1 back to ALB target group') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        aws elbv2 register-targets --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_1_ID}"
                        aws elbv2 wait target-in-service --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_1_ID}"
                    '''
                }
            }
        }

        stage('Deregister EC2 instance 2 from ALB target group') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        aws elbv2 deregister-targets --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_2_ID}"
                        aws elbv2 wait target-deregistered --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_2_ID}"
                    '''
                }
            }
        }

        stage('Update and restart EC2 instance 2 container') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    script {
                        updateInstanceContainer(env.EC2_INSTANCE_2_ID)
                    }
                }
            }
        }

        stage('Register EC2 instance 2 back to ALB target group') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
                    sh '''
                        set -eux
                        aws elbv2 register-targets --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_2_ID}"
                        aws elbv2 wait target-in-service --region "${AWS_REGION}" --target-group-arn "${ALB_TARGET_GROUP_ARN}" --targets Id="${EC2_INSTANCE_2_ID}"
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker rm -f "${APP_CONTAINER}" || true'
        }
    }
}
