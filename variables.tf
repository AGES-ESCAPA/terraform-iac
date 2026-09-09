variable "aws_region" {
  description = "Região AWS onde o node será provisionado"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo usado no nome/tags de todos os recursos"
  type        = string
  default     = "escapa"
}

variable "instance_type" {
  description = "Tipo da instância EC2. t3.large (2 vCPU/8GB) é o mínimo confortável p/ rodar ArgoCD + Prometheus + Loki + Vault + Minio + Postgres + app na mesma VM."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Tamanho do disco raiz (gp3), em GB. Aqui mora tudo: SO, containers e os PVCs via local-path-provisioner."
  type        = number
  default     = 60
}

variable "ssh_public_key" {
  description = "Conteúdo da SUA chave pública SSH (ex: cat ~/.ssh/id_ed25519.pub). Não geramos par de chaves aqui de propósito -- assim a chave privada nunca passa pelo Terraform nem fica no state."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR liberado para SSH (22) e API do k3s (6443). Restrinja ao seu IP: \"SEU.IP.AQUI/32\". Nunca deixe 0.0.0.0/0 aqui."
  type        = string
}

variable "gitops_repo_url" {
  description = "URL git do repositório gitops-escapa (ex: https://github.com/SEU_ORG/gitops-escapa.git). Se preenchido, o bootstrap do ArgoCD (Applications raiz) é aplicado automaticamente no primeiro boot. Deixe vazio para aplicar manualmente depois."
  type        = string
  default     = ""
}

# --- GitHub Container Registry (pull das imagens do frontend/backend) ---

variable "github_username" {
  description = "Usuário/organização do GitHub dono das imagens no GHCR"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token (classic ou fine-grained) com escopo read:packages, usado só para o cluster puxar as imagens do GHCR"
  type        = string
  sensitive   = true
}

# --- Cloudflare Tunnel (exposição da app sem abrir portas na AWS) ---

variable "cloudflare_api_token" {
  description = "API Token da Cloudflare com permissão Account:Cloudflare Tunnel:Edit e Zone:DNS:Edit na zona do domínio"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Account ID da Cloudflare (aparece na barra lateral direita do dashboard)"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID do domínio na Cloudflare (dashboard do domínio > Overview, barra lateral direita)"
  type        = string
}

variable "root_domain" {
  description = "Domínio raiz já configurado na Cloudflare (ex: escapa.com.br)"
  type        = string
}

variable "frontend_subdomain" {
  description = "Subdomínio publico do frontend (ex: app -> app.escapa.com.br)"
  type        = string
  default     = "app"
}

variable "backend_subdomain" {
  description = "Subdomínio publico do backend/API (ex: api -> api.escapa.com.br)"
  type        = string
  default     = "api"
}
