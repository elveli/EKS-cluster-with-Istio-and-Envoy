# One-time bootstrap so GitHub Actions can run `terraform plan` against this
# AWS account without long-lived secrets. Apply this yourself with your own
# AWS credentials (e.g. `terraform apply -target=aws_iam_role.github_actions_plan \
# -target=aws_iam_role_policy_attachment.github_actions_plan_readonly`), then set
# the `github_actions_role_arn` output as the repository variable AWS_ROLE_ARN
# (Settings -> Secrets and variables -> Actions -> Variables) so the CI
# workflow can assume it via OIDC.

# The GitHub Actions OIDC provider is a per-AWS-account resource (one per
# URL), not per-repo -- if any other project in this account has already
# set up GitHub Actions OIDC, a provider for this URL already exists.
# Reference it instead of trying to create a duplicate.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions_plan" {
  name = "${var.cluster_name}-github-actions-plan"

  # Scoped to "push to main" only, matching the CI job's trigger -- plan
  # creds are never handed to workflows triggered by (potentially forked) PRs.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Read-only is sufficient for `terraform plan` (no mutating calls). Broader
# than a hand-scoped policy, but avoids CI plan failures from missing
# Describe/List permissions across VPC/EKS/IAM/Autoscaling APIs.
resource "aws_iam_role_policy_attachment" "github_actions_plan_readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
