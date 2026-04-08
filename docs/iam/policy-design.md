# IAM Policy Design Guide

## What It Is

IAM (Identity and Access Management) controls **who** can do **what** on **which resources** in AWS. It's the permission layer for everything — users, services, applications.

## Core Concepts

### Principal
**Who** — the entity requesting access.

| Type | Example | Use Case |
|---|---|---|
| User | `arn:aws:iam::890742569958:user/darshil` | Human logging in to console or CLI |
| Role | `arn:aws:iam::890742569958:role/EC2-S3-Reader` | EC2 instance, Lambda, EKS pod |
| Service | `ec2.amazonaws.com` | AWS service (in trust policies) |
| Account | `arn:aws:iam::123456789012:root` | Another AWS account (cross-account access) |

### Action
**What** — the operation the principal wants to perform.

| Action | What it means |
|---|---|
| `s3:GetObject` | Read an S3 object |
| `s3:PutObject` | Write an S3 object |
| `s3:DeleteObject` | Delete an S3 object |
| `s3:*` | All S3 actions |
| `ec2:DescribeInstances` | List EC2 instances |
| `iam:GetRole` | Read an IAM role |
| `iam:*` | All IAM actions (dangerous) |

### Resource
**Which** — the AWS resource the action applies to.

| Resource | ARN Format | Example |
|---|---|---|
| S3 bucket | `arn:aws:s3:::bucket-name` | `arn:aws:s3:::devops-capstone-tfstate-890742569958` |
| S3 objects | `arn:aws:s3:::bucket-name/*` | `arn:aws:s3:::devops-capstone-tfstate-890742569958/*` |
| EC2 instance | `arn:aws:ec2:region:account:instance/id` | `arn:aws:ec2:us-east-1:890742569958:instance/i-1234567890abcdef0` |
| RDS database | `arn:aws:rds:region:account:db:name` | `arn:aws:rds:us-east-1:890742569958:db:my-database` |
| All resources | `*` | (use sparingly, security risk) |

## Policy Document Structure

```json
{
  "Version": "2012-10-17",  // Always this version
  "Statement": [
    {
      "Effect": "Allow",    // or "Deny"
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```

**Reading this:**
- **Effect: Allow** — explicitly grant these permissions
- **Action:** These two operations (read object, list bucket)
- **Resource:** On these two resources (bucket itself for ListBucket, objects in bucket for GetObject)

## Roles vs Users

### User
- **Credentials:** Long-lived (access key + secret key, or password)
- **Use case:** Humans logging in, CI/CD pipelines with stored credentials
- **Problem:** Credentials are static and if leaked, compromised forever
- **Example:** Your AWS console login

### Role
- **Credentials:** Temporary (expires in 1 hour by default)
- **Use case:** EC2 instances, Lambda, EKS pods, cross-account access
- **Benefit:** Credentials are rotated automatically, much safer
- **Example:** EC2 instance assuming role to read S3

**In production:** Always use roles for services. Only use users for humans and as a fallback for CI/CD (and even then, consider temporary credentials).

## Trust Policy vs Permission Policy

A role has **two** independent policies:

### Trust Policy (AssumeRolePolicyDocument)
**Who is allowed to assume this role?**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"  // EC2 service can assume this role
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

This says: "The EC2 service is allowed to call `sts:AssumeRole` on this role."

When you attach this role to an EC2 instance, the EC2 metadata service automatically assumes it and provides temporary credentials.

### Permission Policy (InlinePolicy or Attachment)
**What can this role do?**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

This says: "Whoever assumes this role can read objects from `my-bucket`."

**Both must be correct:**
- Trust policy: "EC2 can assume this role" ✓
- Permission policy: "This role can read S3" ✓
- Result: EC2 instance can read S3 ✓

If either is missing:
- No trust policy: Role exists but nobody can use it
- No permission policy: Role can be assumed but does nothing

## Inline vs Managed Policies

### Inline Policy
- **Where it lives:** Inside the role (not reusable)
- **Use case:** One-off permissions specific to one role
- **Example:** EC2 instance role that only reads one specific S3 bucket

```hcl
resource "aws_iam_role_policy" "example" {
  name   = "my-policy"
  role   = aws_iam_role.example.id
  policy = jsonencode({...})
}
```

### Managed Policy
- **Where it lives:** Standalone (reusable by multiple roles)
- **Types:** AWS managed (created by AWS) or customer managed (you create)
- **Use case:** Common permissions (e.g., "read all S3", "manage databases")
- **Example:** `AmazonEKSWorkerNodePolicy` used by all EKS nodes

```hcl
resource "aws_iam_role_policy_attachment" "example" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
```

**AWS managed policies** are the ones starting with `arn:aws:iam::aws:policy/`. They're maintained by AWS and updated automatically.

## Least Privilege Principle

**Rule:** Grant only the minimum permissions needed.

**Bad:**
```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```
This is equivalent to giving someone the AWS root account. Never do this.

**Better:**
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:DescribeInstances",
    "ec2:DescribeSecurityGroups"
  ],
  "Resource": "*"
}
```
Still broad (describes all EC2 resources), but at least limited to describe operations (no delete, no create).

**Best:**
```json
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/logs/*"
}
```
Specific action (GetObject only), specific resource (one bucket, one prefix). Attacker with this credential can only read log files in `my-bucket/logs/`.

## Common Patterns

### Pattern 1: Service reads one S3 bucket

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::my-bucket",
    "arn:aws:s3:::my-bucket/*"
  ]
}
```

**Why two resources?**
- `arn:aws:s3:::my-bucket` — allows ListBucket (needs bucket ARN)
- `arn:aws:s3:::my-bucket/*` — allows GetObject (needs object ARN)

### Pattern 2: Service writes to one DynamoDB table

```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:PutItem",
    "dynamodb:GetItem",
    "dynamodb:Query"
  ],
  "Resource": "arn:aws:dynamodb:us-east-1:890742569958:table/my-table"
}
```

### Pattern 3: Lambda reads from SNS and writes to SQS

```json
{
  "Effect": "Allow",
  "Action": "sns:Receive",
  "Resource": "arn:aws:sns:us-east-1:890742569958:my-topic"
},
{
  "Effect": "Allow",
  "Action": "sqs:SendMessage",
  "Resource": "arn:aws:sqs:us-east-1:890742569958:my-queue"
}
```

## Debugging Access Denied

```
Error: AccessDenied - User: arn:aws:iam::890742569958:user/darshil is not authorized 
to perform: s3:GetObject on resource: arn:aws:s3:::my-bucket/file.txt
```

Check in this order:

1. **Does the user/role have a permission policy?**
   ```bash
   aws iam get-user-policy --user-name darshil --policy-name my-policy
   ```

2. **Does the policy allow this action?**
   Look for `"Action": "s3:GetObject"` or `"Action": "s3:*"` in the policy.

3. **Does the policy allow this resource?**
   Look for `"Resource": "arn:aws:s3:::my-bucket/*"` (or `"*"` for all).

4. **Is there an explicit Deny?**
   If any policy has `"Effect": "Deny"` matching this action+resource, access is always denied (Deny wins).

5. **Does the role have the right trust policy?**
   If using a role, verify the principal that's trying to assume it is listed in the trust policy.

## GCP Mapping

| AWS | GCP |
|---|---|
| Principal | Identity (User, Service Account) |
| Action | IAM Permission |
| Resource | Resource (GCP has less fine-grained resource control) |
| Role | Service Account |
| Inline policy | No equivalent (all policies are managed) |
| Managed policy | IAM Role / Custom Role |
| Trust policy | Service Account key |

## Operational Lessons

**Lesson 1: Explicit Deny always wins**
If you grant `s3:*` but somewhere else deny `s3:DeleteObject`, you cannot delete. Deny is absolute.

**Lesson 2: Wildcards are convenient but dangerous**
`s3:*` is tempting but means the credential can do anything with S3 (get, put, delete, modify ACLs, etc.). If leaked, the blast radius is huge.

**Lesson 3: Resource-level permissions matter**
Granting `s3:GetObject` on `arn:aws:s3:::my-bucket/logs/*` is safer than granting it on `*` (all buckets). Limit the blast radius.

**Lesson 4: Use AWS managed policies as a starting point**
AWS managed policies are well-tested and updated. Start with those (e.g., `AmazonEKSWorkerNodePolicy`), then add custom inline policies for specific needs.

## Related Resources

- `docs/aws/vpc-design.md` — networking that IAM controls access to
- `infra/modules/iam/` — the actual Terraform code for these policies
- AWS IAM documentation: https://docs.aws.amazon.com/iam/
