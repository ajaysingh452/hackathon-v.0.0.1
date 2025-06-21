#!/bin/bash
set -e

# --- Docker Daemon Detection ---
DOCKER="docker"  # default
USE_DOCKER_EXE=false

# Try standard WSL Docker socket
if ! docker ps > /dev/null 2>&1; then
  export DOCKER_HOST=unix:///mnt/wsl/shared-docker/docker.sock
  if ! docker ps > /dev/null 2>&1; then
    echo "⚠️ Docker socket in WSL is not accessible."

    # Try Windows-native Docker CLI fallback
    if [ -x "/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe" ]; then
      DOCKER="/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"
      USE_DOCKER_EXE=true
      echo "✅ Using Windows-native docker.exe at: $DOCKER"
    else
      echo "❌ Docker is not accessible from WSL. Please start Docker Desktop and enable WSL integration."
      exit 1
    fi
  else
    echo "✅ Connected to Docker via WSL shared socket."
  fi
else
  echo "✅ Docker is already working in WSL."
fi

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$ROOT_DIR/web"
echo "✅ Script Directory: "$SCRIPT_DIR""
echo "✅ Root Directory: "$ROOT_DIR""
echo "✅ Site Directory: "$SITE_DIR""

# --- Load .env if exists ---
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

# --- User Inputs ---
read -p "Namespace [${NAMESPACE:-apps}]: " input_namespace
NAMESPACE="${input_namespace:-${NAMESPACE:-apps}}"

read -p "App Name [${APP_NAME:-hackathon}]: " input_app
APP_NAME="${input_app:-${APP_NAME:-hackathon}}"

read -p "Ingress Host [${INGRESS_HOST:-apps.inichepro.in}]: " input_host
INGRESS_HOST="${input_host:-${INGRESS_HOST:-apps.inichepro.in}}"

read -p "Ingress Path [/${INGRESS_PATH:-hackathon}]: " input_path
INGRESS_PATH="/${input_path:-${INGRESS_PATH:-hackathon}}"

# --- Docker Build ---
IMAGE_TAG="v$(date +%s)"
echo "🛠 Building Docker image: ${APP_NAME}:${IMAGE_TAG}"
"$DOCKER" build -t ${APP_NAME}:${IMAGE_TAG} -f "$SCRIPT_DIR/Dockerfile" "$ROOT_DIR"

# --- Kubernetes Resources ---
echo "🚀 Deploying to Kubernetes namespace: $NAMESPACE"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${APP_NAME}:${IMAGE_TAG}
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}-ingress
  namespace: ${NAMESPACE}
  annotations: {}
spec:
  ingressClassName: nginx
  rules:
    - host: ${INGRESS_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${APP_NAME}
                port:
                  number: 80
EOF

echo "🚀 Rollout restart deployment. Starting..."
kubectl rollout restart deployment ${APP_NAME} -n ${NAMESPACE}
echo "✅ Rollout restart deployment. Completed"
echo ""
echo "✅ Deployment complete!"
echo "🌐 Access your app at: http://${INGRESS_HOST}${INGRESS_PATH}"
