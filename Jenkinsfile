pipeline {
    agent {
        docker {
            image 'docker:24-cli'
            args '-v /run/podman/podman.sock:/var/run/docker.sock --privileged --entrypoint=""'
        }
    }

    environment {
        IMAGE_NAME = "ghcr.io/jaeylim/jaeylim-test-repo"
        IMAGE_TAG = "jenkins-agent-test"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Image') {
            steps {
                sh 'docker buildx build --load -t $IMAGE_NAME:$IMAGE_TAG .'
            }
        }

        stage('Login to GHCR') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr-credentials', usernameVariable: 'GHCR_USER', passwordVariable: 'GHCR_TOKEN')]) {
                    sh 'echo $GHCR_TOKEN | docker login ghcr.io -u $GHCR_USER --password-stdin'
                }
            }
        }

        stage('Push Image') {
            steps {
                sh 'docker push $IMAGE_NAME:$IMAGE_TAG'
            }
        }
    }
}
