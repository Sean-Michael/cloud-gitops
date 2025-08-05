# Deployment script for different clouds
#!/bin/bash
# deploy.sh - Deploy to any cloud provider

set -e

CLOUD_PROVIDER=${1:-"azure"}
ENVIRONMENT=${2:-"dev"}
GITOPS_REPO=${3:-"https://github.com/your-org/k8s-gitops"}

echo "Deploying to $CLOUD_PROVIDER in $ENVIRONMENT environment"

# Install ArgoCD if not present
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo "Installing ArgoCD..."
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
fi

# Create the bootstrap application with environment-specific values
cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps-${ENVIRONMENT}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${GITOPS_REPO}
    path: environments/${ENVIRONMENT}
    targetRevision: HEAD
    helm:
      parameters:
      - name: cloudProvider
        value: ${CLOUD_PROVIDER}
      - name: environment
        value: ${ENVIRONMENT}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "Bootstrap application created!"
echo "ArgoCD will now sync all infrastructure and applications"

# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"

# Port forward to access ArgoCD UI
echo "Access ArgoCD at http://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0