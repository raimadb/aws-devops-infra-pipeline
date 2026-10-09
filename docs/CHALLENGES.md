# Challenges faced and how they were resolved

Everything below happened while building this project. Each entry has what I saw, the real cause, the fix and what I would do differently. The entries are ordered roughly as they occurred.

## Summary

| # | Area | Problem | Resolution |
|---|---|---|---|
| 1 | Setup | Forgot the WSL password, wrong distro name | Reset as root through `wsl -u root` |
| 2 | Git | Push rejected with 403 | Two GitHub accounts in the CLI, switched the active one |
| 3 | Terraform | Copied documentation examples that did not fit | Stripped each example to the minimum, validated after every block |
| 4 | Terraform | `No changes` when changes clearly existed | Ran Terraform from the wrong folder |
| 5 | Terraform | Module name mismatch | Block label and folder name are different things |
| 6 | AWS | Resources missing in the console | Looking at the wrong region |
| 7 | Git | Push rejected as non-fast-forward after squash merges | Cherry-picked onto a fresh branch |
| 8 | Tooling | Long pasted scripts were corrupted | Delivered as files instead of pasting |
| 9 | CI | Lint passed locally, failed in CI | Ruff treated first-party imports differently from different folders |
| 10 | CI | Image scan failed on a HIGH vulnerability | OS patching in the Dockerfile |
| 11 | Security | A popular scanning action was compromised | Pinned third-party actions to commit SHAs |
| 12 | CD | OIDC login denied | GitHub changed the token subject format |
| 13 | Security | A webhook URL was exposed | Revoked, recreated, stored through a prompt |
| 14 | CD | A tfvars value fought the pipeline | Tag owned by the pipeline only |
| 15 | CD | A new environment could not deploy | Ordering: image repository before service |
| 16 | GitHub | Required reviewers unavailable | Plan restriction on private repositories |
| 17 | CD | Deploy did not start after a merge | Delayed run, ruled out the usual causes |
| 18 | AWS | Third database blocked | Free-plan instance limit |
| 19 | AWS | Destroy failed twice | Non-empty log bucket, then a data lookup on deleted secrets |
| 20 | Cost | Most of the spend came from one resource | NAT gateway left running for weeks |
| 21 | Security | One HIGH finding that cannot be fixed yet | Accepted and documented |
| 22 | Small | Logs, line endings and file artifacts | Minor fixes |

---

## 1. WSL password and distribution name

**Saw:** `sudo` asked for a password I did not remember. My first reset attempt failed with `WSL_E_DISTRO_NOT_FOUND`.

**Cause:** I used my Linux **username** where WSL expects the **distribution name**.

**Fix:** `wsl -l -v` listed the real distribution name, then `wsl -d <distro> -u root` opened a root shell and `passwd <user>` set a new password. Docker Desktop also needed its WSL integration switched on before `docker` worked inside WSL.

**Lesson:** list before you guess. The names for a user, a distribution and a hostname are different things.

## 2. Push rejected with 403

**Saw:** `Permission to <repo>.git denied to <other-account>`. `gh repo clone` had also failed earlier.

**Cause:** `gh auth status` showed two accounts logged in, and the **active** one was not the repository owner.

**Fix:** `gh auth switch --hostname github.com --user <owner>`.

**Lesson:** when a permission error names an account you did not expect, check which identity the tool is actually using.

## 3. Documentation examples that did not fit

**Saw:** my first Terraform for the state locking table came from a page showing a global (multi-region) table, with streams, a range key and a secondary index. Other copied examples used KMS encryption I did not need, IPv6 routes that referenced resources I never created, and generic names like `example` that no longer existed.

**Cause:** documentation pages show the most feature-complete example, and I pasted whole blocks.

**Fix:** for each example I asked what the minimum set of arguments was for my use case, replaced every `example` reference, and ran `terraform validate` after each block. The state lock table ended up with one key (`LockID`) and on-demand billing.

**Lesson:** read the surrounding text to see which example matches the use case, then delete everything you cannot justify.

## 4. `No changes` when I had made changes

**Saw:** `terraform plan` reported no changes right after I added a whole module.

**Cause:** I ran it from `terraform/`, the parent folder. Terraform only reads the `.tf` files in the folder you run it from.

**Fix:** run Terraform only from `terraform/environments/<env>`. Modules are never run on their own, they are validated through whichever environment calls them.

## 5. Module name versus folder name

**Saw:** `Reference to undeclared module ... Did you mean "security-groups"?`

**Cause:** I named the module block with a hyphen in one file and an underscore in another. The `source` path is a real folder name, but the block label is a free name that must simply be used consistently.

**Fix:** one label everywhere, and `source = "../../modules/security-groups"` unchanged. Terraform's error message named the answer.

## 6. Resources "missing" in the console

**Saw:** the VPC console showed a default VPC and no NAT gateways.

**Cause:** the console was set to `us-east-1`. Everything was in `ap-south-1`. The extra subnets and route table I saw were also AWS defaults: every region has a default VPC with three subnets, and every VPC has an unused main route table.

**Fix:** switch region, and filter by VPC ID or the `Environment` tag.

## 7. Non-fast-forward push after squash merges

**Saw:** `rejected ... non-fast-forward`, and `git log` showed the same change under two commit IDs.

**Cause:** pull requests were squash-merged into `develop`, and my feature branch was later rebuilt on top, which gave one commit a new identity.

**Fix:** I did not force-push. I created a fresh branch from `develop` and `git cherry-pick`ed only the new commit. Afterwards I deleted the merged branches and turned on automatic head-branch deletion. For the rest of the project I worked directly on `develop` and promoted by pull request.

**Lesson:** never reuse a feature branch after a squash merge.

## 8. Long pasted scripts were corrupted

**Saw:** large `cat > file <<'EOF'` blocks arrived with lines missing and fragments of other lines spliced in, and a few such files looked wrong in `cat`.

**Cause:** the terminal mangled long multi-line pastes.

**Fix:** keep pasted blocks short, and ship larger files (workflows, Terraform) as downloadable files that I copied into the repo. Terraform's `validate` and `plan` caught every damaged file before it did harm. Downloaded files also arrived with `*:Zone.Identifier` artifacts from Windows, which I deleted and added to `.gitignore`.

## 9. Lint passed locally, failed in CI

**Saw:** `I001 Import block is un-sorted` on files that passed on my laptop. Separately, rule `B008` flagged `Depends(...)` used as a default value.

**Cause:** I ran `ruff check .` from `app/`, so ruff treated `config.py` and `database.py` as my own modules. CI ran `ruff check app` from the repo root, where they looked like third-party packages and the sort order differed. `B008` is a known false alarm for FastAPI's older style.

**Fix:** a `ruff.toml` inside `app/` with `src = ["."]`, the CI step changed to `cd app && ruff check .`, and the version of ruff pinned. For `B008` I switched to the modern `Annotated[Session, Depends(get_db)]` pattern.

**Lesson:** make CI run the same command from the same folder as I do locally, and pin tool versions.

## 10. Image scan failed on a real vulnerability

**Saw:** Trivy reported `libpcre2-8-0` at `10.46-1~deb13u2` with a HIGH out-of-bounds write, fixed in `deb13u3`. The Python packages were clean.

**Cause:** the `python:3.12-slim` base image was built before Debian published the patch.

**Fix:** `apt-get update && apt-get upgrade -y` in the Dockerfile with the apt cache removed. I proved it with `docker build --pull --no-cache` and `dpkg -l libpcre2-8-0`, which showed `deb13u3`, then the pipeline passed.

**Lesson:** a scanner that blocks on fixable findings does its job when it blocks you.

## 11. A security scanner's own GitHub Action was compromised

**Saw:** while choosing a version for the Trivy action, I found reports that in March 2026 attackers rewrote most of that action's version tags to deliver credential-stealing code. Versions 0.35.0 and later were reported clean.

**Cause:** version tags in GitHub Actions can be moved after the fact, so `@v0.34` is not a fixed target.

**Fix:** third-party actions are pinned to a **full commit SHA**, found with `git ls-remote` and verified on GitHub against the release tag. For the Slack alert I used plain `curl` and `jq` instead of adding another dependency. Only one other third-party action (the official AWS credentials action) is used, also pinned.

## 12. OIDC login denied

**Saw:** `Not authorized to perform sts:AssumeRoleWithWebIdentity`, retried twelve times. Everything before that step was green.

**Cause:** my trust policy matched `repo:<owner>/<repo>:ref:refs/heads/develop`. For repositories created after July 15, 2026, GitHub now puts the **immutable numeric owner and repository IDs** in the token subject, `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...`, which prevents a recycled name from impersonating a pipeline.

**Fix:** I read the IDs with `gh api`, wrote them to `terraform/bootstrap/terraform.tfvars`, and built the subject from them. The plan showed exactly one change, the role's trust condition, and the next run printed `Authenticated as assumedRoleId ...:github-cd-dev-<run-id>`. I had a debug step ready that prints only the token's claims, in case my assumption had been wrong.

**Lesson:** when authentication fails, compare the real claim with the policy instead of loosening the policy.

## 13. A webhook URL was exposed

**Saw:** I pasted a test command containing the full Slack webhook URL, and it appeared in my shell history and in a conversation.

**Cause:** a webhook URL is a credential, since anyone holding it can post to the channel.

**Fix:** deleted the webhook in Slack and created a new one, cleared the shell history (`history -c && history -w`) and confirmed it was gone with `grep`, then stored the new value with `gh secret set SLACK_WEBHOOK_URL`, which prompts without echoing. I also scanned the whole git history for key patterns, webhook URLs and state files before making the repository public. Nothing was found.

## 14. A tfvars value fought the pipeline

**Saw:** a manual `terraform plan` wanted to move the running task back from a commit-hash image to `latest`.

**Cause:** two writers for the same setting. The pipeline passed the commit tag with `-var`, while `terraform.tfvars` still said `image_tag = "latest"`.

**Fix:** removed the value from tfvars so the variable is required, and added `scripts/current-image-tag.sh`, which reads the tag the service is running. After that, `terraform plan -var "image_tag=$(scripts/current-image-tag.sh dev)"` reports `No changes`.

## 15. A new environment could not deploy

**Saw (anticipated, then confirmed):** the ECS service waits for a healthy task and cannot start without an image, but the image repository is created by the same Terraform run.

**Cause:** an ordering dependency that does not exist when you only update an existing environment.

**Fix:** a step before the image build runs `terraform apply -target=module.ecr -target=module.secrets`. On an existing environment it reports no changes. On a new one it creates 5 resources, which is exactly what QA did on its first run, followed by 41 more in the main apply.

## 16. Required reviewers were not available

**Saw:** the plan was a GitHub environment with a required reviewer for production. Documentation said required reviewers are only available for **public** repositories on Free, Pro and Team plans.

**Cause:** the repository was private.

**Fix:** scanned the history for secrets, made the repository public, and turned on approval for outside collaborators' workflow runs. I created the `production` environment **before** the first workflow run that referenced it (a missing environment is created automatically with no protection), and verified it with `gh api` that the rules included `required_reviewers`. My first check showed only a branch policy, which is why I added the reviewer and checked again.

## 17. A deploy did not start after a merge

**Saw:** after merging into `qa`, `gh run watch` found nothing, and only old zero-second failed runs from the empty scaffold files showed on that branch.

**Cause:** not determined. The merged pull request targeted `qa`, the workflow file was on the branch with the right trigger, no skip marker was in the commit message, and all four workflows were active. The run appeared shortly afterwards without my doing anything.

**Fix:** I checked each possible cause in order with read-only commands (`gh pr list`, `git show origin/qa:<file>`, `gh api .../actions/runs?head_sha=...`, `gh workflow list --all`). The likeliest explanation is a delay on GitHub's side.

**Lesson:** ruling causes out systematically is more useful than retrying blindly.

## 18. The third database was blocked

**Saw:** during the first production run: `InstanceQuotaExceeded: You reached the maximum number of instances available with free plan accounts.`

**Cause:** the account was on the AWS free plan, which limits the number of RDS instances. Dev and QA already used both.

**Fix:** destroyed QA, which was already verified and rebuildable by the pipeline, then re-ran **only the failed job**. Terraform's state had recorded the partial apply, so the re-run created just the four missing resources (database, task definition, service, infrastructure dashboard). The run needed the reviewer's approval again, which is expected.

## 19. Destroy failed twice

**Saw:** `BucketNotEmpty` deleting the load balancer's log bucket, and then on a second attempt `couldn't find resource` reading the SSM parameters.

**Cause:** the log bucket held access logs and had no `force_destroy`. The first partial destroy had already deleted the secrets, and the database module still tried to read them while planning.

**Fix:** emptied the bucket with `aws s3 rm --recursive`, then destroyed just the remaining resource with `terraform destroy -target=...`. After that I verified nothing was left (state, buckets, ECR, NAT gateways). The documented teardown order is now: empty the bucket first, then one full destroy. Adding `force_destroy = true` to the log bucket is on the next-steps list.

## 20. Most of the spend came from one resource

**Saw:** the Billing console showed $19.64 for September and $14.90 for October 1 to 8, while the environments were meant to be short-lived.

**Cause:** by my estimate about 90% of it was the dev NAT gateway and its IP address running continuously for around three weeks, because I did not destroy dev between work sessions. The cost chart's largest segment was `EC2 - Other`, which is where NAT gateways are billed.

**Fix:** treat environments as disposable. Everything is code, so an idle environment is destroyed and the pipeline rebuilds it in 10 to 15 minutes. I also found my own early estimate (about $0.11 an hour per environment) was low because it left out the per-address charge for public IPs, and corrected it to about $0.13 to $0.15.

**Lesson:** the biggest cost in a small project is usually a fixed hourly resource nobody remembers to turn off.

## 21. One HIGH finding that cannot be fixed yet

**Saw:** ECR's scan of the production image showed 1 HIGH: a heap overflow in the system `zlib` library (CVE-2026-85091).

**Cause:** the Debian security tracker lists the package as vulnerable with **no fixed version available**. The pipeline's policy (`ignore-unfixed`) blocks fixable HIGH and CRITICAL findings only, so this did not stop the build.

**Fix:** none available, so I recorded it. The flaw needs a program to call `gzprintf` after a stalled non-blocking write, which this application does not do, and the base image is patched on every build, so the fix will arrive with the next build after Debian ships it.

## 22. Small things

- **Plan lines missing from `grep`:** Terraform colors its log, and the escape codes split the words. `sed 's/\x1b\[[0-9;]*m//g'` strips them.
- **503 from the load balancer:** expected before the service exists. It means the load balancer answers, with nothing behind it yet. A timeout would have pointed at a security group or subnet.
- **Branch protection on a solo repo:** GitHub never lets you approve your own pull request, so required approvals were set to 0 for the branch rulesets. Production approval is done through the environment gate instead.
- **tfvars were ignored by git:** my first `.gitignore` excluded `*.tfvars`, which would have hidden the QA and production values the pipeline needs. They hold no secrets, so I removed that rule.
- **`dynamodb_table` is deprecated:** the S3 backend now supports its own lock file (`use_lockfile`). I kept DynamoDB, which still works, and listed the migration as a next step.
- **A failed job that was never "stopped":** the Slack alert job uses `if: failure()`. It waits for the CI and deploy jobs and runs only when one failed, even though the failing job was earlier in the chain.
