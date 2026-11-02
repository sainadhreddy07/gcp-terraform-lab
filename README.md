# GCP Terraform Lab

Provision a small Google Cloud environment with Terraform and deploy it through GitHub Actions using **Workload Identity Federation (OIDC)**. No long-lived service-account JSON key is stored in GitHub.

## Project configuration

| Setting | Value |
|---|---|
| GCP project name | `gcp-terraform-lab` |
| GCP project ID | `project-3c584b29-0ddb-45ce-95d` |
| GCP project number | `620317254226` |
| Region | `asia-south1` (Mumbai) |
| Zone | `asia-south1-a` |
| Terraform state bucket | `gcp-tfstate-620317254226` |
| GitHub repository | `sainadhreddy07/gcp-terraform-lab` (ID `1442968302`) |

**Before starting:** confirm billing is linked to the project. Compute Engine, persistent disks, and external IPv4 usage may incur charges. The `e2-micro` in Mumbai is not assumed to qualify for the GCP free tier.

## Architecture provisioned

- Custom VPC with automatic subnet creation disabled
- Regional subnet (`10.20.1.0/24`) with Private Google Access
- Firewall rule allowing SSH only from IAP's TCP forwarding range (`35.235.240.0/20`)
- Debian 12 Compute Engine VM (`e2-micro` default)
- Balanced persistent boot disk (20 GB default)
- Separate balanced persistent data disk (10 GB default)
- Dedicated VM runtime service account with no project roles granted by this lab
- Ephemeral external IPv4 address for outbound internet access; inbound SSH is restricted by firewall to IAP

## Repository layout

```text
.
├── .github/workflows/deployment.yml
├── bootstrap/setup-gcp.ps1
├── backend.tf
├── compute.tf
├── network.tf
├── outputs.tf
├── provider.tf
├── terraform.tfvars.example
├── variables.tf
└── versions.tf
```

## 0. Put these files into your GitHub repository

The repository is currently empty. Download and extract the ZIP package, then copy the **contents** of its `gcp-terraform-lab` folder into your local clone of the GitHub repository. From the cloned repository directory:

```powershell
git status
git add .
git commit -m "Add GCP Terraform infrastructure and GitHub Actions"
git push origin main
```

Confirm that `.github/workflows/deployment.yml` appears in GitHub before continuing.

## 1. Prerequisites

Install Google Cloud CLI (`gcloud`), Terraform CLI, and Git. Then open PowerShell:

```powershell
gcloud auth login
gcloud config set project project-3c584b29-0ddb-45ce-95d
gcloud billing projects describe project-3c584b29-0ddb-45ce-95d
```

The billing status must show `billingEnabled: true`. If billing is not enabled, link a billing account in Google Cloud Console before proceeding. The Google identity running bootstrap must be allowed to enable APIs, create storage buckets and service accounts, create Workload Identity resources, and grant IAM roles. Project Owner can perform these bootstrap tasks.

## 2. Bootstrap GCP (one time)

From the repository root, run:

```powershell
.ootstrap\setup-gcp.ps1
```

The bootstrap script:

1. Checks billing status.
2. Enables Compute Engine, IAM, IAM Credentials, STS, Cloud Resource Manager, Service Usage, Cloud Storage, and IAP APIs.
3. Creates a GCS state bucket with uniform bucket-level access, public access prevention, and object versioning.
4. Creates a dedicated GitHub Actions Terraform service account.
5. Grants that account the permissions needed for this learning lab.
6. Creates a Workload Identity Pool and OIDC provider restricted to the immutable GitHub repository ID `1442968302` and the `main` branch.
7. Allows only that repository identity to impersonate the Terraform service account.

The bootstrap grants project-level `roles/compute.admin` and `roles/iam.serviceAccountAdmin` to keep the lab straightforward. These are broad permissions for a learning project; do not copy this role design unchanged into production. Prefer custom roles and narrower resource-level grants for production.

**Do not create or download a service-account JSON key.** GitHub authenticates through OIDC federation.

### If the state bucket name is already taken

GCS bucket names are globally unique. If bootstrap cannot create `gcp-tfstate-620317254226` because another project owns that name, choose a new globally unique name and change `$StateBucket` in `bootstrap/setup-gcp.ps1` and `bucket` in `backend.tf` to the exact same name. Then rerun bootstrap.

## 3. Local Terraform setup (optional)

The state bucket must exist before Terraform initializes its GCS backend. For local Terraform use Application Default Credentials:

```powershell
gcloud auth application-default login
gcloud auth application-default set-quota-project project-3c584b29-0ddb-45ce-95d
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

The state is stored in GCS under the prefix `gcp-terraform-lab/state`. The GCS backend supports state locking; object versioning is enabled for recovery. Your local Google identity must have access to this bucket and permission to read/plan the resources.

After `terraform init`, run `terraform providers lock -platform=windows_386 -platform=windows_amd64 -platform=linux_amd64`, then commit `.terraform.lock.hcl`. Your earlier Terraform build reported `windows_386`; the Google provider publishes a Windows 386 binary, but use the Windows AMD64 Terraform build when possible. The lock command includes both Windows architectures and the Linux AMD64 runner. Do not commit `.terraform/`, state files, plan files, or local `terraform.tfvars`:

```powershell
git add .terraform.lock.hcl
git commit -m "Lock Google Terraform provider dependencies"
git push origin main
```

## 4. GitHub Actions deployment

Workflow: `.github/workflows/deployment.yml`

1. Open the repository on GitHub.
2. Select **Actions** → **GCP Terraform Deployment**.
3. Select **Run workflow**.
4. First run with `apply_changes = false`. This authenticates, initializes, validates, and plans without provisioning the VM.
5. Inspect the plan in the run logs. Run again with `apply_changes = true` only when you are ready to deploy.

The `apply_changes = true` run creates a fresh plan and then applies it automatically in that same run; it does not pause for a second approval after showing the plan. Review the preceding plan and only trigger apply when you intend to provision the current configuration. The workflow serializes runs to avoid concurrent state operations.

WIF configuration in this repository:

- Provider: `projects/620317254226/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
- Service account: `github-terraform-deployer@project-3c584b29-0ddb-45ce-95d.iam.gserviceaccount.com`
- Allowed GitHub repository ID/ref: `1442968302` / `refs/heads/main` (repository: `sainadhreddy07/gcp-terraform-lab`)

No GitHub secret is required for this OIDC setup. Repository and project identifiers are not secrets.

## 5. Verify deployment

After a successful apply:

```powershell
terraform state list
terraform output
```

Expected managed resources include the VPC, subnet, firewall, VM runtime service account, service-account IAM binding, Compute Engine VM, separate data disk, and disk attachment.

Also verify in the Cloud Console:

- VPC network → VPC networks
- VPC network → Firewall
- Compute Engine → VM instances / Disks
- Cloud Storage → Buckets → `gcp-tfstate-620317254226`

## 6. Connect to the VM through IAP

Replace the email below with the Google account you use for `gcloud`:

```powershell
gcloud projects add-iam-policy-binding project-3c584b29-0ddb-45ce-95d --member="user:YOUR_GOOGLE_ACCOUNT_EMAIL" --role="roles/iap.tunnelResourceAccessor"
gcloud projects add-iam-policy-binding project-3c584b29-0ddb-45ce-95d --member="user:YOUR_GOOGLE_ACCOUNT_EMAIL" --role="roles/compute.osAdminLogin"
gcloud iam service-accounts add-iam-policy-binding gcp-lab-runtime@project-3c584b29-0ddb-45ce-95d.iam.gserviceaccount.com --project=project-3c584b29-0ddb-45ce-95d --member="user:YOUR_GOOGLE_ACCOUNT_EMAIL" --role="roles/iam.serviceAccountUser"
```

Connect:

```powershell
gcloud compute ssh gcp-lab-vm --project=project-3c584b29-0ddb-45ce-95d --zone=asia-south1-a --tunnel-through-iap
```

The firewall permits SSH only from IAP's documented TCP forwarding range. Do not open SSH to `0.0.0.0/0`.

### Format and mount the attached data disk (inside the VM)

First inspect the disk; confirm the device path before formatting because formatting destroys existing data:

```bash
ls -l /dev/disk/by-id/google-gcp-lab-data-disk
sudo mkfs.ext4 -F /dev/disk/by-id/google-gcp-lab-data-disk
sudo mkdir -p /mnt/data
sudo mount /dev/disk/by-id/google-gcp-lab-data-disk /mnt/data
sudo blkid /dev/disk/by-id/google-gcp-lab-data-disk
```

Use the UUID returned by `blkid` to add a persistent mount entry to `/etc/fstab` after confirming the mount works.

## 7. Cleanup

When finished, destroy Terraform-managed infrastructure:

```powershell
terraform plan -destroy
terraform destroy
```

The GCS state bucket, Workload Identity Pool/provider, and Terraform deployment service account are bootstrap resources; they are not destroyed by this root Terraform configuration. Keep the state bucket until destroy has completed and you no longer need state history. Remove bootstrap resources separately only if you no longer need the project.

## Cost and safety notes

- VM runtime, balanced persistent disks, and external IPv4 usage can incur charges.
- The Mumbai `e2-micro` machine type is not assumed to be free-tier eligible.
- Review current pricing and billing before applying; destroy lab resources when not in use.
- Never commit Terraform state, plan files, service-account keys, or generated credentials.
- Review every Terraform plan before applying.

## Official references

- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [GitHub Actions authentication to Google Cloud](https://github.com/google-github-actions/auth)
- [Terraform GCS backend](https://developer.hashicorp.com/terraform/language/backend/gcs)
- [Google Terraform provider](https://registry.terraform.io/providers/hashicorp/google/latest)
