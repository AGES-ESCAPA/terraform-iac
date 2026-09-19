variable "aws_region" {
  description = "Região AWS onde o node será provisionado"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefixo usado no nome/tags de todos os recursos"
  type        = string
  default     = "escapa"
}

variable "instance_type" {
  description = "Tipo da instância EC2. Padrão: t4g.medium (ARM64, 2 vCPU/4 GiB). Dimensione os workloads do k3s para a memória disponível."
  type        = string
  default     = "t4g.medium"
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
  description = "URL HTTPS do repositório GitOps. Se preenchido, o primeiro boot clona o repositório e configura seu acesso no ArgoCD. Os Applications raiz só são aplicados se bootstrap_gitops for true."
  type        = string
  default     = ""
}

variable "gitops_token" {
  description = "Token do GitHub usado no clone inicial e no ArgoCD para acessar o repositório GitOps por HTTPS. Exige Contents: Read; pode ter Read and write se também for usado pelo CI. Deixe vazio para repositório público."
  type        = string
  sensitive   = true
  default     = ""
}

variable "bootstrap_gitops" {
  description = "Aplica os Applications raiz de infraestrutura e apps no primeiro boot. Mantenha false para preparar k3s/ArgoCD antes de publicar as imagens da aplicação."
  type        = bool
  default     = false
}

# --- GitHub Container Registry (pull das imagens do frontend/backend) ---

variable "github_username" {
  description = "Usuário/organização do GitHub dono das imagens no GHCR"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token classic com escopo read:packages, usado só para o cluster puxar as imagens do GHCR. Tokens fine-grained não suportam GitHub Packages."
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
