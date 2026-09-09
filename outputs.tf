output "public_ip" {
  description = "IP publico (fixo, via Elastic IP) do node"
  value       = aws_eip.k3s_node.public_ip
}

output "ssh_command" {
  description = "Comando para acessar o node via SSH"
  value       = "ssh ubuntu@${aws_eip.k3s_node.public_ip}"
}

output "fetch_kubeconfig_command" {
  description = "Comando para copiar o kubeconfig do node e apontar pro IP publico"
  value       = <<-EOT
    scp ubuntu@${aws_eip.k3s_node.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig-escapa.yaml
    sed -i 's/127.0.0.1/${aws_eip.k3s_node.public_ip}/' ./kubeconfig-escapa.yaml
    export KUBECONFIG=./kubeconfig-escapa.yaml
    kubectl get nodes
  EOT
}

output "argocd_admin_password_command" {
  description = "Comando (rodar DENTRO do node, via ssh) para pegar a senha inicial do ArgoCD"
  value       = "sudo k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}

output "bootstrap_log_command" {
  description = "Comando para acompanhar o progresso do cloud-init (instalacao do k3s/ArgoCD)"
  value       = "ssh ubuntu@${aws_eip.k3s_node.public_ip} 'sudo tail -f /var/log/bootstrap.log'"
}

output "frontend_url" {
  description = "URL publica do frontend (via Cloudflare Tunnel)"
  value       = "https://${var.frontend_subdomain}.${var.root_domain}"
}

output "backend_url" {
  description = "URL publica do backend/API (via Cloudflare Tunnel)"
  value       = "https://${var.backend_subdomain}.${var.root_domain}"
}
