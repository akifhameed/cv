# Akif Hameed — Digital CV / Portfolio

A static, accessible, mobile-responsive digital CV built with **HTML and CSS only**.

The application is packaged as a lightweight Docker image, served by **Nginx**, and deployed to **two independent Kubernetes (Minikube) clusters running on AWS EC2** — one as a stable manually-deployed baseline, one driven by a **Jenkins CI/CD pipeline**.

This repository is part of the coursework deliverable for the LSBU module **CSI_7_COD — Container Orchestration for DevOps**.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Tech Stack](#tech-stack)
3. [Project Structure](#project-structure)
4. [Branching Strategy](#branching-strategy)
5. [Docker Hub Image Strategy](#docker-hub-image-strategy)
6. [Run It Locally](#run-it-locally)
7. [EC2 #1 — Docker / Minikube Baseline (manual workflow)](#ec2-1--docker--minikube-baseline-manual-workflow)
8. [EC2 #2 — Jenkins CI/CD Pipeline (automated workflow)](#ec2-2--jenkins-cicd-pipeline-automated-workflow)
9. [Kubernetes Deployment Properties](#kubernetes-deployment-properties)
10. [Roadmap](#roadmap)
11. [Author](#author)

---

## Architecture

Two completely independent AWS EC2 instances, each with its own Minikube cluster. They share only the Docker Hub registry — never communicate directly.

```
                      GITHUB (akifhameed/portfolio-cv)
        ┌─────────────────────────────┬─────────────────────────────────┐
        │  main branch                │  develop branch                  │
        │  STABLE BASELINE             │  CI/CD TRIGGER                   │
        │  • index.html                │  Everything in main +            │
        │  • styles.css                │  • Jenkinsfile                   │
        │  • Dockerfile                │                                  │
        │  • k8s/deployment.yaml       │  Future commits here             │
        │  • k8s/service.yaml          │  trigger the Jenkins pipeline    │
        │  • README.md, .gitignore     │                                  │
        └──────────┬──────────────────┴──────────┬───────────────────────┘
                   │ manual git pull              │ webhook on push
                   ▼                              ▼
        ┌─────────────────────────────┐  ┌──────────────────────────────────┐
        │  EC2 #1 — docker-server      │  │  EC2 #2 — jenkins-server         │
        │  ──────────────────────────  │  │  ──────────────────────────────  │
        │  Docker, git, kubectl,        │  │  Docker, git, kubectl, Minikube  │
        │  Minikube                     │  │  + Java 21 + Jenkins             │
        │                               │  │                                  │
        │  Manual workflow:             │  │  Automated pipeline (4 stages):  │
        │   1. git clone main           │  │   1. Code Pull (develop)         │
        │   2. docker build :1.0        │  │   2. Image Build (:N)            │
        │   3. docker push :1.0         │  │   3. Push Image to Docker Hub    │
        │   4. kubectl apply -f k8s/    │  │   4. Deploy: kubectl apply +     │
        │                               │  │      kubectl set image to :N     │
        │  Hosts STABLE BASELINE        │  │  Hosts CI/CD-DRIVEN deployment   │
        │  (image :1.0, never changes)  │  │  (image rolls on every push)     │
        │                               │  │                                  │
        │  NodePort 30081               │  │  NodePort 30081                  │
        │  Jenkins UI port: n/a         │  │  Jenkins UI port: 8080           │
        └──────────┬────────────────────┘  └──────────────┬───────────────────┘
                   │                                       │
                   │ pulls :1.0                            │ pushes :2, :3, ...
                   │                                       │ pulls :latest tag
                   ▼                                       ▼
                   ┌────────────────────────────────────────┐
                   │      DOCKER HUB                        │
                   │   akifhameed/portfolio-cv               │
                   │   :1.0  ← manual baseline              │
                   │   :2, :3, ...  ← Jenkins build numbers │
                   └────────────────────────────────────────┘

USER (LAPTOP BROWSER):
  • Stable baseline CV:  http://<EC2_1_PUBLIC_IP>:30081
  • CI/CD live CV:       http://<EC2_2_PUBLIC_IP>:30081
  • Jenkins UI:          http://<EC2_2_PUBLIC_IP>:8080
```

The two EC2s are **deliberately decoupled**: terminating one has no effect on the other. They're snapshotted as separate AMIs for independent disaster recovery.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Markup | HTML5 |
| Styling | CSS3 (custom properties, no frameworks) |
| Web Server | Nginx (Alpine) |
| Container Runtime | Docker |
| Image Registry | Docker Hub (`akifhameed/portfolio-cv`) |
| Orchestration | Kubernetes (Minikube on AWS EC2 — two independent clusters) |
| CI/CD | Jenkins (declarative pipeline) |
| Version Control | Git + GitHub (two-branch workflow) |
| Cloud | AWS EC2 (Amazon Linux 2023, t3.large) |

No JavaScript, no build step, no transpiler — the page renders the moment Nginx serves the static files.

---

## Project Structure

```
.
├── index.html              # Single-page CV: hero, about, skills, projects, contact
├── styles.css              # Design tokens, layout, components
├── Dockerfile              # Builds nginx:1.27-alpine image with the CV inside
├── README.md               # This file
├── .gitignore
│
├── k8s/                    # Kubernetes manifests (applied by both EC2s)
│   ├── deployment.yaml     #   2 replicas, RollingUpdate, resource limits
│   └── service.yaml        #   NodePort 30081 → container port 80
│
└── Jenkinsfile             # ⚠️ ONLY on the develop branch
                            #   Declarative pipeline, 4 stages
                            #   Pull · Build · Push · Deploy
```

---

## Branching Strategy

Two-branch Git Flow with strict separation of concerns:

| Branch | Purpose | Files unique to this branch |
|---|---|---|
| `main` | **Stable baseline** consumed by EC2 #1's manual K8s workflow. Updated only via Pull Request after a successful pipeline run. | (none — main is a subset of develop) |
| `develop` | **CI/CD trigger** read by EC2 #2's Jenkins pipeline. All ongoing work commits here first. | `Jenkinsfile` |

The Jenkinsfile lives ONLY on develop because Jenkins (the build-system concern) belongs to the integration branch, not the stable production branch. The marker can compare `main` and `develop` and immediately see what's "what's running stable" versus "what triggers CI/CD".

A minimum of **5 meaningful commits** with conventional-commit-style messages (`feat:`, `chore:`, `ci:`, `docs:`) are made across the two branches.

---

## Docker Hub Image Strategy

A single repository — `akifhameed/portfolio-cv` — holds many tagged versions of the same application:

| Tag | Built by | Used by | Notes |
|---|---|---|---|
| `:1.0` | Manually, on EC2 #1 | EC2 #1's K8s baseline | Never changes — frozen baseline |
| `:2`, `:3`, `:N` | Automatically, by Jenkins on EC2 #2 | EC2 #2's K8s pipeline-driven deployment | One new tag per pipeline run; `kubectl set image` rolls the deployment to the latest tag |
| `:latest` | Automatically | (convenience pointer) | Tracks the most recent successful pipeline image |

This is the standard Docker Hub idiom: **one repo per application, many tags per version**. The two EC2s share the repository but consume different tags, so there is no contention between them.

---

## Run It Locally

The site is fully static — open the file directly:

```bash
# Windows
start index.html

# macOS
open index.html

# Linux
xdg-open index.html
```

For a more production-realistic preview that mimics the Docker container's Nginx behaviour, serve with Python's built-in HTTP server on port 8081:

```bash
python -m http.server 8081
# Then visit http://localhost:8081
```

---

## EC2 #1 — Docker / Minikube Baseline (manual workflow)

Demonstrates the **Kubernetes Requirements** of the coursework specification: the YAML manifests applied manually against a single-node Minikube cluster, satisfying the spec's properties (≥2 replicas, rolling-update strategy, resource limits, NodePort).

```bash
# 1. Install: Docker, git, kubectl, Minikube
# 2. Start the cluster
minikube start --driver=docker

# 3. Pull the source (main branch only)
git clone -b main https://github.com/akifhameed/portfolio-cv.git
cd portfolio-cv

# 4. Build and push the baseline image
docker build -t akifhameed/portfolio-cv:1.0 .
docker login
docker push akifhameed/portfolio-cv:1.0

# 5. Apply the manifests
kubectl apply -f k8s/

# 6. Verify
kubectl get pods             # 2/2 Running
kubectl get svc              # NodePort 8081:30081/TCP

# 7. Expose the service to the EC2 public interface
nohup kubectl port-forward --address 0.0.0.0 \
      svc/portfolio-cv-service 30081:8081 > ~/portfwd.log 2>&1 &

# 8. Browser:  http://<EC2_1_PUBLIC_IP>:30081
```

EC2 #1's deployment **always runs `:1.0`** — the stable baseline. It never auto-updates; it only changes if you manually re-run `kubectl apply` with a new tag.

---

## EC2 #2 — Jenkins CI/CD Pipeline (automated workflow)

Demonstrates the **Jenkins Requirements** of the coursework specification: a Pipeline-as-Code Jenkinsfile defining four declarative stages, with a GitHub webhook auto-triggering the pipeline on every push to `develop`.

### Pipeline stages

| # | Stage | Action |
|---|---|---|
| 1 | **Code Pull** | `checkout scm` — Jenkins pulls the latest `develop` commit |
| 2 | **Image Build** | `docker build -t akifhameed/portfolio-cv:${BUILD_NUMBER} .` |
| 3 | **Push Image** | `docker login` (via Jenkins credentials store), then `docker push :${BUILD_NUMBER}` and `:latest` |
| 4 | **Deploy to Kubernetes** | `kubectl apply -f k8s/` then `kubectl set image deployment/portfolio-cv-deployment portfolio-cv=...:${BUILD_NUMBER}` then `kubectl rollout status` |

### Trigger

A GitHub webhook posts to `http://<EC2_2_PUBLIC_IP>:8080/github-webhook/` on every push to `develop`. Jenkins is configured with **GitHub hook trigger for GITScm polling** so the pipeline runs automatically. (Bonus marks per the coursework spec.)

### Verification

```bash
kubectl get pods -w           # watch the rollout in real time
docker logs <container_id>    # inspect Nginx output if needed
```

The browser at `http://<EC2_2_PUBLIC_IP>:30081` reflects whatever image the most recent successful pipeline run pushed and rolled to.

---

## Kubernetes Deployment Properties

The single `k8s/deployment.yaml` (used identically on both EC2s) declares:

- **`replicas: 2`** — meets spec's "use at least 2 replicas".
- **`strategy.type: RollingUpdate`** with `maxSurge: 1` and `maxUnavailable: 1` — meets spec's "use rolling updates" with zero-downtime guarantee.
- **`resources.requests`** (50m CPU, 32Mi memory) and **`resources.limits`** (200m CPU, 128Mi memory) — meets spec's "include resource limits".
- Container port: 80 (Nginx default inside the container).

The `k8s/service.yaml` declares:

- **`type: NodePort`** with `nodePort: 30081`, `port: 8081`, `targetPort: 80` — meets spec's "be accessible via NodePort or LoadBalancer".

Same manifests, two clusters, two demonstrations of the spec being satisfied.

---

## Roadmap

- [ ] Initialise repo with `main` + `develop` branches.
- [ ] Add static portfolio (`index.html`, `styles.css`) — first commit on `main`.
- [ ] Add `Dockerfile` to `main`.
- [ ] Add `k8s/deployment.yaml` + `k8s/service.yaml` to `main`.
- [ ] Branch `develop` from `main` and add `Jenkinsfile`.
- [ ] Launch **EC2 #1** (`docker-server`) and execute manual workflow.
- [ ] Capture the EC2 #1 environment as **AMI #1**.
- [ ] Launch **EC2 #2** (`jenkins-server`) and install Jenkins.
- [ ] Configure Jenkins pipeline pointing at the `develop` branch.
- [ ] Configure GitHub webhook → Jenkins (bonus marks).
- [ ] Trigger end-to-end demo commit on `develop` → live rollout on EC2 #2.
- [ ] Capture the EC2 #2 environment as **AMI #2**.
- [ ] Final `develop → main` merge via Pull Request.

---

## Author

**Akif Hameed**
GitHub: [@akifhameed](https://github.com/akifhameed)

This repository was created as part of academic coursework for the **CSI_7_COD — Container Orchestration for DevOps** module at London South Bank University.
