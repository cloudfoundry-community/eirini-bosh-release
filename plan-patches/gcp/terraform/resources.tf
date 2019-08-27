# K8s Cluster {
resource "google_container_cluster" "gke-cluster" {
  name               = "${var.env_id}-cluster"
  zone               = "${var.zone}"
  network            = "${google_compute_network.bbl-network.name}"
  subnetwork         = "${google_compute_subnetwork.bbl-subnet.name}"
  initial_node_count = "${var.gke_cluster_num_nodes}"

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    machine_type = "${var.gke_cluster_node_machine_type}"

    tags = ["${var.env_id}-cluster-nodes"]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  timeouts {
    create = "30m"
    update = "40m"
  }
}
# }

# Firewall rules {
resource "google_compute_firewall" "gke-nodes-to-opi" {
  name    = "${var.env_id}-gke-nodes-to-opi"
  network = "${google_compute_network.bbl-network.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["5000"]
  }

  source_tags = ["${var.env_id}-cluster-nodes"]
  target_tags = ["cf-opi"]
}

resource "google_compute_firewall" "gke-nodes-pods-to-doppler" {
  name    = "${var.env_id}-gke-nodes-pods-to-doppler"
  network = "${google_compute_network.bbl-network.name}"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["8082"]
  }

  source_tags   = ["${var.env_id}-cluster-nodes"]
  source_ranges = ["${google_container_cluster.gke-cluster.cluster_ipv4_cidr}"]
  target_tags   = ["cf-doppler"]
}
# }

# Kubernetes Artifacts {
provider "kubernetes" {
  host = "${google_container_cluster.gke-cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(google_container_cluster.gke-cluster.master_auth.0.cluster_ca_certificate)}"
  token = "${data.google_client_config.current.access_token}"
}

resource "kubernetes_namespace" "system" {
  metadata {
    name = "${var.eirini_system_namespace}"
  }
}

resource "kubernetes_service_account" "eirini-service-account" {
  metadata {
    name = "${var.eirini_service_account_name}"
    namespace = "${var.eirini_system_namespace}"
  }
}

resource "kubernetes_cluster_role_binding" "opi-service-account-cluster-role-binding" {
  metadata {
    name = "${var.eirini_service_account_name}-cluster-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "${var.eirini_service_account_name}"
    namespace = "${var.eirini_system_namespace}"
  }
}

resource "kubernetes_secret" "lb-ca-cert-secret" {
  metadata {
    name = "lb-ca-cert-secret"
  }
  data {
    ca.crt = "${var.ssl_certificate}"
  }
}

resource "kubernetes_daemonset" "lb-ca-cert-secret" {
  metadata {
    name = "add-lb-cert-to-nodes"
  }
  spec {
    selector {
      match_labels = {
        name = "add-lb-cert-to-nodes"
      }
    }
    template{
      metadata {
        labels {
          name = "add-lb-cert-to-nodes"
        }
      }
      spec {
          init_container {
            name = "create-docker-certs-directory-on-node"
            image = "ubuntu:xenial"
            security_context {
              run_as_user = 0
              privileged = true
            }
            volume_mount {
              name = "etcdocker"
              mount_path = "/etc/docker"
            }
            command = ["bash"]
            args = ["-cx", "mkdir -p /etc/docker/certs.d/registry.${var.system_domain}"]
          }
          container {
            name = "add-ca-cert-to-nodes-docker-trust"
            image = "ubuntu:xenial"
            security_context {
              run_as_user = 0
              privileged = true
            }
            volume_mount {
              name = "etcdocker"
              mount_path = "/etc/docker"
            }
            volume_mount {
              name = "lb-ca-cert"
              mount_path = "/etc/lb-ca-cert"
            }
            command = ["bash"]
            args = ["-cx", "cp /etc/lb-ca-cert/ca.crt /etc/docker/certs.d/registry.${var.system_domain}/ && sleep infinity"]
          }
          volume {
            name = "etcdocker"
            host_path {
              path = "/etc/docker"
            }
          }
          volume {
            name = "lb-ca-cert"
            secret {
              secret_name = "lb-ca-cert-secret"
            }
          }
        }
      }
    }
}
# }
