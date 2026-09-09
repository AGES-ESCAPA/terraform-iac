# terraform-aws-k3s

Provisiona **1 instância EC2 rodando k3s single-node** na AWS, já com o k3s e o ArgoCD instalados
no primeiro boot. É a camada de infraestrutura *abaixo* do repositório `gitops-escapa` — o Terraform
cria a VM e a rede; a partir do momento em que o k3s está de pé, quem manda é o ArgoCD lendo o repo GitOps.

## O que é criado

- **EC2** (`t3.large` por padrão, Ubuntu 22.04) com disco `gp3` de 60GB — SO + containers + PVCs
  (via `local-path-provisioner`, que já vem no k3s).
- **Elastic IP** — IP público fixo, sobrevive a stop/start da instância.
- **Security Group**:
  - `22` (SSH) e `6443` (API do k3s) liberados **só** para o seu `admin_cidr`.
  - `80`/`443` públicos — é por onde o tráfego da aplicação entra (via Traefik, que já vem embutido no k3s).
- **Key pair** — a partir da SUA chave pública (você fornece; a privada nunca passa pelo Terraform).
- Usa a **VPC/subnet default** da conta — sem custo de NAT Gateway, simples o suficiente para 1 node.

## Como usar

```bash
cp terraform.tfvars.example terraform.tfvars
# edite terraform.tfvars: ssh_public_key, admin_cidr (seu IP: curl ifconfig.me), gitops_repo_url

export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

terraform init
terraform plan    # confira o que vai ser criado antes de aplicar
terraform apply
```

Depois do `apply` (leva ~2-3 min pra AWS subir a VM + mais alguns minutos de cloud-init instalando
k3s/ArgoCD em background):

```bash
# acompanhar o progresso do bootstrap
terraform output -raw bootstrap_log_command | bash

# quando terminar, pegar o kubeconfig local
terraform output -raw fetch_kubeconfig_command

# pegar a senha do ArgoCD (rodar dentro do node via ssh, ou copiar o comando)
ssh ubuntu@$(terraform output -raw public_ip) \
  "sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
```

Se você preencheu `gitops_repo_url`, os dois `Application` raiz (`infrastructure-root` e `apps-root`)
já são aplicados automaticamente — o ArgoCD assume a partir daí. Se deixou em branco, aplique manualmente:

```bash
export KUBECONFIG=./kubeconfig-escapa.yaml
kubectl apply -f /caminho/para/gitops-escapa/bootstrap/infrastructure-root.yaml
kubectl apply -f /caminho/para/gitops-escapa/bootstrap/apps-root.yaml
```

## Limitações conhecidas (coerentes com ser 1 node só)

- **user_data só roda no primeiro boot.** Se você mudar o script depois, precisa recriar a instância
  (`terraform taint aws_instance.k3s_node && terraform apply`) ou rodar o comando manualmente via SSH —
  o Terraform não reaplica user_data em instância já existente.
- **Sem alta disponibilidade.** Se a instância cair, tudo cai junto (é o mesmo tradeoff de rodar
  local-path/Vault standalone que já discutimos — coerente com o cenário de 1 node).
- **State local por padrão.** Para uso em time, descomente o bloco `backend "s3"` em `versions.tf`.

## Próximos passos possíveis

- Trocar a VPC default por uma dedicada (`aws_vpc`), se quiser isolamento de rede.
- Backup do EBS via snapshot agendado (AWS Backup / DLM) — protege contra perda de disco, o que
  local-path sozinho não cobre (ver conversa anterior sobre local-path vs Longhorn).
- Se decidirem crescer para múltiplos nodes no futuro: aí sim migrar para **EKS** (outro módulo) e
  reintroduzir o Longhorn no repo GitOps.
