# GitHub Actions -> AWS authentication through OpenID Connect (no stored access keys).
#
# This lives in bootstrap because the OIDC provider is account-wide: only one can exist
# per account, so it must not be created per environment.

# GitHub's default OIDC subject for repositories created after July 15, 2026 embeds the
# immutable numeric IDs: repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>
# The values come from terraform.tfvars (generated with `gh api`, see below).
variable "github_owner" {
  type        = string
  description = "GitHub user or organization that owns the repository, exactly as GitHub spells it"
}

variable "github_owner_id" {
  type        = string
  description = "Numeric ID of the owner (gh api repos/OWNER/REPO --jq .owner.id)"
}

variable "github_repo_name" {
  type        = string
  description = "Repository name, exactly as GitHub spells it"
}

variable "github_repo_id" {
  type        = string
  description = "Numeric ID of the repository (gh api repos/OWNER/REPO --jq .id)"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "github-actions-oidc"
  }
}

locals {
  # Start of every subject GitHub issues for this repository.
  repo_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo_name}@${var.github_repo_id}"

  # Which GitHub token "subject" may assume each environment's deploy role.
  # dev: pushes to the develop branch of this repo only.
  # qa and production are added here later (production will require the GitHub
  # environment "production", which is where the manual approval gate lives).
  deploy_roles = {
    dev        = "${local.repo_subject}:ref:refs/heads/develop"
    qa         = "${local.repo_subject}:ref:refs/heads/qa"
    production = "${local.repo_subject}:environment:production"
  }
}

data "aws_iam_policy_document" "github_assume" {
  for_each = local.deploy_roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  for_each = local.deploy_roles

  name                 = "github-actions-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[each.key].json
  max_session_duration = 3600

  tags = {
    Name        = "github-actions-${each.key}"
    Environment = each.key
  }
}

resource "aws_iam_role_policy_attachment" "github_deploy_power_user" {
  for_each = local.deploy_roles

  role       = aws_iam_role.github_deploy[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "github_deploy_iam" {
  for_each = local.deploy_roles

  # PowerUserAccess has no IAM permissions. Terraform has to manage the ECS execution
  # role, so allow IAM actions only on roles named "<env>-*".
  statement {
    sid = "ManageEnvironmentRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.key}-*"]
  }

  # Registering an ECS task definition needs PassRole on its execution role,
  # and only when the role is handed to ECS tasks.
  statement {
    sid       = "PassRolesToEcsTasksOnly"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy_iam" {
  for_each = local.deploy_roles

  name   = "manage-${each.key}-roles"
  role   = aws_iam_role.github_deploy[each.key].id
  policy = data.aws_iam_policy_document.github_deploy_iam[each.key].json
}

output "github_deploy_role_arns" {
  value = { for env, role in aws_iam_role.github_deploy : env => role.arn }
}
