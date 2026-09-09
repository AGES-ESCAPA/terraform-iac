resource "aws_security_group" "k3s_node" {
  name        = "${var.project_name}-k3s-node"
  description = "SG do node k3s single-node - so SSH/API do admin, sem porta publica (app exposta via Cloudflare Tunnel)"
  vpc_id      = data.aws_vpc.default.id

  # SSH - só do seu IP
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # API do k3s/kubectl - só do seu IP (não deve ser publica)
  ingress {
    description = "Kubernetes API (k3s)"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Nao ha regra de ingress para 80/443: o cloudflared dentro do cluster abre uma
  # conexao de SAIDA para a Cloudflare (outbound), entao nenhuma porta publica
  # precisa ficar aberta na AWS para o trafego da aplicacao chegar.

  egress {
    description = "Todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-k3s-node"
    Project = var.project_name
  }
}
