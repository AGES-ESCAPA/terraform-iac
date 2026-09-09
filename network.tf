# Usa a VPC e subnet default da conta/região -- suficiente para um único node.
# Se depois vocês quiserem uma VPC dedicada (isolamento de rede, múltiplos ambientes),
# esse é o arquivo a substituir por aws_vpc/aws_subnet próprios.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pega a primeira subnet default disponível na região
data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}
