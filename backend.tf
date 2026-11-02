terraform {
  backend "gcs" {
    bucket = "gcp-tfstate-620317254226"
    prefix = "gcp-terraform-lab/state"
  }
}
