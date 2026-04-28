variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Primary GCP region for Cloud Run, Artifact Registry, and Cloud SQL."
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Cloud Run service name and container image name."
  type        = string
  default     = "reactive-english"
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "reactive-english"
}

variable "db_instance_name" {
  description = "Cloud SQL instance name."
  type        = string
  default     = "reactive-english-db"
}

variable "db_name" {
  description = "Application database name."
  type        = string
  default     = "reactive_english"
}

variable "db_user" {
  description = "Application database user."
  type        = string
  default     = "reactive_english"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. db-f1-micro is the lowest-cost learning default."
  type        = string
  default     = "db-f1-micro"
}

variable "db_edition" {
  description = "Cloud SQL edition. ENTERPRISE is required for low-cost shared-core tiers such as db-f1-micro."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.db_edition)
    error_message = "db_edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size in GB."
  type        = number
  default     = 10
}

variable "enable_backups" {
  description = "Enable automated Cloud SQL backups. Costs slightly more storage."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect the Cloud SQL instance from accidental Terraform destroy."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = "GitHub repository owner or organization."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
}

variable "github_branch" {
  description = "Branch allowed to deploy through GitHub OIDC."
  type        = string
  default     = "main"
}
