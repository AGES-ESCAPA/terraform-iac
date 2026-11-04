# Túnel local: encaminhamento para o Traefik configurado no GitOps.
# As rotas ficam no ConfigMap do cloudflared no repositório GitOps.
resource "random_id" "local_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "ingress" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-ingress"
  secret     = random_id.local_tunnel_secret.b64_std
  config_src = "local"
}

locals {
  cloudflare_local_credentials = jsonencode({
    AccountTag   = var.cloudflare_account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.ingress.id
    TunnelSecret = random_id.local_tunnel_secret.b64_std
  })
}

# O DNS passa a ser administrado pelo painel. Esquecer os registros no state
# preserva os CNAMEs existentes e evita desfazer futuras alterações manuais.
removed {
  from = cloudflare_record.frontend
  lifecycle {
    destroy = false
  }
}

removed {
  from = cloudflare_record.backend
  lifecycle {
    destroy = false
  }
}
