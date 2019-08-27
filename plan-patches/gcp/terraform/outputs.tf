output "k8s_service_token" {
  value = "${data.kubernetes_secret.k8s_service_token.data.token}"
}

output "k8s_host_url" {
  value = "https://${google_container_cluster.gke-cluster.endpoint}"
}

output "k8s_service_username" {
  value = "${var.eirini_service_account_name}"
}

output "k8s_ca" {
  value = "${base64decode(google_container_cluster.gke-cluster.master_auth.0.cluster_ca_certificate)}"
}

output "system_domain" {
  value = "${var.system_domain}"
}
