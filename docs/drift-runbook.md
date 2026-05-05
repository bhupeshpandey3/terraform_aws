# Drift Runbook

## What is drift?

Drift is when the real AWS state no longer matches what Terraform's state file
expects. It happens after manual changes via the AWS Console, CLI, or SDK.

## How we detect it

The `drift-detection.yml` workflow runs every weekday at 06:00 UTC. It runs
`terraform plan` across all environments and opens a GitHub Issue labelled
`drift:<env>` if any unexpected changes are found.

---

## Recovery playbook

When a drift issue is opened, you have two choices:

### Option A — Revert to Terraform (code wins)

Use this when the manual change was a mistake or hotfix that should be undone.

```bash
./tf.sh web-app prod apply
```

Terraform will revert the resource back to what the code says.

### Option B — Accept the change (AWS wins, update code to match)

Use this when the manual change was intentional and should become permanent.

**Step 1** — Identify what changed from the plan output in the issue.

**Step 2** — Update the Terraform code to reflect the new desired state.
```hcl
# e.g. someone scaled up RDS in prod — update the variable:
# environments/prod.tfvars
db_instance_class = "db.r6g.xlarge"   # was db.r6g.large
```

**Step 3** — Run plan to confirm it shows no changes.
```bash
./tf.sh web-app prod plan
# Should output: No changes. Your infrastructure matches the configuration.
```

**Step 4** — Open a PR with the code change, merge it. Close the drift issue.

---

## Importing resources created manually

If someone created a **net-new** resource manually (e.g. an S3 bucket, security
group) that Terraform doesn't know about, you need to import it into state
before Terraform can manage it.

```bash
# Example: import a manually created S3 bucket
./tf.sh web-app prod import 'module.s3[0].aws_s3_bucket.main' my-manually-created-bucket

# Example: import an RDS instance
./tf.sh web-app prod import 'module.rds[0].aws_db_instance.main' myapp-prod-db
```

Then run plan — it should show zero changes if the code matches reality.

---

## Prevention checklist

| Control | Where | Status |
|---------|-------|--------|
| GitHub Actions is the only identity with write IAM | `scripts/bootstrap.tf` → `human_readonly` role | ✅ |
| Drift detection runs daily | `.github/workflows/drift-detection.yml` | ✅ |
| Terraform state is locked during apply | S3 native locking (`use_lockfile = true`) | ✅ |
| All infra changes require a PR + plan review | `.github/workflows/infra.yml` | ✅ |
| `deletion_protection = true` on prod RDS | `environments/prod.tfvars` | ✅ |
| `enable_deletion_protection` on prod ALB | `main.tf` (auto on prod) | ✅ |
