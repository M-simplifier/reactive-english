# GCP Deployment

## Target Architecture

- Cloud Run serves the Haskell backend and the built PureScript frontend.
- Artifact Registry stores Docker images.
- Cloud SQL for PostgreSQL stores production learner data.
- Secret Manager stores the libpq `DATABASE_URL` connection string.
- GitHub Actions deploys through Google Workload Identity Federation, not a
  long-lived JSON service account key.
- Local development remains SQLite by default. PostgreSQL support is compiled
  only for production builds via `cabal -fpostgres`.

This follows the current Google guidance that Workload Identity Federation is
preferred over service account keys, and that Cloud Run can connect to Cloud SQL
through the managed Cloud SQL connection socket.

References:

- https://github.com/google-github-actions/auth
- https://github.com/google-github-actions/deploy-cloudrun
- https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
- https://cloud.google.com/sql/docs/postgres/connect-run

## Cost Guardrails

The default Terraform variables are intentionally small:

- Cloud Run `min-instances=0`, `max-instances=2`, `512Mi`, `1 CPU`.
- Cloud SQL `db-f1-micro`, zonal, 10 GB HDD, disk autoresize disabled.
- Automated backups disabled by default for the cheapest learning deployment.
- Artifact Registry is regional and should be kept pruned.

As of the current Google pricing pages, Cloud SQL `db-f1-micro` in `us-central1`
is listed at `$0.0105/hour`, so the instance itself is roughly `$7.70/month`
before storage, backup, network, and tax. A realistic idle learning deployment
should usually be around `$10-15/month`; Cloud Run will often stay near the free
tier at low traffic. Verify with the official pricing calculator before leaving
the deployment running.

References:

- https://cloud.google.com/sql/pricing
- https://cloud.google.com/run/pricing
- https://cloud.google.com/artifact-registry/pricing

## One-Time Prerequisites

Install local tools:

```sh
gcloud --version
terraform version
docker --version
```

Create or choose a GCP project with billing enabled, then authenticate locally:

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

The Terraform user needs permission to enable project services, create IAM
service accounts, create Cloud SQL, create Artifact Registry, and create Secret
Manager secrets. If the first `terraform apply` cannot enable APIs, enable the
Service Usage API once from the console or with `gcloud services enable
serviceusage.googleapis.com`.

Create a GitHub repository if one does not already exist, then push the default
branch:

```sh
git init
git add .
git commit -m "Initial Reactive English deployment setup"
git branch -M main
git remote add origin git@github.com:YOUR_OWNER/YOUR_REPO.git
git push -u origin main
```

## Provision GCP

```sh
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
project_id    = "your-gcp-project-id"
region        = "us-central1"
github_owner  = "your-github-user-or-org"
github_repo   = "reactive-english"
github_branch = "main"
```

Then apply:

```sh
terraform init
terraform plan
terraform apply
terraform output github_actions_variables
```

Important: local Terraform state contains the generated Cloud SQL password.
Keep `infra/terraform/terraform.tfstate*` out of Git and treat it as sensitive.

## Configure GitHub Actions Variables

Add the values from `terraform output github_actions_variables` as GitHub
repository variables:

- `ARTIFACT_REPOSITORY`
- `CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT`
- `CLOUD_SQL_INSTANCE_CONNECTION_NAME`
- `DATABASE_URL_SECRET_NAME`
- `GCP_DEPLOYER_SERVICE_ACCOUNT`
- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `SERVICE_NAME`

Also add:

- `GOOGLE_CLIENT_ID`: the Google OAuth web client ID.

After the first Cloud Run deployment prints the service URL, add that production
origin to the same Google OAuth client:

```text
https://YOUR_CLOUD_RUN_HOST
```

## Deploy

Push to `main` or run `Deploy to GCP` manually from the GitHub Actions tab.

The workflow:

1. Authenticates to Google Cloud with OIDC.
2. Builds the Docker image with PostgreSQL support.
3. Pushes the image to Artifact Registry.
4. Deploys Cloud Run with `DATABASE_BACKEND=postgres`.
5. Injects `DATABASE_URL` from Secret Manager.
6. Attaches the Cloud SQL instance to the Cloud Run revision.

## Rollback And Cleanup

Rollback can be done from the Cloud Run revisions screen or with:

```sh
gcloud run services update-traffic reactive-english \
  --region us-central1 \
  --to-revisions REVISION_NAME=100
```

Destroy the learning environment when not needed:

```sh
cd infra/terraform
terraform destroy
```

If `deletion_protection=true`, set it to `false` and apply before destroy.
