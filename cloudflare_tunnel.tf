# Segredo usado no registro do túnel. O conector usa o tunnel_token retornado
# pelo provider; as regras de ingress são gerenciadas remotamente pela Cloudflare.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "escapa" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-k3s"
  secret     = random_id.tunnel_secret.b64_std
  config_src = "cloudflare"
}

# Ingress remotamente gerenciado: o cloudflared no cluster só precisa se autenticar
# e conectar -- as regras de roteamento (hostname -> serviço interno) vivem na Cloudflare,
# consultadas automaticamente pelo conector.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "escapa" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.escapa.id

  config {
    ingress_rule {
      hostname = "${var.frontend_subdomain}.${var.root_domain}"
      service  = "http://escapa-frontend.escapa-prod.svc.cluster.local:80"
    }

    ingress_rule {
      hostname = "${var.backend_subdomain}.${var.root_domain}"
      service  = "http://escapa-backend.escapa-prod.svc.cluster.local:8080"
    }

    # Regra "catch-all" obrigatória - qualquer hostname não mapeado acima cai aqui
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Registros DNS proxied apontando pro túnel -- é isso que substitui o Elastic IP
# como forma de as pessoas chegarem na aplicação.
resource "cloudflare_record" "frontend" {
  zone_id = var.cloudflare_zone_id
  name    = var.frontend_subdomain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.escapa.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "backend" {
  zone_id = var.cloudflare_zone_id
  name    = var.backend_subdomain
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.escapa.id}.cfargotunnel.com"
  proxied = true
}
