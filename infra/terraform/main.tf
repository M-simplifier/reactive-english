locals {
  deployer_service_account_id = "${var.service_name}-deployer"
  runtime_service_account_id  = "${var.service_name}-runtime"
  database_url_secret_id      = "${var.service_name}-database-url"
  github_repository           = "${var.github_owner}/${var.github_repo}"
  image_base                  = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repository_id}/${var.service_name}"
  required_services = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "sqladmin.googleapis.com"
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Docker images for Reactive English"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "runtime" {
  account_id   = local.runtime_service_account_id
  display_name = "Reactive English Cloud Run runtime"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "deployer" {
  account_id   = local.deployer_service_account_id
  display_name = "Reactive English GitHub Actions deployer"

  depends_on = [google_project_service.required]
}

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "postgres" {
  name                = var.db_instance_name
  database_version    = "POSTGRES_16"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.db_tier
    edition           = var.db_edition
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = false

    backup_configuration {
      enabled = var.enable_backups
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = random_password.db.result
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = local.database_url_secret_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret = google_secret_manager_secret.database_url.id
  secret_data = join(" ", [
    "user=${google_sql_user.app.name}",
    "password=${random_password.db.result}",
    "dbname=${google_sql_database.app.name}",
    "host=/cloudsql/${google_sql_database_instance.postgres.connection_name}"
  ])
}

resource "google_project_iam_member" "runtime_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "runtime_database_url_reader" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "deployer_database_url_reader" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_project_iam_member" "deployer_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_project_iam_member" "deployer_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_artifact_registry_repository_iam_member" "deployer_artifact_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.app.location
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_service_account_iam_member" "deployer_can_use_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.service_name}-github"
  display_name              = "Reactive English GitHub Actions"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${local.github_repository}' && assertion.ref == 'refs/heads/${var.github_branch}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_can_impersonate_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repository}"
}
