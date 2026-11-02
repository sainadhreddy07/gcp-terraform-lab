output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "vpc_name" {
  description = "Created VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Created subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "vm_name" {
  description = "Compute Engine VM name"
  value       = google_compute_instance.vm.name
}

output "vm_zone" {
  description = "Compute Engine VM zone"
  value       = google_compute_instance.vm.zone
}

output "vm_internal_ip" {
  description = "VM internal IP address"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "vm_external_ip" {
  description = "Ephemeral external IPv4 address"
  value       = try(google_compute_instance.vm.network_interface[0].access_config[0].nat_ip, null)
}

output "data_disk_name" {
  description = "Attached persistent data disk"
  value       = google_compute_disk.data.name
}

output "ssh_command" {
  description = "Command to connect through IAP"
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
}
