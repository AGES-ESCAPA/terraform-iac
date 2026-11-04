#!/usr/bin/env bash
# Execute localmente, após aplicar o túnel. Nunca habilite set -x neste script.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Uso: bash scripts/update-cloudflared-secret.sh usuario@host caminho-chave-ssh" >&2
  exit 2
fi

terraform_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# As credenciais passam somente pelo pipe e pela conexão SSH, sem arquivo temporário,
# argumento de processo ou impressão no terminal. Python valida antes de emitir o Secret.
terraform -chdir="$terraform_dir" output -raw cloudflare_local_tunnel_credentials |
  python3 -c '
import base64
import json
import sys
import uuid

try:
    credentials = json.load(sys.stdin)
    tunnel_id = str(uuid.UUID(credentials["TunnelID"]))
    if not credentials["AccountTag"] or len(base64.b64decode(credentials["TunnelSecret"], validate=True)) != 32:
        raise ValueError()
except (ValueError, KeyError, TypeError):
    sys.exit("Credenciais locais inválidas ou ausentes; aplique primeiro o novo túnel.")
json.dump({
    "apiVersion": "v1",
    "kind": "Secret",
    "metadata": {"name": "cloudflared-local-credentials", "namespace": "cloudflared"},
    "type": "Opaque",
    "data": {
        "credentials.json": base64.b64encode(json.dumps(credentials).encode()).decode(),
        "tunnel-id": base64.b64encode(tunnel_id.encode()).decode(),
    },
}, sys.stdout)
' |
  ssh -i "$2" "$1" 'sudo k3s kubectl apply --server-side -f -'
