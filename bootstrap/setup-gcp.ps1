$ErrorActionPreference = "Stop"

# One-time bootstrap for this GCP project and GitHub Actions Workload Identity Federation.
# Run from PowerShell after installing Google Cloud CLI and authenticating.

$ProjectId     = "project-3c584b29-0ddb-45ce-95d"
$ProjectNumber = "620317254226"
$Region        = "asia-south1"
$StateBucket   = "gcp-tfstate-620317254226"
$RepositoryId  = "1442968302" # Immutable GitHub repository ID
$Repository    = "sainadhreddy07/gcp-terraform-lab"
$Branch        = "main"
$PoolId        = "github-pool"
$ProviderId    = "github-provider"
$TerraformSa   = "github-terraform-deployer"

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    throw "Google Cloud CLI (gcloud) was not found. Install it before running this script."
}

Write-Host "Checking billing status..." -ForegroundColor Cyan
$BillingEnabled = gcloud billing projects describe $ProjectId --format="value(billingEnabled)"
if ($LASTEXITCODE -ne 0) {
    throw "Could not read billing status. Authenticate and confirm project access."
}
if ($BillingEnabled.Trim().ToLower() -ne "true") {
    throw "Billing is not enabled. Link a billing account in the Cloud Console, then rerun this script."
}

gcloud config set project $ProjectId
if ($LASTEXITCODE -ne 0) { throw "Could not set the active GCP project." }

Write-Host "Enabling APIs..." -ForegroundColor Cyan
gcloud services enable `
    compute.googleapis.com `
    iam.googleapis.com `
    iamcredentials.googleapis.com `
    sts.googleapis.com `
    cloudresourcemanager.googleapis.com `
    serviceusage.googleapis.com `
    storage.googleapis.com `
    iap.googleapis.com `
    --project=$ProjectId
if ($LASTEXITCODE -ne 0) { throw "API enablement failed. Check project permissions and billing." }

Write-Host "Checking Terraform state bucket..." -ForegroundColor Cyan
gcloud storage buckets describe "gs://$StateBucket" --project=$ProjectId 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gcloud storage buckets create "gs://$StateBucket" `
        --project=$ProjectId `
        --location=$Region `
        --uniform-bucket-level-access `
        --public-access-prevention
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create gs://$StateBucket. Bucket names are globally unique; if this name is taken, update StateBucket in this script and bucket in backend.tf to the same new name, then rerun."
    }
}

gcloud storage buckets update "gs://$StateBucket" --versioning
if ($LASTEXITCODE -ne 0) { throw "Could not enable object versioning on the state bucket." }

$TerraformSaEmail = "$TerraformSa@$ProjectId.iam.gserviceaccount.com"
Write-Host "Creating Terraform deployment service account if needed..." -ForegroundColor Cyan
gcloud iam service-accounts describe $TerraformSaEmail --project=$ProjectId 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gcloud iam service-accounts create $TerraformSa `
        --project=$ProjectId `
        --display-name="GitHub Actions Terraform Deployer"
    if ($LASTEXITCODE -ne 0) { throw "Could not create Terraform deployment service account." }
}

# Broad roles are used here to keep the learning lab manageable. Tighten them
# to custom/narrow roles before reusing this pattern in production.
Write-Host "Granting lab deployment permissions..." -ForegroundColor Cyan
gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:$TerraformSaEmail" --role="roles/compute.admin" --quiet
if ($LASTEXITCODE -ne 0) { throw "Could not grant roles/compute.admin." }
gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:$TerraformSaEmail" --role="roles/iam.serviceAccountAdmin" --quiet
if ($LASTEXITCODE -ne 0) { throw "Could not grant roles/iam.serviceAccountAdmin." }
gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:$TerraformSaEmail" --role="roles/serviceusage.serviceUsageConsumer" --quiet
if ($LASTEXITCODE -ne 0) { throw "Could not grant roles/serviceusage.serviceUsageConsumer." }

gcloud storage buckets add-iam-policy-binding "gs://$StateBucket" `
    --member="serviceAccount:$TerraformSaEmail" `
    --role="roles/storage.objectAdmin"
if ($LASTEXITCODE -ne 0) { throw "Could not grant Terraform state bucket access." }

Write-Host "Creating Workload Identity Pool if needed..." -ForegroundColor Cyan
gcloud iam workload-identity-pools describe $PoolId --project=$ProjectId --location=global 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gcloud iam workload-identity-pools create $PoolId `
        --project=$ProjectId `
        --location=global `
        --display-name="GitHub Actions Pool"
    if ($LASTEXITCODE -ne 0) { throw "Could not create Workload Identity Pool." }
}

$AttributeCondition = "assertion.repository_id == '$RepositoryId' && assertion.ref == 'refs/heads/$Branch'"
Write-Host "Creating GitHub OIDC provider if needed..." -ForegroundColor Cyan
gcloud iam workload-identity-pools providers describe $ProviderId `
    --project=$ProjectId `
    --location=global `
    --workload-identity-pool=$PoolId 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    gcloud iam workload-identity-pools providers create-oidc $ProviderId `
        --project=$ProjectId `
        --location=global `
        --workload-identity-pool=$PoolId `
        --display-name="GitHub Actions OIDC Provider" `
        --issuer-uri="https://token.actions.githubusercontent.com" `
        --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref" `
        --attribute-condition=$AttributeCondition
    if ($LASTEXITCODE -ne 0) { throw "Could not create GitHub OIDC provider." }
}

$Principal = "principalSet://iam.googleapis.com/projects/$ProjectNumber/locations/global/workloadIdentityPools/$PoolId/attribute.repository_id/$RepositoryId"
Write-Host "Allowing only the repository to impersonate the Terraform service account..." -ForegroundColor Cyan
gcloud iam service-accounts add-iam-policy-binding $TerraformSaEmail `
    --project=$ProjectId `
    --role="roles/iam.workloadIdentityUser" `
    --member=$Principal
if ($LASTEXITCODE -ne 0) { throw "Could not bind Workload Identity User to the Terraform service account." }

Write-Host "Bootstrap completed." -ForegroundColor Green
Write-Host "Project: $ProjectId"
Write-Host "State bucket: gs://$StateBucket"
Write-Host "Terraform service account: $TerraformSaEmail"
Write-Host "Workload Identity Provider: projects/$ProjectNumber/locations/global/workloadIdentityPools/$PoolId/providers/$ProviderId"
Write-Host "Allowed repository ID/ref: $RepositoryId / refs/heads/$Branch ($Repository)"
Write-Host "Allow up to five minutes for IAM and WIF changes to propagate."
