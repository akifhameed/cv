// Jenkinsfile — Declarative Pipeline as Code
// Four stages: Code Pull, Image Build, Push Image, Deploy.
// Stage 4 deploys to BOTH:

pipeline {
    agent any

    environment {
        IMAGE_NAME       = 'akifhameed/cv'
        IMAGE_TAG        = "${env.BUILD_NUMBER}"
        EC2_1_PRIVATE_IP = '172.31.80.6'   // private IP
    }

    stages {

        stage('Code Pull') {
            steps {
                checkout scm
            }
        }

        stage('Image Build') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_PASS')]) {
                    sh 'echo $DH_PASS | docker login -u $DH_USER --password-stdin'
                    sh 'docker push ${IMAGE_NAME}:${IMAGE_TAG}'
                }
            }
        }

        stage('Deploy') {
            steps {
                sh 'docker rm -f portfolio-cv-pipeline || true'
                sh 'docker run -d --name portfolio-cv-pipeline -p 8081:80 ${IMAGE_NAME}:${IMAGE_TAG}'

                sh '''
                    ssh -o StrictHostKeyChecking=no ec2-user@${EC2_1_PRIVATE_IP} \
                        "kubectl set image deployment/portfolio-cv-deployment \
                         portfolio-cv=${IMAGE_NAME}:${IMAGE_TAG}"

                    ssh -o StrictHostKeyChecking=no ec2-user@${EC2_1_PRIVATE_IP} \
                        "kubectl rollout status deployment/portfolio-cv-deployment --timeout=120s"
                '''
            }
        }
    }
}
