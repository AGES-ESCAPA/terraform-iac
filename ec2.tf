# Seleciona uma AMI compatível com a arquitetura do tipo de instância.
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

locals {
  instance_architecture = data.aws_ec2_instance_type.selected.supported_architectures[0]
  ubuntu_architecture = {
    arm64  = "arm64"
    x86_64 = "amd64"
  }[local.instance_architecture]
}

# AMI oficial da Ubuntu (Canonical), sempre a mais recente 22.04 LTS na região
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-${local.ubuntu_architecture}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [local.instance_architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project_name}-admin-key"
  public_key = var.ssh_public_key
}

# Instância sob demanda (On-Demand).
resource "aws_instance" "k3s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.k3s_node.id]
  key_name               = aws_key_pair.admin.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    bootstrap_gitops          = var.bootstrap_gitops
    gitops_repo_url           = var.gitops_repo_url
    gitops_repo_url_b64       = base64encode(var.gitops_repo_url)
    gitops_token_b64          = base64encode(var.gitops_token)
    github_username           = var.github_username
    github_pat                = var.github_pat
    cf_tunnel_credentials_b64 = base64encode(local.cloudflare_local_credentials)
    cf_tunnel_id              = cloudflare_zero_trust_tunnel_cloudflared.ingress.id
  })

  # O user_data só executa no primeiro boot. Alterá-lo depois não reaplica o
  # bootstrap; a atualização do cluster existente precisa ser feita explicitamente.
  #
  # A AMI vem de "most_recent" e o user_data muda com o template: sem ignorar os
  # dois, um apply recriaria a VM e apagaria os volumes local-path (banco, Vault,
  # Garage). Para trocar de AMI de propósito, use -replace=aws_instance.k3s_node.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  tags = {
    Name    = "${var.project_name}-k3s-node"
    Project = var.project_name
  }
}

resource "aws_eip" "k3s_node" {
  instance = aws_instance.k3s_node.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-k3s-node-eip"
    Project = var.project_name
  }
}
