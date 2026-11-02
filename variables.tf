variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
  default     = "project-3c584b29-0ddb-45ce-95d"
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "GCP zone for Compute Engine resources"
  type        = string
  default     = "asia-south1-a"
}

variable "name_prefix" {
  description = "Prefix used for resource names"
  type        = string
  default     = "gcp-lab"
}

variable "subnet_cidr" {
  description = "IPv4 range for the custom subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "machine_type" {
  description = "Compute Engine machine type"
  type        = string
  default     = "e2-micro"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 20
}

variable "data_disk_size_gb" {
  description = "Separate persistent data disk size in GB"
  type        = number
  default     = 10
}

variable "terraform_service_account_email" {
  description = "Service account used by GitHub Actions to run Terraform"
  type        = string
  default     = "github-terraform-deployer@project-3c584b29-0ddb-45ce-95d.iam.gserviceaccount.com"
}
