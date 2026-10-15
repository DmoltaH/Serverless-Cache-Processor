# bootstrap/ — account baseline

One-time stack applied by the **account owner** that creates everything the
`infra/` stack needs *before* it can run with least privilege.

| Resource | Purpose |
|---|---|
| S3 account-level Public Access Block | No bucket in the account can ever become public. |
| `tfstate-<project>-<account_id>` bucket | Remote Terraform state: versioned, encrypted, TLS-only, native locking (`use_lockfile`). |
| IAM user `terraform-deployer` (`/bootstrap/`) | Programmatic identity. Its **only** permission is `sts:AssumeRole` on the deployer role (inline user policy; IAM groups are denied by the account's AWS-managed SCP). |
| IAM role `<project>-terraform-deployer` | Least-privilege role used by Terraform for `infra/`. Temporary credentials (1 h). |
| 3 managed policies (network / compute / data) | Scoped by name prefix, account, region; explicit denies on bootstrap identities. |
| Permissions boundary `<project>-workload-boundary` | Ceiling for every role `infra/` creates (e.g. Lambda execution role). |
| `AWSServiceRoleForElastiCache` | Service-linked role, so the deployer does not need `iam:CreateServiceLinkedRole`. |

## Why a separate stack

1. **Credentials chicken-and-egg** — creating the deployer identity requires an identity with broader IAM rights (the owner).
2. **No self-escalation** — the deployer must not manage its own permissions; they are owned by this stack and protected by explicit denies on the `/bootstrap/` IAM path.
3. **State backend** — the state bucket must exist before `terraform init` of `infra/`, and must survive `terraform destroy` of `infra/`.

## Apply (workstation, PowerShell, signed in as account owner)

`aws login` gives the owner short-lived credentials through the browser (with MFA),
so the owner never needs long-term access keys.

```powershell
# 1. Owner credentials (temporary), exported for Terraform
aws login --profile owner
aws configure export-credentials --profile owner --format powershell | Invoke-Expression

# 2. First apply with LOCAL state: the bucket does not exist yet,
#    so temporarily move backend.tf out of the way
Rename-Item backend.tf backend.tf.off
Copy-Item terraform.tfvars.example terraform.tfvars   # set the project's region
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Move this stack's own state into the bucket it just created
Rename-Item backend.tf.off backend.tf
terraform init -migrate-state

# 4. Values needed on your workstation
terraform output -raw aws_cli_config

# 5. Drop the owner credentials from this shell
Remove-Item Env:AWS_ACCESS_KEY_ID, Env:AWS_SECRET_ACCESS_KEY, Env:AWS_SESSION_TOKEN, Env:AWS_CREDENTIAL_EXPIRATION -ErrorAction SilentlyContinue
```

`backend.tf` hardcodes the bucket name (it contains the account ID) because backend
blocks cannot use variables. If the stack is deployed to another account, update it there.

## After apply

1. Console → IAM → Users → `terraform-deployer` → *Security credentials* → **Create access key** (use case: CLI).
   The key is created manually on purpose: a secret created by Terraform would be stored in state.
2. On your workstation:
   ```bash
   aws configure --profile deployer-user      # paste the access key, region, json
   ```
   Append the `aws_cli_config` output to `~/.aws/config` (replacing the `[profile deployer-user]` block `aws configure` created).
   `deployer-user` holds the user's key (no permissions); `deployer-role` assumes the role and is the one Terraform uses.
3. Verify you end up in the role, not the user:
   ```bash
   aws sts get-caller-identity --profile deployer-role
   ```
   Expected ARN: `arn:aws:sts::<account>:assumed-role/sre-assessment-terraform-deployer/terraform-sre-assessment`.

## Key rotation / revocation

Delete or deactivate the access key in IAM. Since the user can only assume the role,
this immediately revokes deploy access; in-flight role sessions expire within 1 h.
