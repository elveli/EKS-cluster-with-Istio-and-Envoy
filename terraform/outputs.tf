output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions to assume via OIDC for `terraform plan` in CI. Set this as the repository variable AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions_plan.arn
}
