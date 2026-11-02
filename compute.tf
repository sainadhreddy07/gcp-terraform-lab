data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

resource "google_service_account" "vm_runtime" {
  account_id   = "${var.name_prefix}-runtime"
  display_name = "Runtime service account for the GCP Terraform lab VM"
  description  = "No project roles are granted by this lab"
}

# The Terraform deployment identity may attach this dedicated VM identity.
resource "google_service_account_iam_member" "terraform_can_attach_vm_sa" {
  service_account_id = google_service_account.vm_runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.terraform_service_account_email}"
}

resource "google_compute_disk" "data" {
  name        = "${var.name_prefix}-data-disk"
  zone        = var.zone
  type        = "pd-balanced"
  size        = var.data_disk_size_gb
  description = "Separate persistent data disk managed by Terraform"

  labels = {
    environment = "lab"
    managed_by  = "terraform"
  }
}

resource "google_compute_instance" "vm" {
  name         = "${var.name_prefix}-vm"
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["${var.name_prefix}-vm"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    # Ephemeral external IPv4 allows outbound updates. Firewall rules still
    # restrict inbound SSH to the IAP TCP forwarding range.
    access_config {}
  }

  service_account {
    email  = google_service_account.vm_runtime.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  allow_stopping_for_update = true
  deletion_protection       = false

  depends_on = [
    google_service_account_iam_member.terraform_can_attach_vm_sa
  ]
}

resource "google_compute_attached_disk" "data" {
  disk        = google_compute_disk.data.id
  instance    = google_compute_instance.vm.id
  device_name = "${var.name_prefix}-data-disk"
  mode        = "READ_WRITE"
}
