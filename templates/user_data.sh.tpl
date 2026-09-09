#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/bootstrap.log) 2>&1

# 1. Instala o k3s single-node
#    --write-kubeconfig-mode 644 : permite ler o kubeconfig sem sudo (facilita o scp depois)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

KUBECTL="/usr/local/bin/k3s kubectl"

# 2. Espera o node ficar Ready antes de continuar
until $KUBECTL get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 5
done

# 3. Namespace da aplicacao + secret de pull do GHCR
#    (criado aqui, fora do git, para nao commitar credencial nenhuma no repo GitOps)
$KUBECTL create namespace escapa-prod --dry-run=client -o yaml | $KUBECTL apply -f -

$KUBECTL create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username='${github_username}' \
  --docker-password='${github_pat}' \
  -n escapa-prod \
  --dry-run=client -o yaml | $KUBECTL apply -f -

# 4. Namespace + secret de credenciais do Cloudflare Tunnel
#    credentials.json e o formato que o cloudflared espera para se autenticar
#    (AccountTag + TunnelSecret + TunnelID -- os tres definidos no Terraform)
$KUBECTL create namespace cloudflared --dry-run=client -o yaml | $KUBECTL apply -f -

cat > /tmp/credentials.json << EOC
{
  "AccountTag": "${cf_account_tag}",
  "TunnelSecret": "${cf_tunnel_secret_b64}",
  "TunnelID": "${cf_tunnel_id}"
}
EOC

$KUBECTL create secret generic cloudflared-credentials \
  --from-file=credentials.json=/tmp/credentials.json \
  -n cloudflared \
  --dry-run=client -o yaml | $KUBECTL apply -f -

rm -f /tmp/credentials.json

# 5. Instala o ArgoCD
$KUBECTL create namespace argocd
$KUBECTL apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Espera o argocd-server subir
until $KUBECTL -n argocd get deploy argocd-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; do
  sleep 5
done

%{ if gitops_repo_url != "" }
# 6. Clona o repo GitOps e aplica os dois App-of-Apps raiz (infra + apps)
#    Os secrets acima ja existem nos namespaces certos, entao os pods do
#    backend/frontend/cloudflared sobem direto sem ficar esperando nada.
apt-get update -y
apt-get install -y git
git clone ${gitops_repo_url} /opt/gitops-escapa
$KUBECTL apply -f /opt/gitops-escapa/bootstrap/infrastructure-root.yaml
$KUBECTL apply -f /opt/gitops-escapa/bootstrap/apps-root.yaml
%{ endif }

echo "bootstrap concluido em $(date)" > /var/log/bootstrap-done.log
