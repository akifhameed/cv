// Jenkinsfile — Declarative Pipeline as Code
// Code Pull, Image Build, Push Image, Deploy.
pipeline {
    agent any
    environment {
        IMAGE_NAME = 'akifhameed/cv'
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
    }
    stages {

        // Stage 1 of 4 — Code Pull
        stage('Code Pull') {
            steps {
                checkout scm
            }
        }
        // Stage 2 of 4 — Image Build
        stage('Image Build') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
            }
        }
        // Stage 3 of 4 — Push Image
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
        // Stage 4 of 4 — Deploy
        stage('Deploy') {
            steps {
                sh 'docker rm -f portfolio-cv-pipeline || true'
                sh 'docker run -d --name portfolio-cv-pipeline -p 8081:80 ${IMAGE_NAME}:${IMAGE_TAG}'
            }
        }
    }
}
