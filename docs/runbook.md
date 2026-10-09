# Runbook

Day-to-day operation of the three environments. Architecture is in [architecture.md](architecture.md), setup from zero is in the [README](../README.md).

Procedures marked **untested** describe the intended method but were not run during this project. Try them in dev before relying on them.

## 0. Quick reference

Replace `<env>` with `dev`, `qa` or `production`, and `<account-id>` with the AWS account ID. Region is `ap-south-1`.

| Thing | Name |
|---|---|
| Git branch and workflow | dev: `develop` and `cd-dev.yml`, qa: `qa` and `cd-qa.yml`, production: `main` and `cd-production.yml` |
| Terraform folder | `terraform/environments/<env>` |
| State key | `<env>/terraform.tfstate` |
| ECS cluster and service | `<env>-cluster`, `<env>-app` |
| Log group | `/ecs/<env>-app` |
| Image repository | `<env>-app` |
| Load balancer and target group | `<env>-alb`, `<env>-app-tg` |
| Database | `<env>-postgres` |
| Secrets | `/<env>/db/username`, `/<env>/db/password` |
| Dashboards | `<env>-infrastructure`, `<env>-application` |
| Access log bucket | `<env>-alb-access-logs-<account-id>` |
| Deploy role | `github-actions-<env>` |

### Before you do anything

```bash
aws sts get-caller-identity            # which AWS identity am I?
gh auth status                         # is the right GitHub account active?
pwd                                    # am I inside terraform/environments/<env>?
```

Terraform commands run **only** from `terraform/environments/<env>`, never from `terraform/` or a module folder.

## 1. Deploy a change

1. Commit to `develop` and push.
   ```bash
   git push origin develop
   gh run watch
   ```
   CI runs, then the dev deployment. Verify dev (section 3).
2. Promote to qa.
   ```bash
   gh pr create --base qa --head develop --title "Promote to qa" --body "Promote verified dev changes"
   gh pr checks            # wait for the pull request checks
   gh pr merge --merge     # the merge triggers cd-qa.yml
   gh run watch
   ```
   Opening the pull request only runs CI. The deployment starts when it is **merged**. If no run shows up, wait a minute and check `gh run list --workflow cd-qa.yml --limit 3`.
3. Verify qa, then promote to production.
   ```bash
   gh pr create --base main --head qa --title "Promote to production" --body "Promote verified qa changes"
   gh pr merge --merge
   ```
4. Approve the production deployment (section 2).

Documentation-only changes (`*.md` and `docs/**`) do not trigger a deployment.

## 2. Approve a production deployment

1. Open the run in the repository's **Actions** tab. The deploy job shows **Waiting**.
2. Check the pull request and CI results.
3. Click **Review deployments**, tick `production`, add a comment and click **Approve and deploy** (or **Reject**, which fails the job and sends the Slack alert).
4. Watch it finish, then verify production (section 3).

Confirm the gate is intact whenever the repository settings change:

```bash
gh api repos/<owner>/<repo>/environments/production --jq '[.protection_rules[].type]'
gh api repos/<owner>/<repo>/environments/production/deployment-branch-policies --jq '[.branch_policies[].name]'
```

You want `required_reviewers` in the first output and `["main"]` in the second.

## 3. Verify an environment

```bash
cd terraform/environments/<env>
terraform init
ALB=$(terraform output -raw alb_dns_name)

curl -s http://$ALB/health                                                        # expect {"status":"ok"}
curl -s -X POST http://$ALB/items -H "Content-Type: application/json" -d '{"title":"check"}'
curl -s http://$ALB/items                                                         # the item is listed
```

Deeper checks:

```bash
# running service and its recent events
aws ecs describe-services --cluster <env>-cluster --services <env>-app --region ap-south-1 \
  --query 'services[0].{running:runningCount,desired:desiredCount,events:events[:3].message}'

# are the load balancer targets healthy?
aws elbv2 describe-target-health --region ap-south-1 \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[].TargetHealth.State'

# database status and settings
aws rds describe-db-instances --db-instance-identifier <env>-postgres --region ap-south-1 \
  --query 'DBInstances[0].{status:DBInstanceStatus,public:PubliclyAccessible,encrypted:StorageEncrypted,backups:BackupRetentionPeriod}'

# application logs
aws logs tail /ecs/<env>-app --since 10m --region ap-south-1

# dashboards
terraform output dashboard_urls
```

A healthy environment shows `running` equal to `desired`, targets `healthy`, database `available`, and `/health` returning ok.

## 4. Check which version is running

```bash
scripts/current-image-tag.sh <env>          # prints the commit hash of the running image
git log --oneline -5
```

## 5. Run Terraform by hand (plan only)

The pipeline owns the image tag, so always pass it, otherwise the plan tries to move the task to `latest`.

```bash
cd terraform/environments/<env>
terraform init
terraform plan -var "image_tag=$(../../../scripts/current-image-tag.sh <env>)"
```

The expected result for an untouched environment is `No changes`. A plan never changes AWS.

## 6. Roll back a bad release

Choose in this order.

**A. Automatic.** If the new task never becomes healthy, the ECS deployment circuit breaker rolls the service back by itself and the pipeline's smoke test fails, which sends the Slack alert. Nothing to do except fix the cause.

**B. Revert through the pipeline (preferred).**
```bash
git revert --no-edit <bad-commit>
git push origin <branch>                   # the branch of that environment
```
The pipeline rebuilds the previous code and redeploys it. For production the revert also needs the approval step.

**C. Emergency, by hand.** Use only when the pipeline itself is unavailable, and write down why.
```bash
aws ecr describe-images --repository-name <env>-app --region ap-south-1 \
  --query 'sort_by(imageDetails,&imagePushedAt)[].imageTags'
cd terraform/environments/<env>
terraform plan  -var image_tag=<previous-tag> -out=tfplan
terraform apply tfplan
```
Then reconcile with git (revert or fix forward) so the repository matches what is deployed.

## 7. Scale or resize

Edit `terraform/environments/<env>/terraform.tfvars` and deploy through the pipeline.

| Change | Variable |
|---|---|
| More tasks | `app_desired_count` |
| Task size | `app_cpu` and `app_memory` (use a valid Fargate pairing) |
| Database size | `db_instance_class` |
| Database availability | `db_multi_az = true` (production-grade, raises cost) |
| Backup retention | `db_backup_retention_period` |

Read the plan before merging. A database change shows as `~` update in place. If it shows `-/+` replace, stop: the pipeline's guard will refuse it and the change needs a manual, planned migration.

## 8. Rebuild an environment from nothing

An environment that has been destroyed is rebuilt by the pipeline alone.

```bash
gh workflow enable cd-<env>.yml            # if you disabled it
git commit --allow-empty -m "chore: rebuild <env>"
git push origin <branch>                   # for production, merge to main and approve instead
gh run watch
```

What happens: the CI gate, then a targeted apply creates the image repository and secrets, the image is built and pushed, then everything else is created. Expect 10 to 20 minutes, most of it the NAT gateway, the load balancer and the database.

Check these limits first:

- The free plan allows only a small number of RDS instances. If another environment is already using them, destroy an idle one first.
- Dashboards beyond three per account are billed.

## 9. Pause or tear down an environment

The cheapest way to pause an environment is to destroy it, because the NAT gateway and load balancer cannot be paused. Order matters.

```bash
# 1. stop the pipeline rebuilding it on the next push
gh workflow disable cd-<env>.yml

# 2. empty the load balancer log bucket (a non-empty bucket cannot be deleted)
aws s3 rm s3://<env>-alb-access-logs-<account-id> --recursive

# 3. preview, then destroy
cd terraform/environments/<env>
terraform init
terraform plan -destroy -var image_tag=latest | tail -3
terraform destroy -var image_tag=latest
```

Do not send traffic to the load balancer between steps 2 and 3, because new requests write new log files. If the destroy stops with `BucketNotEmpty`, empty the bucket again and re-run the destroy.

If the destroy fails reading `/<env>/db/...` parameters that an earlier partial destroy already removed, finish with a targeted destroy of what remains: `terraform destroy -target=<address> -var image_tag=latest`.

Confirm nothing billable is left (every command should print nothing):

```bash
aws ec2 describe-nat-gateways --region ap-south-1 --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName' --output text
aws rds describe-db-instances --region ap-south-1 --query 'DBInstances[].DBInstanceIdentifier' --output text
aws rds describe-db-snapshots --region ap-south-1 --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
aws ec2 describe-addresses --region ap-south-1 --query 'Addresses[].PublicIp' --output text
aws ecs list-clusters --region ap-south-1 --query clusterArns --output text
aws s3 ls | grep alb-access-logs || echo "no log buckets"
```

## 10. Rotate the database password (untested)

The password is a Terraform resource, so rotating means replacing it and restarting the tasks. Try this in dev first.

```bash
cd terraform/environments/dev
terraform plan  -replace=module.secrets.random_password.db_password -var "image_tag=$(../../../scripts/current-image-tag.sh dev)" -out=tfplan
# expect: the generated password and the SSM parameter change, the database password is modified in place
terraform apply tfplan
aws ecs update-service --cluster dev-cluster --service dev-app --force-new-deployment --region ap-south-1
```

The running tasks hold the old password until they restart, which is why the forced deployment follows. Check the plan shows the database as an in-place change, never a replacement.

## 11. Add a new environment (untested)

1. Copy a folder: `cp -r terraform/environments/qa terraform/environments/<new>`, then change the state key in `main.tf` and the values in `terraform.tfvars` (a new address range such as `10.3.`, `environment = "<new>"`).
2. Add the environment to `deploy_roles` in `terraform/bootstrap/github-oidc.tf` with its branch or environment subject, then plan and apply bootstrap by hand.
3. Copy a workflow (`cd-qa.yml`) to `cd-<new>.yml` and replace the environment name, branch and role name. Read the diff.
4. Add the new folder to the validate loop in `ci.yml`.
5. Create the branch, and a GitHub environment with reviewers if it should be gated.
6. Check the account limits for databases first.

## 12. Change Terraform, providers or the base image

- **Terraform code:** run `terraform fmt`, `terraform validate` and a plan from the environment folder before committing. CI repeats `fmt -check` and `validate` for all environments.
- **Provider versions:** `terraform init -upgrade` updates `.terraform.lock.hcl`. Commit the lock file with the change.
- **Third-party actions:** keep them pinned to a full commit SHA. Resolve a new one with `git ls-remote <repo-url> 'refs/tags/<tag>*'`, confirm on GitHub that the commit belongs to that release, then edit the workflow.
- **Dependencies:** change `app/requirements.txt` and rebuild. Pinned versions keep builds repeatable.
- **Scan failures:** a fixable HIGH or CRITICAL finding in Trivy blocks the deploy. Update the package or rebuild the image so the OS packages are patched. Unfixed findings are recorded in the README as known risks.

## 13. Change the foundation (bootstrap)

Bootstrap holds the state bucket, lock table, OIDC provider and deploy roles. It is applied by hand and uses **local state**.

```bash
cd terraform/bootstrap
ls terraform.tfstate                       # must exist, or this machine does not know about the foundation
cp terraform.tfstate* ~/tf-backup/         # back it up first
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

If the state file is lost, Terraform no longer knows about the bucket or the roles. Rebuild it with `terraform import` or migrate it into the bucket in future with `terraform init -migrate-state`.

## 14. If the pipeline is down

1. Check https://www.githubstatus.com and the run logs.
2. A temporary GitHub delay: wait, then `gh run list`. Re-run a failed job with `gh run rerun <run-id> --failed`.
3. If an emergency fix cannot wait, apply by hand with the same guard rails the pipeline uses:
   ```bash
   cd terraform/environments/<env>
   terraform init
   terraform plan -var "image_tag=<tag>" -out=tfplan
   terraform show tfplan | sed 's/\x1b\[[0-9;]*m//g' | grep -E "# module|Plan:"
   terraform apply tfplan
   ```
   Read the plan for any `destroy` or `replace` before applying. Record what you did and reconcile the repository afterwards.

## 15. Troubleshooting

| Symptom | Check | Likely cause and fix |
|---|---|---|
| `503` from the load balancer | `aws ecs describe-services ...` events, target health | No healthy target. The service does not exist yet, or the task keeps failing. Read the logs and the stopped-task reason below |
| Tasks start then stop | `aws ecs list-tasks --cluster <env>-cluster --desired-status STOPPED`, then `aws ecs describe-tasks --cluster <env>-cluster --tasks <arn> --query 'tasks[0].stoppedReason'` | Image cannot be pulled (NAT or ECR), the execution role cannot read the SSM parameters, or the app crashes at start |
| App logs show database connection errors | `aws rds describe-db-instances ...`, security group `<env>-rds-sg` | Database not yet available, or the app group is not allowed on 5432 |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | compare the role's trust policy with the real token claims | Subject mismatch. For this repository the subject includes numeric owner and repository IDs. Or the job is not in the `production` environment |
| `InstanceQuotaExceeded` creating the database | `aws rds describe-db-instances` | Free-plan database limit. Destroy an idle environment, then re-run only the failed job |
| `BucketNotEmpty` during destroy | `aws s3 ls s3://<env>-alb-access-logs-<account-id> --recursive` | Empty the bucket and run the destroy again |
| `Error acquiring the state lock` | who else is running Terraform, `gh run list` | Wait for the other run. Only if you are certain nothing is running: `terraform force-unlock <lock-id>` |
| Manual plan wants to change the task definition | the image tag | Pass `-var "image_tag=$(../../../scripts/current-image-tag.sh <env>)"` |
| Plan wants to delete or replace the database | which attribute changed | Stop. The pipeline guard fails the run on purpose. Plan a manual migration with a snapshot first |
| Deploy workflow did not start after a merge | `gh run list --limit 5`, `git show origin/<branch>:.github/workflows/cd-<env>.yml` | Usually a delay of a minute or more. Confirm the workflow file is on the branch, the workflow is enabled and the commit message has no skip marker |
| Trivy fails the build | the Trivy step log | A fixable HIGH or CRITICAL vulnerability. Update or rebuild |
| Resources look missing in the console | the region selector | Make sure it says Asia Pacific (Mumbai) |
| Terraform says `No changes` right after you edited code | `pwd` | You are in the wrong folder |
| Slack alert did not arrive | the `Notify Slack on failure` job log | The secret `SLACK_WEBHOOK_URL` is missing or the webhook was deleted |

## 16. Cost control

- **Cost of one running environment:** about $0.13 to $0.15 per hour (an approximation: NAT gateway, load balancer, database, one task and public IP addresses). The NAT gateway is the biggest single item.
- **Habit:** destroy an environment as soon as you finish with it. The pipeline rebuilds it.
- **Check spend:** the Billing console shows month-to-date cost and your credit balance. From the terminal (about one cent per request):
  ```bash
  aws ce get-cost-and-usage --region us-east-1 \
    --time-period Start=<yyyy-mm-01>,End=<yyyy-mm-dd> --granularity MONTHLY \
    --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
    --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' --output table
  ```
- **Weekly:** run the "nothing billable is left" commands from section 9 and review the budget alert and any cost anomaly notice.

## 17. First five minutes of an incident

1. Is it up? `curl -s http://$ALB/health` and the target health command.
2. What changed? `gh run list --limit 5` and `git log --oneline -5`.
3. What does the service say? ECS service events and `aws logs tail`.
4. Is the database up? `aws rds describe-db-instances ...`.
5. If the last deploy is the cause, roll back (section 6) before investigating.
6. Note the time, what you saw and what you changed, and write it into the pull request or the issue afterwards.

## 18. Known gotchas

- Terraform runs from the environment folder only.
- The image tag is owned by the pipeline, always pass it on manual runs.
- Opening a pull request does not deploy, merging does.
- An environment referenced by a workflow but not yet created in GitHub is created with **no protection**. Create `production` and its reviewers first.
- NAT gateways and load balancers bill every hour, destroy idle environments.
- Empty the log bucket before destroying.
- The bootstrap state is a local file, keep a backup.
- The load balancer address changes every time an environment is rebuilt.
- `dynamodb_table` shows a deprecation warning. It still works.
