# Kubernetes Artifacts {
data "google_client_config" "current" {}

data "kubernetes_secret" "k8s_service_token" {
  metadata {
    name = "${kubernetes_service_account.eirini-service-account.default_secret_name}"
    namespace = "${var.eirini_system_namespace}"
  }
}
# }
