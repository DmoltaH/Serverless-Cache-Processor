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

## Apply (AWS CloudShell, signed in as owner with MFA)

CloudShell uses the console session's temporary credentials, so the owner never needs access keys.

```bash
# 1. Install Terraform in your CloudShell home (persists between sessions)
mkdir -p ~/bin && export PATH="$HOME/bin:$PATH"
ARCH=$([ "$(uname -m)" = "aarch64" ] && echo arm64 || echo amd64)
TF_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)
curl -fsSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip"
unzip -o /tmp/tf.zip -d ~/bin && terraform -version

# 2. Upload bootstrap.zip (Actions > Upload file), then:
unzip -o bootstrap.zip -d bootstrap && cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # adjust region if needed

# 3. Apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Move this stack's own state into the bucket it just created
terraform output -raw bootstrap_backend_hcl > backend.hcl
mv backend.tf.disabled backend.tf
terraform init -migrate-state -backend-config=backend.hcl

# 5. Values needed on your workstation
terraform output -raw aws_cli_config
terraform output -raw infra_backend_hcl
```

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
