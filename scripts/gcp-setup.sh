#!/usr/bin/env bash
# One-time setup of the Google Cloud project the API runs in, for .github/workflows/deploy.yml.
# Run it in Cloud Shell (the >_ button at console.cloud.google.com) as the project's owner, after
# pasting the `database-url` and `supabase-secret-key` secrets into Secret Manager:
#   bash <(curl -fsSL https://raw.githubusercontent.com/tmeng53/wildcard/main/scripts/gcp-setup.sh) PROJECT_ID [REGION]
# REGION is the Cloud Run region nearest the Supabase project (us-east4 for Supabase's us-east-1).
# Running it again is safe: it only adds what is missing.
#
# It makes:
# - `wildcard`, the Artifact Registry repository the server's images go to;
# - `wildcard-api`, the service account Cloud Run runs the server as, which may read the secrets;
# - `github-deploy`, the account the deploy workflow acts as: it may push images, deploy the
#   service, see which secrets exist and read `database-url` to run migrations;
# - a Workload Identity pool that lets only this repository's deploy workflow on `main` act as
#   `github-deploy`, so GitHub holds no Google key at all.
# Secret values never pass through here: they are pasted into Secret Manager by hand.
set -euo pipefail

project="${1:?usage: gcp-setup.sh PROJECT_ID [REGION]}"
region="${2:-us-east4}"
# GitHub's id for tmeng53/wildcard: a repository renamed or recreated under the name can't deploy.
repo_id=1423871728

exists() { "$@" >/dev/null 2>&1; }

for secret in database-url supabase-secret-key; do
  exists gcloud secrets describe "$secret" --project "$project" || {
    echo "gcp-setup: paste the $secret secret into Secret Manager first" >&2
    exit 1
  }
done

gcloud config set project "$project"
number="$(gcloud projects describe "$project" --format 'value(projectNumber)')"
runtime="wildcard-api@$project.iam.gserviceaccount.com"
deployer="github-deploy@$project.iam.gserviceaccount.com"

gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com

exists gcloud artifacts repositories describe wildcard --location "$region" ||
  gcloud artifacts repositories create wildcard --repository-format docker --location "$region"

for account in wildcard-api github-deploy; do
  exists gcloud iam service-accounts describe "$account@$project.iam.gserviceaccount.com" ||
    gcloud iam service-accounts create "$account"
done

grant_project() {
  gcloud projects add-iam-policy-binding "$project" --member "serviceAccount:$1" --role "$2" \
    --condition None >/dev/null
}
# The server reads its secrets as it starts. The project holds nothing but Wildcard's API.
grant_project "$runtime" roles/secretmanager.secretAccessor
grant_project "$deployer" roles/run.admin
# Which secrets exist (names only, not values), so a deploy passes on those that do.
grant_project "$deployer" roles/secretmanager.viewer
gcloud artifacts repositories add-iam-policy-binding wildcard --location "$region" \
  --member "serviceAccount:$deployer" --role roles/artifactregistry.writer >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$runtime" \
  --member "serviceAccount:$deployer" --role roles/iam.serviceAccountUser >/dev/null
gcloud secrets add-iam-policy-binding database-url \
  --member "serviceAccount:$deployer" --role roles/secretmanager.secretAccessor >/dev/null

exists gcloud iam workload-identity-pools describe github --location global ||
  gcloud iam workload-identity-pools create github --location global --display-name "GitHub Actions"
# Only the deploy workflow, run from main in the `beta` environment, may act as the deployer.
condition="assertion.repository_id == '$repo_id' && assertion.ref == 'refs/heads/main' && assertion.job_workflow_ref == 'tmeng53/wildcard/.github/workflows/deploy.yml@refs/heads/main' && assertion.environment == 'beta'"
if exists gcloud iam workload-identity-pools providers describe wildcard --location global \
  --workload-identity-pool github; then
  gcloud iam workload-identity-pools providers update-oidc wildcard --location global \
    --workload-identity-pool github --attribute-condition "$condition"
else
  gcloud iam workload-identity-pools providers create-oidc wildcard --location global \
    --workload-identity-pool github --issuer-uri https://token.actions.githubusercontent.com \
    --attribute-mapping 'google.subject=assertion.sub,attribute.repository_id=assertion.repository_id' \
    --attribute-condition "$condition"
fi
gcloud iam service-accounts add-iam-policy-binding "$deployer" --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/github/attribute.repository_id/$repo_id" \
  >/dev/null

echo
echo "gcp-setup: done. Send Claude this line (none of it is secret):"
echo "GCP_PROJECT_ID=$project GCP_PROJECT_NUMBER=$number GCP_REGION=$region"
