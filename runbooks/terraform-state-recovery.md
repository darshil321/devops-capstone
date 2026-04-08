# Terraform State Recovery Runbook

## When to Use This

Your Terraform state file is corrupted or lost. Symptoms:

- `terraform plan` shows "Error: unable to decode state"
- `terraform apply` fails with "Error: error reading state"
- State file was accidentally deleted from S3
- State lock is stuck and `terraform force-unlock` doesn't work
- Infrastructure exists in AWS but state claims it doesn't

## Root Causes

| Cause | Symptom | Fix |
|---|---|---|
| Partial write (crash mid-apply) | State file is truncated | Restore from S3 version |
| Manual edits to `.tfstate` | JSON syntax error | Restore from S3 version |
| Accidental deletion | State file gone | Restore from S3 backup |
| Stale lock (crashed apply) | "state is locked" error | Force unlock |
| Terraform version mismatch | State format error | Use same version as `.terraform.lock.hcl` |

## Recovery Steps

### Option 1: Restore from S3 Versioning (Most Common)

S3 versioning was enabled on `devops-capstone-tfstate-890742569958`, so all previous versions of the state file are preserved.

**Step 1: List available versions**

```bash
aws s3api list-object-versions \
  --bucket devops-capstone-tfstate-890742569958 \
  --prefix dev/terraform.tfstate
```

Output shows all versions with timestamps:
```json
{
  "Versions": [
    {
      "Key": "dev/terraform.tfstate",
      "VersionId": "abc123def456...",
      "LastModified": "2026-04-02T10:20:00Z",
      "IsLatest": false
    },
    {
      "Key": "dev/terraform.tfstate",
      "VersionId": "xyz789uvw...",
      "LastModified": "2026-04-02T09:00:00Z",
      "IsLatest": true
    }
  ]
}
```

**Step 2: Identify the good version**

- `IsLatest: true` is the current (broken) version
- Look for the last version before things broke
- Check timestamps to find when it last worked

**Step 3: Download the good version**

```bash
aws s3api get-object \
  --bucket devops-capstone-tfstate-890742569958 \
  --key dev/terraform.tfstate \
  --version-id "xyz789uvw..." \
  /tmp/terraform.tfstate.good

# Verify it's readable
cat /tmp/terraform.tfstate.good | python3 -c "import sys, json; json.load(sys.stdin)" && echo "Valid JSON"
```

**Step 4: Restore it**

```bash
# Back up the current (broken) state locally
aws s3api get-object \
  --bucket devops-capstone-tfstate-890742569958 \
  --key dev/terraform.tfstate \
  /tmp/terraform.tfstate.broken

# Upload the good version back to S3
aws s3api put-object \
  --bucket devops-capstone-tfstate-890742569958 \
  --key dev/terraform.tfstate \
  --body /tmp/terraform.tfstate.good

# Verify
aws s3api get-object \
  --bucket devops-capstone-tfstate-890742569958 \
  --key dev/terraform.tfstate \
  /tmp/check.tfstate && cat /tmp/check.tfstate | python3 -c "import sys, json; json.load(sys.stdin)" && echo "State restored successfully"
```

**Step 5: Verify Terraform can read it**

```bash
cd infra/environments/dev
terraform refresh
```

If successful, Terraform will read the state and show all resources as managed.

---

### Option 2: Force-Unlock Stuck Lock

If `terraform apply` failed mid-way, a lock might be stuck in DynamoDB.

**Step 1: Check if lock exists**

```bash
aws dynamodb scan \
  --table-name devops-capstone-tfstate-lock \
  --region us-east-1
```

Output:
```json
{
  "Items": [
    {
      "LockID": {
        "S": "devops-capstone-tfstate-890742569958/dev/terraform.tfstate"
      },
      "Digest": { "S": "..." },
      "Operation": { "S": "apply" },
      "Who": { "S": "jenkins@ci-server" },
      "Version": { "S": "..." },
      "Created": { "S": "2026-04-02T09:45:00Z" }
    }
  ]
}
```

**Step 2: Check if the process is actually running**

```bash
# Is the Jenkins job still running?
jenkins_url/job/my-job/lastBuild

# Is the Terraform process still running on a dev machine?
ps aux | grep terraform
```

**Only proceed if you're 100% sure the apply is NOT running.**

**Step 3: Force unlock**

```bash
cd infra/environments/dev

# Get the lock ID from the scan output above
terraform force-unlock "devops-capstone-tfstate-890742569958/dev/terraform.tfstate"

# Or if that doesn't work, manually delete from DynamoDB
aws dynamodb delete-item \
  --table-name devops-capstone-tfstate-lock \
  --key '{"LockID": {"S": "devops-capstone-tfstate-890742569958/dev/terraform.tfstate"}}' \
  --region us-east-1
```

**Step 4: Verify lock is gone**

```bash
aws dynamodb scan --table-name devops-capstone-tfstate-lock
# Should return empty Items list
```

---

### Option 3: Re-import Resources (Last Resort)

If state is completely lost but infrastructure still exists in AWS, you can recreate the state by importing resources.

**Only do this if:**
- S3 versioning backup is unavailable
- You can't restore from backup
- But infrastructure exists in AWS

**Step 1: Create skeleton state**

```bash
cd infra/environments/dev

# Create a blank state
rm terraform.tfstate terraform.tfstate.backup .terraform/terraform.tfstate

# Run terraform init to create new (empty) state
terraform init
```

**Step 2: Import existing resources**

```bash
# Find the VPC ID in AWS
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=devops-capstone-vpc"

# Import it
terraform import aws_vpc.main vpc-0c0703653eeac7d91

# Import subnets
terraform import "aws_subnet.public[0]" subnet-0a0af031dabc4cc3f
terraform import "aws_subnet.public[1]" subnet-046e831bfe11ce032
terraform import "aws_subnet.private[0]" subnet-03c3acf872595699d
terraform import "aws_subnet.private[1]" subnet-0400361d1d0325f07

# ... repeat for all resources
```

**Step 3: Verify plan is clean**

```bash
terraform plan
# Should show: No changes. Infrastructure matches configuration.
```

---

## Prevention

### Enable S3 Versioning

Already done:
```bash
aws s3api put-bucket-versioning \
  --bucket devops-capstone-tfstate-890742569958 \
  --versioning-configuration Status=Enabled
```

### Enable State File Encryption

Already done:
```hcl
backend "s3" {
  ...
  encrypt = true  # Server-side encryption at rest
}
```

### Regular State File Backups

Add a scheduled job (Phase 5 Observability):

```bash
# Every day at 2 AM
0 2 * * * \
  aws s3api get-object \
    --bucket devops-capstone-tfstate-890742569958 \
    --key dev/terraform.tfstate \
    s3://devops-capstone-backups/terraform.tfstate-$(date +%Y-%m-%d).backup
```

### Never Use Force Flags

Avoid these unless absolutely necessary:
```bash
terraform apply -auto-approve          # No confirmation prompt
terraform destroy -auto-approve        # Auto-delete all resources
terraform force-unlock                 # Override state lock
```

## Operational Lessons

**Lesson 1: S3 versioning is insurance**
Without it, accidental deletion = permanent loss. With it, any previous version is one command away.

**Lesson 2: State lock prevents corruption**
DynamoDB lock prevents two applies running simultaneously. If lock is stuck, the issue is usually a crashed process, not Terraform itself.

**Lesson 3: Terraform state is not disaster recovery**
State tells you what was created, not how to recreate it. The real disaster recovery is your Terraform code (which should be in git).

**Lesson 4: Import is slow but reliable**
If you have to re-import 50 resources, it's tedious but beats manually recreating. Automate it:

```bash
# Script to import all resources
for vpc_id in $(aws ec2 describe-vpcs --query "Vpcs[?Tags[?Key=='Project' && Value=='devops-capstone']].VpcId" --output text); do
  terraform import aws_vpc.main "$vpc_id"
done
```

## Related Resources

- `docs/terraform/getting-started.md` — state file overview
- `docs/aws/vpc-design.md` — what resources exist
- AWS S3 documentation on object versioning
