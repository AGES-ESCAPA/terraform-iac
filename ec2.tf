# AMI oficial da Ubuntu (Canonical), sempre a mais recente 22.04 LTS na região
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

resource "aws_spot_instance_request" "k3s_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.k3s_node.id]
  key_name               = aws_key_pair.admin.key_name

  # spot persistente: se a AWS reclamar a instância, uma nova é lançada automaticamente
  # (mas o EIP não segue sozinho -- ver aws_eip abaixo -- e dados fora do EBS raiz somem)
  wait_for_fulfillment = true
  spot_type            = "persistent"
  instance_interruption_behavior = "terminate"

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    gitops_repo_url      = var.gitops_repo_url
    github_username      = var.github_username
    github_pat           = var.github_pat
    cf_account_tag       = var.cloudflare_account_id
    cf_tunnel_id         = cloudflare_tunnel.escapa.id
    cf_tunnel_secret_b64 = random_id.tunnel_secret.b64_std
  })

  # troca de user_data força recriação do bootstrap sem recriar a instância toda,
  # mas em EC2 o user_data só roda no PRIMEIRO boot -- mudanças aqui depois do apply
  # inicial não têm efeito automático (documentado no README).

  tags = {
    Name    = "${var.project_name}-k3s-node"
    Project = var.project_name
  }
}

resource "aws_eip" "k3s_node" {
  instance = aws_spot_instance_request.k3s_node.spot_instance_id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-k3s-node-eip"
    Project = var.project_name
  }
}
