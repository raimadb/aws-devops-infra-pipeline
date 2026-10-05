# aws-devops-infra-pipeline

## Goal
A production-style AWS DevOps project (my own learning/portfolio project).
Terraform-provisioned infrastructure, a FastAPI + PostgreSQL app on ECS Fargate,
GitHub Actions CI/CD across Dev -> QA -> Prod, centralized logging and monitoring,
secret management and backups, all documented well enough to explain end to end.
I want to understand every piece, so explain what you do and why as you go.

## Architecture
- Region: ap-south-1. AWS account is new, so credits are limited. Cost matters.
- Per environment (dev, qa, production), fully separate resources and state:
  - VPC: 2 public + 2 private subnets across 2 AZs, IGW, ONE NAT gateway per env
  - Security groups: ALB <- internet:80, App <- ALB:8000, RDS <- App:5432, chained by SG reference (not CIDR)
  - RDS PostgreSQL: db.t3.micro, single-AZ, private subnets, encrypted, automated backups
  - ALB in public subnets, ECS Fargate service in private subnets (0.25 vCPU / 0.5 GB, 1 task)
  - ECR repo, CloudWatch log groups (7-day retention), 2 dashboards (infra + app)
- Secrets: SSM Parameter Store. Terraform generates the DB password (random_password)
  and stores it as a SecureString at /<env>/db/password. Never hardcode secrets.
- Remote state: S3 bucket my-tf-106834-bucket, lock table my-dynamo-106834-tf-locks,
  one key per env (dev/terraform.tfstate, qa/terraform.tfstate, production/terraform.tfstate).
  terraform/bootstrap uses LOCAL state (gitignored) and was applied once. Do not re-apply it.
- The dynamodb_table deprecation warning (use_lockfile) is known and accepted for now.

## Repo layout
- app/                 FastAPI app (main.py, routers/health.py, routers/items.py), tests/, Dockerfile
- terraform/bootstrap  state bucket + lock table (already applied)
- terraform/modules/   vpc, security-groups, secrets, rds, alb, compute, monitoring
- terraform/environments/{dev,qa,production}  each has main.tf, variables.tf, terraform.tfvars, outputs.tf
- .github/workflows/   ci.yml, cd-dev.yml, cd-qa.yml, cd-production.yml
- docs/                architecture.md, runbook.md

## Terraform conventions
- Run Terraform ONLY from terraform/environments/<env>/ (never from terraform/ or from a module folder).
- Module block names use underscores (module "security_groups"); `source` paths use the real folder names (hyphens).
- Cross-module wiring goes through module outputs (module.vpc.vpc_id), not new tfvars entries.
- Every resource gets tags: Name and Environment = var.environment.
- Make cost-sensitive choices variables (multi_az, backup retention, instance class).
- Always `terraform plan -out=tfplan`, then apply that exact plan file.
- Run `terraform fmt` and `terraform validate` before every commit.

## Git workflow (IMPORTANT)
- Work directly on the `develop` branch. Do NOT create feature branches.
- COMMIT after every completed module or task, with a clear conventional message
  (e.g. "feat: add RDS module and wire into dev environment").
  For Terraform tasks: commit once validate passes and the plan passes the auto-apply
  checks (see Hard rules), then apply. If the apply forces code changes, commit the fix
  as a separate commit.
- Do NOT push. Never run `git push` in any form. I will push myself.
- Never force anything, never amend or rebase published commits, never touch main or qa.
- Before each commit run `git status` and confirm nothing sensitive is staged.
  Never commit: *.tfstate, .terraform/, tfplan, .env, or any secret value.
  DO commit .terraform.lock.hcl.
- At the end of the project I will raise PRs: develop -> qa (QA deploys), then
  qa -> main (Production, behind a GitHub Environment manual-approval gate).

## Hard rules
- AUTO-APPLY (dev environment only): after `plan -out=tfplan`, you may run
  `terraform apply tfplan` WITHOUT asking me, but only if ALL of these are true:
  1. The plan contains only creations ("N to add, 0 to change, 0 to destroy").
  2. The number and types of resources match what the current task is supposed to add
     (e.g. RDS task = 1 aws_db_subnet_group + 1 aws_db_instance, nothing else).
  3. Nothing existing is modified, replaced ("must be replaced", "-/+") or destroyed.
  4. validate and fmt passed, and the change is already committed locally.
  If ANY check fails, STOP, show me the plan and explain what is unexpected. Wait for my OK.
- NEVER run `terraform destroy` without my explicit OK, and never apply to qa or
  production without my explicit OK (production is deployed only through the pipeline
  with the GitHub Environment approval gate).
- After an auto-apply, show a short summary: what was created, the outputs, and any
  cost-creating resources now running.
- If an auto-apply fails midway, STOP. Do not retry blindly or re-run with changes.
  Show me the error and the current state first.
- Never print or log secret values. Never put credentials in code or workflow files.
  CI authenticates to AWS with GitHub OIDC (an assumed role), no static keys.
- Cost (NAT gateway, RDS and ALB are billed hourly) does not block an auto-apply, but
  always list the billed resources now running in your summary. Remind me to
  `terraform destroy` dev resources whenever we stop for the day.
- Confirm `aws sts get-caller-identity` shows user raima-devops before any AWS action.
- After each completed task, update the "Current status" section below.

## Decisions (for the README later)
- ONE NAT gateway per environment, not per AZ: cost vs HA trade-off, documented.
- SSM Parameter Store over Secrets Manager: free, and sufficient for this project.
- Auto-generated DB password (random_password): no human ever sees or types it.
- Separate resources and state per environment; only module code and app source are shared.
- Security groups chained by reference, so tiers can only talk to their neighbours.

## Current status
- DONE and applied in dev: bootstrap, VPC module, security groups, secrets (SSM).
- RDS module written and planned (2 to add), NOT yet applied or committed.
- TODO in order:
  1. Apply RDS, verify, commit
  2. ALB module
  3. ECR + compute module (ECS Fargate)
  4. FastAPI app: /health, Postgres CRUD, pytest unit + integration tests, Dockerfile
  5. ci.yml (pytest, lint, Trivy dependency + image scan)
  6. cd-dev.yml (build, push to ECR, deploy)
  7. monitoring module (log groups + 2 dashboards)
  8. Replicate dev to qa and production environment folders
  9. cd-qa.yml and cd-production.yml (approval gate), Slack failure notifications
  10. README.md, CHALLENGES.md, docs/architecture.md, docs/runbook.md
