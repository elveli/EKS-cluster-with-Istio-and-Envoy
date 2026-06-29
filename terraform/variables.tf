variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "istio-demo-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API server endpoint. Defaults to open (0.0.0.0/0) for showcase convenience -- restrict this to your own IP/CIDR for anything beyond a throwaway demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "github_org" {
  description = "GitHub org/user that owns this repository (scopes the CI OIDC trust policy in github-oidc.tf)"
  type        = string
  default     = "elveli"
}

variable "github_repo" {
  description = "GitHub repository name (scopes the CI OIDC trust policy in github-oidc.tf)"
  type        = string
  default     = "EKS-cluster-with-Istio-and-Envoy"
}
