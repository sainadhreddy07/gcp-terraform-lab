resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Custom VPC managed by Terraform"
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  description              = "Subnet for the Terraform lab VM"
}

resource "google_compute_firewall" "allow_ssh_from_iap" {
  name        = "${var.name_prefix}-allow-ssh-iap"
  network     = google_compute_network.vpc.name
  description = "Allow SSH only through Identity-Aware Proxy"

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["${var.name_prefix}-vm"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
