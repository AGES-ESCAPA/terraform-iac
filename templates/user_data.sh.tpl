#!/bin/bash
# Não habilite xtrace (set -x): este script manipula credenciais.
set -euo pipefail

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

# 4. Namespace + token do túnel gerenciado remotamente pela Cloudflare.
$KUBECTL create namespace cloudflared --dry-run=client -o yaml | $KUBECTL apply -f -

(
  umask 077
  tunnel_token_file="$(mktemp)"
  trap 'rm -f -- "$tunnel_token_file"' EXIT
  printf '%s' '${cf_tunnel_token_b64}' | base64 --decode > "$tunnel_token_file"
  test -s "$tunnel_token_file"
  $KUBECTL create secret generic cloudflared-credentials \
    --from-file=token="$tunnel_token_file" \
    -n cloudflared \
    --dry-run=client -o yaml | $KUBECTL apply --server-side -f -
)

# 5. Instala o ArgoCD
$KUBECTL create namespace argocd
# Server-side apply evita exceder o limite de 256 KiB da anotação last-applied nas CRDs.
$KUBECTL apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Espera o argocd-server subir
until $KUBECTL -n argocd get deploy argocd-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; do
  sleep 5
done

%{ if gitops_repo_url != "" }
# 6. Prepara o repositório GitOps e suas credenciais no ArgoCD.
apt-get update -y
apt-get install -y git
GITOPS_REPO_URL="$(printf '%s' '${gitops_repo_url_b64}' | base64 --decode)"

%{ if gitops_token_b64 != "" }
# O token fica em um diretório temporário acessível apenas por root.
# GIT_ASKPASS evita incluir a credencial na URL, nos argumentos do git ou no remote salvo.
gitops_credentials_dir="$(mktemp -d)"
trap 'rm -rf -- "$gitops_credentials_dir"' EXIT
printf '%s' '${gitops_token_b64}' | base64 --decode > "$gitops_credentials_dir/token"
chmod 600 "$gitops_credentials_dir/token"
cat > "$gitops_credentials_dir/askpass" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'x-access-token' ;;
  *Password*) cat "$GITOPS_TOKEN_FILE" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$gitops_credentials_dir/askpass"

LC_ALL=C GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS="$gitops_credentials_dir/askpass" \
  GITOPS_TOKEN_FILE="$gitops_credentials_dir/token" \
  git -c credential.helper= clone -- "$GITOPS_REPO_URL" /opt/gitops-escapa

# O ArgoCD precisa de sua própria configuração de acesso ao repositório privado.
# O Secret é criado antes dos Applications raiz, sem imprimir seu conteúdo no log.
$KUBECTL create secret generic gitops-repository \
  --namespace=argocd \
  --from-literal=type=git \
  --from-literal=url="$GITOPS_REPO_URL" \
  --from-literal=username=x-access-token \
  --from-file=password="$gitops_credentials_dir/token" \
  --dry-run=client -o yaml | \
  $KUBECTL label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | \
  $KUBECTL apply -f -

rm -rf -- "$gitops_credentials_dir"
trap - EXIT
%{ else }
GIT_TERMINAL_PROMPT=0 git clone -- "$GITOPS_REPO_URL" /opt/gitops-escapa
%{ endif }

%{ if bootstrap_gitops }
# Ativa a sincronização de infraestrutura e aplicações somente quando solicitado.
$KUBECTL apply -f /opt/gitops-escapa/bootstrap/infrastructure-root.yaml
$KUBECTL apply -f /opt/gitops-escapa/bootstrap/apps-root.yaml
%{ endif }
%{ endif }

echo "bootstrap concluido em $(date)" > /var/log/bootstrap-done.log
