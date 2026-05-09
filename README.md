# Akif Hameed, Digital CV / Portfolio

A static, accessible, mobile-responsive digital CV built with **HTML and CSS only**.

The application is packaged as a lightweight Docker image, served by **Nginx**, and deployed to a **Minikube Kubernetes cluster on AWS EC2**, continuously delivered through a **Jenkins declarative pipeline** triggered by a **GitHub webhook**, and rolled out to the live cluster through an **SSH bridge** between the Jenkins server and the Kubernetes server.

This repository is part of the coursework deliverable for the LSBU module **CSI_7_COD, Container Orchestration for DevOps**.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Tech Stack](#tech-stack)
3. [Project Structure](#project-structure)
4. [Branching Strategy](#branching-strategy)
5. [Docker Hub Image Strategy](#docker-hub-image-strategy)
6. [Run It Locally](#run-it-locally)
7. [Kubernetes Server, Manual Baseline](#kubernetes-server-manual-baseline)
8. [Jenkins Server, CI/CD Pipeline](#jenkins-server-cicd-pipeline)
9. [Kubernetes Deployment Properties](#kubernetes-deployment-properties)
10. [Author](#author)

---

## Architecture

The runtime is split across **two AWS EC2 servers**, the **Kubernetes server** and the **Jenkins server**, with a clean separation of concerns. The two servers communicate only through Docker Hub for image distribution and through a single SSH key for the remote `kubectl` deployment step. Only the Kubernetes server hosts a Minikube cluster; the Jenkins server hosts the controller and a verification Docker container.

```
                      GITHUB (akifhameed/cv)
        +-----------------------------+----------------------------------+
        |  main branch                |  develop branch                  |
        |  STABLE BASELINE            |  CI/CD TRIGGER                   |
        |  * index.html               |  Everything in main +            |
        |  * styles.css               |  * Jenkinsfile                   |
        |  * Dockerfile               |                                  |
        |  * k8s/deployment.yaml      |  Every push here fires           |
        |  * k8s/service.yaml         |  the Jenkins pipeline            |
        |  * README.md, .gitignore    |                                  |
        +-------------+---------------+------------+---------------------+
                      | manual git pull             | webhook on push
                      v                             v
        +-----------------------------+   +----------------------------------+
        |  Kubernetes server (EC2)    |   |  Jenkins server (EC2)            |
        |  Docker, Git, kubectl,      |   |  Docker, Git, Java 21, Jenkins   |
        |  Minikube                   |   |                                  |
        |                             |   |  4-stage declarative pipeline:   |
        |  Manual workflow:           |   |   1. Code Pull (develop)         |
        |   1. git clone main         |   |   2. Image Build (:N)            |
        |   2. docker build :1.0      |   |   3. Push Image to Docker Hub    |
        |   3. docker push :1.0       |   |   4. Deploy:                     |
        |   4. kubectl apply -f k8s/  |   |      a) docker run on Jenkins    |
        |                             |   |         server (verification)    |
        |  Hosts the live Minikube    |   |      b) ssh + kubectl set image  |
        |  Deployment (image tag      |   |         on Kubernetes server     |
        |  rolls when Jenkins drives  |   |         (rolling update)         |
        |  it via SSH)                |   |                                  |
        |                             |   |  Jenkins UI port: 8080           |
        |  NodePort: 30081            |   |                                  |
        +-------------+---------------+   +----------+-----------------------+
                      ^                              |
                      |  ssh ec2-user@<priv-ip>      |
                      |  kubectl set image           |
                      |  kubectl rollout status      |
                      +------------------------------+
                      |                              |
                      | pulls :1.0 (manual)          | pushes :2, :3, ...
                      | pulls :N (rolling update)    |
                      v                              v
                   +------------------------------------------+
                   |              DOCKER HUB                  |
                   |        akifhameed/cv                     |
                   |   :1.0          (manual baseline)        |
                   |   :2, :3, ...   (Jenkins build numbers)  |
                   +------------------------------------------+

USER (LAPTOP BROWSER):
  * Live CV (Kubernetes):  http://<KUBERNETES_SERVER_PUBLIC_IP>:30081
  * Verification container: http://<JENKINS_SERVER_PUBLIC_IP>:8081
  * Jenkins UI:             http://<JENKINS_SERVER_PUBLIC_IP>:8080
```

The two servers are **deliberately decoupled at the level of the operating system** but **connected at the level of the pipeline** through the SSH bridge. Each server is snapshotted as its own AMI for independent disaster recovery.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Markup | HTML5 |
| Styling | CSS3 (custom properties, no frameworks) |
| Web Server | Nginx (Alpine) |
| Container Runtime | Docker |
| Image Registry | Docker Hub (`akifhameed/cv`) |
| Orchestration | Kubernetes (Minikube on AWS EC2) |
| CI/CD | Jenkins (declarative pipeline) |
| Remote Orchestration | SSH (jenkins user public key authorised on the Kubernetes server's ec2-user) |
| Version Control | Git + GitHub (two-branch workflow) |
| Cloud | AWS EC2 (Amazon Linux 2023, t3.large) |

No JavaScript, no build step, no transpiler. The page renders the moment Nginx serves the static files.

---

## Project Structure

```
.
+-- index.html              # Single-page CV: hero, about, skills, projects, contact
+-- styles.css              # Design tokens, layout, components
+-- Dockerfile              # Builds nginx:1.27-alpine image with the CV inside
+-- README.md               # This file
+-- .gitignore
|
+-- k8s/                    # Kubernetes manifests (applied on the Kubernetes server)
|   +-- deployment.yaml     #   2 replicas, RollingUpdate, resource limits
|   +-- service.yaml        #   NodePort 30081, port 8081, targetPort 80
|
+-- Jenkinsfile             # ONLY on the develop branch
                            #   Declarative pipeline, 4 stages
                            #   Pull, Build, Push, Deploy (local + remote)
```

---

## Branching Strategy

Two-branch Git Flow with strict separation of concerns:

| Branch | Purpose | Files unique to this branch |
|---|---|---|
| `main` | **Stable baseline** consumed by the Kubernetes server's manual workflow. Updated only via Pull Request after a successful pipeline run. | (none, main is a strict subset of develop) |
| `develop` | **CI/CD trigger** read by the Jenkins server's pipeline. All ongoing work commits here first. | `Jenkinsfile` |

The Jenkinsfile lives ONLY on `develop` because Jenkins (the build-system concern) belongs to the integration branch, not the stable production branch. A reviewer can compare `main` and `develop` and immediately see what is running as the stable baseline versus what triggers CI/CD.

A minimum of **5 meaningful commits** with conventional-commit-style messages (`feat:`, `chore:`, `ci:`, `docs:`) are made across the two branches.

---

## Docker Hub Image Strategy

A single repository, `akifhameed/cv`, holds many tagged versions of the same application:

| Tag | Built by | Used by | Notes |
|---|---|---|---|
| `:1.0` | Manually, on the Kubernetes server | The Kubernetes baseline | Frozen baseline, never auto-updated |
| `:2`, `:3`, `:N` | Automatically, by Jenkins | The same Kubernetes Deployment after Jenkins drives `kubectl set image` over SSH | One new tag per pipeline run, providing a versioned audit trail of every change |

This is the standard Docker Hub idiom: one repository per application, many tags per version. The build number, bound to `${env.BUILD_NUMBER}` inside the Jenkinsfile, makes every successful run reproducible by tag.

---

## Run It Locally

The site is fully static, so the simplest preview is to open the file directly:

```bash
# Windows
start index.html

# macOS
open index.html

# Linux
xdg-open index.html
```

For a more production-realistic preview that mimics the Docker container's Nginx behaviour, serve with Python's built-in HTTP server:

```bash
python -m http.server 8000
# Then visit http://localhost:8000
```

---

## Kubernetes Server, Manual Baseline

The Kubernetes server demonstrates the **Kubernetes Requirements** of the coursework specification: the YAML manifests applied manually against a single-node Minikube cluster, satisfying the spec's properties (at least 2 replicas, rolling-update strategy, resource limits, NodePort).

```bash
# 1. Install: Docker, Git, kubectl, Minikube
# 2. Start the cluster
minikube start --driver=docker

# 3. Pull the source (main branch only)
git clone -b main https://github.com/akifhameed/cv.git
cd cv

# 4. Build and push the baseline image
docker build -t akifhameed/cv:1.0 .
docker login
docker push akifhameed/cv:1.0

# 5. Apply the manifests
kubectl apply -f k8s/

# 6. Verify
kubectl get pods             # 2/2 Running
kubectl get svc              # NodePort 8081:30081/TCP

# 7. Expose the service to the EC2 public interface
nohup kubectl port-forward --address 0.0.0.0 \
      svc/portfolio-cv-service 30081:8081 > ~/portfwd.log 2>&1 &

# 8. Browser:  http://<KUBERNETES_SERVER_PUBLIC_IP>:30081
```

The Kubernetes baseline runs `:1.0` until Jenkins drives a rolling update via the SSH bridge described in the next section.

---

## Jenkins Server, CI/CD Pipeline

The Jenkins server demonstrates the **Jenkins Requirements** of the coursework specification: a Pipeline-as-Code Jenkinsfile defining four declarative stages, with a GitHub webhook auto-triggering the pipeline on every push to `develop`.

### Pipeline stages

| # | Stage | Action |
|---|---|---|
| 1 | **Code Pull** | `checkout scm`, Jenkins pulls the latest `develop` commit |
| 2 | **Image Build** | `docker build -t akifhameed/cv:${BUILD_NUMBER} .` |
| 3 | **Push Image** | `docker login` via Jenkins credentials store, then `docker push akifhameed/cv:${BUILD_NUMBER}` |
| 4 | **Deploy** | (a) Local verification: `docker run -d --name portfolio-cv-pipeline -p 8081:80 …` on the Jenkins server. (b) Remote rolling update: `ssh ec2-user@<KUBERNETES_SERVER_PRIVATE_IP> "kubectl set image deployment/portfolio-cv-deployment portfolio-cv=akifhameed/cv:${BUILD_NUMBER}"` followed by `kubectl rollout status deployment/portfolio-cv-deployment --timeout=120s`. |

### Trigger

A GitHub webhook posts to `http://<JENKINS_SERVER_PUBLIC_IP>:8080/github-webhook/` on every push to `develop`. Jenkins is configured with **GitHub hook trigger for GITScm polling** so the pipeline runs automatically. (Bonus marks per the coursework spec.)

### SSH bridge

The remote `kubectl` calls in Stage 4 are made possible by an SSH key generated on the Jenkins server as the jenkins user, with the public key authorised on the Kubernetes server's `~ec2-user/.ssh/authorized_keys`. The Jenkinsfile uses the **private VPC IP** of the Kubernetes server, which is stable across AWS Academy Stop and Start cycles, instead of the public IP, which is not.

### Verification

```bash
# On the Kubernetes server, watch the rollout in real time:
kubectl get pods -w

# On the Jenkins server, the local verification container:
docker logs portfolio-cv-pipeline
```

The browser at `http://<KUBERNETES_SERVER_PUBLIC_IP>:30081` reflects whatever image the most recent successful pipeline run pushed and rolled to.

---

## Kubernetes Deployment Properties

The single `k8s/deployment.yaml`, applied on the Kubernetes server, declares:

- **`replicas: 2`**, meets the spec's "use at least 2 replicas".
- **`strategy.type: RollingUpdate`** with `maxSurge: 1` and `maxUnavailable: 1`, meets the spec's "use rolling updates" with a zero-downtime guarantee.
- **`resources.requests`** (50m CPU, 32Mi memory) and **`resources.limits`** (200m CPU, 128Mi memory), meets the spec's "include resource limits".
- Container port: 80 (Nginx default inside the container).

The `k8s/service.yaml` declares:

- **`type: NodePort`** with `nodePort: 30081`, `port: 8081`, `targetPort: 80`, meets the spec's "be accessible via NodePort or LoadBalancer".

The same manifests govern the cluster across both the manual baseline and the Jenkins-driven rolling update; only the image tag changes between deployments.

---

## Author

**Akif Hameed**
GitHub: [@akifhameed](https://github.com/akifhameed)

This repository was created as part of academic coursework for the **CSI_7_COD, Container Orchestration for DevOps** module at London South Bank University.
