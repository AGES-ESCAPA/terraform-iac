# Liga e desliga a EC2 em horario fixo (EventBridge Scheduler, fora da VM).
# Com t4g.large (8 GiB) ligada 12h/dia o custo da instancia fica abaixo da
# t4g.medium 24/7. Disco (EBS) e Elastic IP continuam cobrados com a VM parada.
# Autorizado pelo Arquiteto da AGES junto com a troca para t4g.large.

resource "aws_iam_role" "ec2_scheduler" {
  name = "${var.project_name}-ec2-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = {
    Project = var.project_name
  }
}

# Somente start/stop desta instancia.
resource "aws_iam_role_policy" "ec2_scheduler" {
  name = "start-stop-k3s-node"
  role = aws_iam_role.ec2_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:StartInstances", "ec2:StopInstances"]
      Resource = aws_instance.k3s_node.arn
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_scheduler_schedule" "k3s_node_start" {
  name                         = "${var.project_name}-k3s-node-start"
  description                  = "Liga o node k3s"
  schedule_expression          = var.schedule_start_cron
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:startInstances"
    role_arn = aws_iam_role.ec2_scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.k3s_node.id] })
  }
}

resource "aws_scheduler_schedule" "k3s_node_stop" {
  name                         = "${var.project_name}-k3s-node-stop"
  description                  = "Desliga o node k3s"
  schedule_expression          = var.schedule_stop_cron
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ec2:stopInstances"
    role_arn = aws_iam_role.ec2_scheduler.arn
    input    = jsonencode({ InstanceIds = [aws_instance.k3s_node.id] })
  }
}
