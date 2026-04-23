// =============================================================================
// JENKINSFILE — CI/CD PIPELINE
// =============================================================================
// Declarative pipeline: GitHub push → build image → push ECR → deploy EKS
//
// Flow:
//   1. Checkout: fetch code from GitHub
//   2. Build:    docker buildx --platform linux/amd64 (AMD64 for EKS nodes)
//   3. Push:     authenticate to ECR, push image tagged with git SHA
//   4. Deploy:   kubectl rollout restart (K8s pulls new image, rolling update)
//   5. Verify:   wait for rollout to complete, confirm pods healthy
//
// Image tagging strategy:
//   We tag with the short git SHA (e.g. d7b544b) not "latest".
//   WHY: "latest" is ambiguous — you can't tell which commit is running.
//   SHA tags are immutable — each commit = unique image = traceable deploys.
// =============================================================================

pipeline {
    agent {
        // Run pipeline on a Kubernetes pod agent (spun up per build, killed after)
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-agent
spec:
  serviceAccountName: jenkins
  containers:
    # -----------------------------------------------------------------------
    # jnlp: Jenkins agent container (handles communication with controller)
    # This container is always required in a K8s agent pod.
    # -----------------------------------------------------------------------
    - name: jnlp
      image: jenkins/inbound-agent:latest
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"

    # -----------------------------------------------------------------------
    # docker: Docker-in-Docker sidecar
    # Provides a Docker daemon that the pipeline can use to build images.
    # privileged: true is required for DinD to work.
    # -----------------------------------------------------------------------
    - name: docker
      image: docker:28-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests:
          cpu: "200m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"

    # -----------------------------------------------------------------------
    # aws-kubectl: Alpine with kubectl + AWS CLI v2 for deploy stage
    # -----------------------------------------------------------------------
    - name: aws-kubectl
      image: alpine/k8s:1.29.12
      command: ["sleep"]
      args: ["infinity"]
      resources:
        requests:
          cpu: "100m"
          memory: "128Mi"
"""
        }
    }

    // =========================================================================
    // ENVIRONMENT VARIABLES
    // Available in all stages. Use env.VAR_NAME in Groovy.
    // =========================================================================
    environment {
        AWS_REGION      = "us-east-1"
        ECR_REGISTRY    = "890742569958.dkr.ecr.us-east-1.amazonaws.com"
        ECR_REPO        = "devops-capstone-dev"
        EKS_CLUSTER     = "devops-capstone-dev"
        K8S_NAMESPACE   = "capstone"
        K8S_DEPLOYMENT  = "devops-capstone"

        // Short git SHA — used as image tag for traceability
        // GIT_COMMIT is set automatically by Jenkins from the checkout
        IMAGE_TAG       = "${env.GIT_COMMIT?.take(7) ?: 'unknown'}"
        IMAGE_FULL      = "${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
    }

    // =========================================================================
    // PIPELINE OPTIONS
    // =========================================================================
    options {
        timeout(time: 30, unit: 'MINUTES')  // kill runaway builds
        disableConcurrentBuilds()           // no parallel deploys to same cluster
        buildDiscarder(logRotator(numToKeepStr: '10'))  // keep last 10 builds
    }

    stages {
        // =====================================================================
        // STAGE 1: CHECKOUT
        // Fetches the source code from GitHub.
        // Jenkins sets GIT_COMMIT env var automatically here.
        // =====================================================================
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    env.IMAGE_FULL = "${env.ECR_REGISTRY}/${env.ECR_REPO}:${env.IMAGE_TAG}"
                    echo "Building image: ${env.IMAGE_FULL}"
                }
            }
        }

        // =====================================================================
        // STAGE 2: BUILD
        // Builds a linux/amd64 Docker image from app/Dockerfile.
        // WHY amd64: EKS nodes are x86_64. Our Mac is ARM64.
        // Docker buildx handles cross-platform compilation.
        // =====================================================================
        stage('Build') {
            steps {
                container('docker') {
                    dir('app') {
                        sh """
                            # Wait for Docker daemon to be ready (DinD takes ~5s to start)
                            echo "Waiting for Docker daemon..."
                            until docker info > /dev/null 2>&1; do sleep 2; done
                            echo "Docker daemon ready"

                            # Install buildx plugin for cross-platform builds
                            docker buildx create --use --name multiarch 2>/dev/null || true

                            # Build for linux/amd64 (EKS node architecture)
                            docker buildx build \\
                                --platform linux/amd64 \\
                                --tag ${IMAGE_FULL} \\
                                --load \\
                                .

                            echo "Build complete: ${IMAGE_FULL}"
                            docker images ${ECR_REGISTRY}/${ECR_REPO}
                        """
                    }
                }
            }
        }

        // =====================================================================
        // STAGE 3: PUSH TO ECR
        // The docker container has Docker but not AWS CLI.
        // The aws-kubectl container has AWS CLI but not Docker.
        // Solution: get the ECR token in aws-kubectl, write it to the shared
        // workspace (/home/jenkins/agent), then use it in the docker container.
        // All containers in a pod share the same workspace volume.
        // =====================================================================
        stage('Push to ECR') {
            steps {
                // Step 1: get ECR token using IRSA (in aws-kubectl container)
                container('aws-kubectl') {
                    sh """
                        mkdir -p /home/jenkins/agent/.docker
                        ECR_TOKEN=\$(aws ecr get-login-password --region ${AWS_REGION})
                        AUTH=\$(echo -n "AWS:\$ECR_TOKEN" | base64 | tr -d '\\n')
                        echo '{\"auths\":{\"${ECR_REGISTRY}\":{\"auth\":\"'\$AUTH'\"}}}' \\
                            > /home/jenkins/agent/.docker/config.json
                        echo "ECR credentials written to shared workspace"
                    """
                }
                // Step 2: push using docker, pointing at the shared credentials
                container('docker') {
                    sh """
                        export DOCKER_CONFIG=/home/jenkins/agent/.docker
                        docker push ${IMAGE_FULL}
                        echo "Pushed: ${IMAGE_FULL}"
                    """
                }
            }
        }

        // =====================================================================
        // STAGE 4: DEPLOY TO EKS
        // Jenkins runs INSIDE the cluster → use in-cluster config directly.
        // The pod's ServiceAccount token is auto-mounted and our RBAC Role
        // grants it patch/update on Deployments in the capstone namespace.
        //
        // WHY in-cluster vs aws eks update-kubeconfig:
        //   update-kubeconfig uses an exec auth plugin (aws eks get-token) which
        //   requires the aws CLI and IRSA env vars to be available at auth time.
        //   In-cluster config uses the pod's mounted ServiceAccount token directly
        //   — simpler, always available, no external dependency.
        // =====================================================================
        stage('Deploy to EKS') {
            steps {
                container('aws-kubectl') {
                    sh """
                        # Use in-cluster config (pod ServiceAccount token, already has RBAC perms)
                        kubectl config set-cluster in-cluster \\
                            --server=https://kubernetes.default.svc \\
                            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
                        kubectl config set-credentials jenkins-sa \\
                            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
                        kubectl config set-context in-cluster \\
                            --cluster=in-cluster --user=jenkins-sa
                        kubectl config use-context in-cluster

                        # Update the deployment's image to the new SHA-tagged image
                        kubectl set image deployment/${K8S_DEPLOYMENT} \\
                            ${K8S_DEPLOYMENT}=${IMAGE_FULL} \\
                            -n ${K8S_NAMESPACE}

                        echo "Deployment updated to ${IMAGE_FULL}"
                    """
                }
            }
        }

        // =====================================================================
        // STAGE 5: VERIFY
        // Waits for the rolling update to complete (all pods on new image).
        // Fails the build if rollout doesn't complete within timeout.
        // This is your automated smoke test — if pods crash, build fails.
        // =====================================================================
        stage('Verify') {
            steps {
                container('aws-kubectl') {
                    sh """
                        echo "Waiting for rollout to complete..."
                        kubectl rollout status deployment/${K8S_DEPLOYMENT} \\
                            -n ${K8S_NAMESPACE} \\
                            --timeout=300s

                        echo "Pods after deployment:"
                        kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT}
                    """
                }
            }
        }
    }

    // =========================================================================
    // POST-BUILD ACTIONS
    // Run regardless of build result (success, failure, aborted)
    // =========================================================================
    post {
        success {
            echo "Pipeline SUCCESS — ${IMAGE_FULL} is live in ${K8S_NAMESPACE}"
        }
        failure {
            echo "Pipeline FAILED — check logs above. Rolling back if needed:"
            container('aws-kubectl') {
                sh """
                    kubectl config set-cluster in-cluster --server=https://kubernetes.default.svc --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt || true
                    kubectl config set-credentials jenkins-sa --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) || true
                    kubectl config set-context in-cluster --cluster=in-cluster --user=jenkins-sa || true
                    kubectl config use-context in-cluster || true
                    kubectl rollout undo deployment/${K8S_DEPLOYMENT} -n ${K8S_NAMESPACE} || true
                """
            }
        }
        always {
            // Clean up local Docker images to save disk space on the agent
            container('docker') {
                sh "docker rmi ${IMAGE_FULL} 2>/dev/null || true"
            }
        }
    }
}
