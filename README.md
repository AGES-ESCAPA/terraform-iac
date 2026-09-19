# terraform-aws-k3s

Provisiona **1 instância EC2 rodando k3s single-node** na AWS, já com o k3s e o ArgoCD instalados
no primeiro boot. É a camada de infraestrutura *abaixo* do repositório `gitops-escapa` — o Terraform
cria a VM e a rede; a partir do momento em que o k3s está de pé, quem manda é o ArgoCD lendo o repo GitOps.

## O que é criado

- **EC2 sob demanda (On-Demand)** (`t4g.medium` por padrão, 2 vCPU/4 GiB, Ubuntu 22.04 ARM64) em **us-east-2 (Ohio)**,
  com disco `gp3` de 60GB — SO + containers + PVCs
  (via `local-path-provisioner`, que já vem no k3s).
- **Elastic IP** — IP público fixo, sobrevive a stop/start da instância.
- **Security Group**:
  - `22` (SSH) e `6443` (API do k3s) liberados **só** para o seu `admin_cidr`.
  - Sem entrada pública em `80`/`443`: a aplicação é exposta pelo Cloudflare Tunnel.
- **Key pair** — a partir da SUA chave pública (você fornece; a privada nunca passa pelo Terraform).
- Usa a **VPC/subnet default** da conta — sem custo de NAT Gateway, simples o suficiente para 1 node.

## Como usar

No Arch Linux, instale as ferramentas pelos repositórios oficiais:

```bash
sudo pacman -S --needed aws-cli-v2 terraform
aws --version
terraform version
```

Autentique com o acesso ao console recebido da AGES (AWS CLI >= 2.32.0):

```bash
aws login --profile escapa --region us-east-2
aws configure set credential_process 'aws configure export-credentials --profile escapa --format process' --profile escapa-terraform
aws configure set region us-east-2 --profile escapa-terraform
export AWS_PROFILE=escapa-terraform
aws sts get-caller-identity
```

O login abre o navegador e usa a sessão do console para obter credenciais temporárias.
O perfil `escapa-terraform` permite que o provider AWS use essa sessão via `credential_process`.
Quando a sessão expirar, repita `aws login --profile escapa --region us-east-2`.
Não coloque credenciais AWS nos arquivos do Terraform.

```bash
cp -n terraform.tfvars.example terraform.tfvars
chmod 600 terraform.tfvars
# edite terraform.tfvars: chave SSH, admin_cidr, GitOps, GHCR e Cloudflare

terraform init
terraform validate
terraform plan    # confira o que vai ser criado antes de aplicar
terraform apply
```

### Repositório GitOps privado

Use a URL HTTPS sem credenciais em `gitops_repo_url` e preencha `gitops_token` no
`terraform.tfvars` local. Para `AGES-ESCAPA/gitos-escapa`, a URL é
`https://github.com/AGES-ESCAPA/gitos-escapa.git`. O token precisa ter acesso ao repositório
e permissão `Contents: Read`. Se o mesmo token for usado pelo CI para atualizar os
manifestos, use `Contents: Read and write` e cadastre-o também como secret no GitHub Actions.
O Terraform não configura esse secret do CI.

No primeiro boot, o script fornece o token ao Git via `GIT_ASKPASS`, mantém a URL do
remote sem credenciais e cria o Secret `gitops-repository` no namespace `argocd`.
Os Applications raiz só são aplicados se `bootstrap_gitops = true`.
O diretório temporário com a credencial é removido
ao terminar ou em caso de erro. Com token vazio, o clone é anônimo, para repositórios públicos.

O bootstrap não usa `set -x`, para evitar registrar credenciais nos logs. Ainda assim,
**`sensitive` não criptografa o segredo**: o token integra o `user_data` enviado à EC2,
pode estar presente no state/plan e fica no Secret do Kubernetes. Base64 apenas permite
transportar o valor sem alterar caracteres. Restrinja o acesso a esses arquivos e recursos;
o `.gitignore` protege contra inclusão acidental no Git, não contra leitura na AWS.

Trocar o token no `terraform.tfvars` não atualiza um cluster já existente, pois o bootstrap
só executa no primeiro boot. Nesse caso, atualize também a credencial do repositório no ArgoCD
e o secret do CI. O `github_pat` é usado separadamente para imagens privadas do GHCR e requer
um token **classic** com `read:packages`; o token fine-grained do GitOps não atende ao GHCR.

### Compatibilidade com a conta e com ARM64

- O guia da AGES exige `us-east-2` e ainda lista apenas famílias T2/T3 até `medium`.
  O padrão `t4g.medium` segue a especificação mais recente do projeto; confirme que a
  política da conta também permite esse tipo antes de provisionar.
- A AMI é selecionada pela arquitetura retornada pela AWS para `instance_type`:
  `arm64` para T4g e `amd64` para instâncias x86. A consulta exige
  `ec2:DescribeInstanceTypes`, além das permissões de provisionamento.
- As imagens de frontend/backend e dos componentes GitOps precisam oferecer `linux/arm64`.
  Um build Docker realizado apenas em uma máquina x86 não garante essa compatibilidade.
- Os 4 GiB são compartilhados por SO, k3s, ArgoCD e aplicações. Revise requests/limits
  e a necessidade de subir toda a stack de observabilidade antes de aplicar o GitOps completo.

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

Por padrão, `bootstrap_gitops = false`: o primeiro boot instala k3s e ArgoCD, prepara
os secrets e clona o repositório informado, mas não aplica os Applications raiz.
Isso permite validar o cluster antes de publicar as imagens da aplicação ou instalar
a stack GitOps de infraestrutura (observabilidade, Vault, MinIO e cloudflared).
Os recursos Cloudflare declarados no Terraform continuam sendo criados; o conector
cloudflared só será instalado quando a sincronização GitOps for ativada.

Para um primeiro boot com sincronização automática, preencha `gitops_repo_url` e use
`bootstrap_gitops = true`. Se o node já existe, ative o GitOps manualmente quando os
manifestos estiverem prontos; mudar a variável depois não reexecuta o bootstrap:

```bash
export KUBECONFIG=./kubeconfig-escapa.yaml
kubectl apply -f /caminho/para/gitops-escapa/bootstrap/infrastructure-root.yaml
kubectl apply -f /caminho/para/gitops-escapa/bootstrap/apps-root.yaml
```

## Correção do Cloudflare Tunnel em um cluster existente

O túnel usa `config_src = "cloudflare"`: o Terraform gerencia as rotas e o Deployment
GitOps usa `TUNNEL_TOKEN` vindo da chave `token` do Secret `cloudflared-credentials`.
O `credentials.json` da implementação anterior não é usado pelo novo Deployment.
O bootstrap atualizado prepara esse Secret para novas instâncias; em uma EC2 já criada,
a atualização é manual. Não reaplique o bootstrap inteiro.

No provider Cloudflare 4.52.9, mudar `config_src` exige substituir o túnel. Confira o plano:
o ID pode mudar e os CNAMEs precisam acompanhar. Para esta correção excepcional, use
um plano restrito à configuração do túnel e aos dois registros DNS, sem atualizar a EC2:

```bash
terraform plan -out=.terraform/cloudflare-tunnel.tfplan \
  -target=cloudflare_zero_trust_tunnel_cloudflared_config.escapa \
  -target=cloudflare_record.frontend \
  -target=cloudflare_record.backend
```

O túnel e seu segredo entram no plano por dependência. Revise as substituições antes
de aplicar o plano salvo. O arquivo contém dados sensíveis e fica dentro de `.terraform/`,
que já é ignorado pelo Git. `-target` é usado aqui para recuperação pontual, não como rotina.

Depois de revisar e aplicar esse plano, transfira o token diretamente ao cluster, no computador local:

```bash
terraform apply .terraform/cloudflare-tunnel.tfplan
bash scripts/update-cloudflared-secret.sh ubuntu@SEU_IP ~/.ssh/escapa_aws
```

O script requer Terraform, Python 3 e SSH localmente, além do namespace `cloudflared`
já criado pelo bootstrap. Ele não imprime o token e mantém o conteúdo fora do Git.
Não execute `terraform output -raw cloudflare_tunnel_token` isoladamente para compartilhar a saída.

Publique os manifests corrigidos do repositório GitOps antes de sincronizar a Application
`cloudflared`. Ela está temporariamente em sincronização manual. Valide no node:

```bash
sudo k3s kubectl -n cloudflared rollout status deployment/cloudflared --timeout=180s
sudo k3s kubectl -n cloudflared logs deployment/cloudflared --tail=50
```

Se atualizar o Secret com pods já em execução, reinicie o Deployment explicitamente
(`sudo k3s kubectl -n cloudflared rollout restart deployment/cloudflared`), pois a variável
de ambiente só recebe o novo token ao iniciar o container. O túnel conectado não garante
resposta dos hosts `app`/`api` enquanto seus Services e aplicações não existirem.

Depois da recuperação, execute um `terraform plan` completo para revisar diferenças
pendentes. Alterações de `user_data` podem parar/iniciar a EC2 e não reexecutam o bootstrap;
não aplique esse plano completo sem avaliar esses efeitos.

## Limitações conhecidas (coerentes com ser 1 node só)

- **user_data só roda no primeiro boot.** Se você mudar o script depois, precisa recriar a instância
  (`terraform apply -replace=aws_instance.k3s_node`) ou rodar o comando manualmente via SSH —
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
