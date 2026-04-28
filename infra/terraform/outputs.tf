output "artifact_image_base" {
  description = "Base image path. GitHub Actions appends the commit SHA tag."
  value       = local.image_base
}

output "cloud_sql_instance_connection_name" {
  description = "Cloud SQL connection name for Cloud Run --add-cloudsql-instances."
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloud_run_runtime_service_account" {
  description = "Runtime service account for Cloud Run."
  value       = google_service_account.runtime.email
}

output "database_url_secret_name" {
  description = "Secret Manager secret containing the libpq connection string."
  value       = google_secret_manager_secret.database_url.secret_id
}

output "gcp_deployer_service_account" {
  description = "Service account to impersonate from GitHub Actions."
  value       = google_service_account.deployer.email
}

output "gcp_workload_identity_provider" {
  description = "Workload Identity Provider resource name for google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_actions_variables" {
  description = "Repository variables expected by .github/workflows/deploy-gcp.yml."
  value = {
    ARTIFACT_REPOSITORY                = var.artifact_repository_id
    CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT  = google_service_account.runtime.email
    CLOUD_SQL_INSTANCE_CONNECTION_NAME = google_sql_database_instance.postgres.connection_name
    DATABASE_URL_SECRET_NAME           = google_secret_manager_secret.database_url.secret_id
    GCP_DEPLOYER_SERVICE_ACCOUNT       = google_service_account.deployer.email
    GCP_PROJECT_ID                     = var.project_id
    GCP_REGION                         = var.region
    GCP_WORKLOAD_IDENTITY_PROVIDER     = google_iam_workload_identity_pool_provider.github.name
    SERVICE_NAME                       = var.service_name
  }
}
