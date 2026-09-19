#!/usr/bin/env bash
# Execute localmente, após aplicar o túnel. Nunca habilite set -x neste script.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso: bash scripts/update-cloudflared-secret.sh usuario@host caminho-chave-ssh" >&2
  exit 2
fi

terraform_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# O token passa somente pelo pipe e pela conexão SSH, sem arquivo temporário,
# argumento de processo ou impressão no terminal. Python valida antes de emitir o Secret.
terraform -chdir="$terraform_dir" output -raw cloudflare_tunnel_token |
  python3 -c '
import base64
import json
import sys

token = sys.stdin.read().strip()
if not token:
    sys.exit("Token ausente; aplique primeiro a correção do túnel no Terraform.")
json.dump({
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {"name": "cloudflared-credentials", "namespace": "cloudflared"},
    "type": "Opaque",
    "data": {"token": base64.b64encode(token.encode()).decode()},
}, sys.stdout)
' |
  ssh -i "$2" "$1" 'sudo k3s kubectl apply --server-side -f -'
