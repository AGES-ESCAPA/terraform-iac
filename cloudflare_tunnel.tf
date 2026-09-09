# Segredo do túnel: 32 bytes aleatórios, usados tanto para registrar o túnel na Cloudflare
# quanto para gerar o credentials.json que o cloudflared usa dentro do cluster.
# Como os dois lados usam o MESMO valor gerado aqui, não precisamos chamar a API da Cloudflare
# de novo pra "buscar" um token depois -- o credentials.json é montado localmente.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_tunnel" "escapa" {
  account_id = var.cloudflare_account_id
  name       = "${var.project_name}-k3s"
  secret     = random_id.tunnel_secret.b64_std
}

# Ingress remotamente gerenciado: o cloudflared no cluster só precisa se autenticar
# e conectar -- as regras de roteamento (hostname -> serviço interno) vivem na Cloudflare,
# consultadas automaticamente pelo conector.
resource "cloudflare_tunnel_config" "escapa" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.escapa.id

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
  content = "${cloudflare_tunnel.escapa.id}.cfargotunnel.com"
  proxied = true
}

resource "cloudflare_record" "backend" {
  zone_id = var.cloudflare_zone_id
  name    = var.backend_subdomain
  type    = "CNAME"
  content = "${cloudflare_tunnel.escapa.id}.cfargotunnel.com"
  proxied = true
}
