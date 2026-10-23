#!/usr/bin/env bash
# One-time setup of the Google Cloud project the API runs in, for .github/workflows/deploy.yml.
# Run it in Cloud Shell (the >_ button at console.cloud.google.com) as the project's owner, after
# pasting the `database-url` and `supabase-secret-key` secrets into Secret Manager:
#   bash <(curl -fsSL https://raw.githubusercontent.com/tmeng53/wildcard/main/scripts/gcp-setup.sh) PROJECT_ID [REGION] [API_URL]
# REGION is the Cloud Run region nearest the Supabase project (us-east4 for Supabase's us-east-1);
# API_URL is where the API answers (https://api.wildcardsquad.com).
# Running it again is safe: it only adds what is missing. A new service account can take a minute
# to be usable, so if a grant fails with "does not exist", wait a minute and run it again.
#
# It makes:
# - `wildcard`, the Artifact Registry repository the server's images go to;
# - `wildcard-api`, the service account Cloud Run runs the server as, which may read the secrets;
# - `github-deploy`, the account the deploy workflow acts as: it may push images, deploy the
#   service, see which secrets exist and read `database-url` to run migrations;
# - a Workload Identity pool that lets only this repository's deploy workflow on `main` act as
#   `github-deploy`, so GitHub holds no Google key at all;
# - `wildcard-scheduler`, the account Cloud Scheduler signs its calls as, and the two jobs it
#   runs: the daily progress push every 15 minutes and the weekly awards every hour. Each call
#   carries an ID token Google signs for that account, which the API checks, so no shared secret
#   sits in a job. Two jobs fit in Cloud Scheduler's free tier (three a billing account).
# Secret values never pass through here: they are pasted into Secret Manager by hand.
set -euo pipefail

project="${1:?usage: gcp-setup.sh PROJECT_ID [REGION] [API_URL]}"
region="${2:-us-east4}"
api_url="${3:-https://api.wildcardsquad.com}"
# The jobs' audience must be the API's origin exactly as the server compares it: no trailing slash.
api_url="${api_url%/}"
[[ "$api_url" =~ ^https://[^/]+$ ]] || { echo "API_URL must be an https origin, like https://api.wildcardsquad.com" >&2; exit 1; }
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
# Cloud Run needs billing on (its free tier still applies).
[ "$(gcloud billing projects describe "$project" --format 'value(billingEnabled)')" = True ] || {
  echo "gcp-setup: turn on billing for $project first (gcloud billing projects link)" >&2
  exit 1
}
runtime="wildcard-api@$project.iam.gserviceaccount.com"
deployer="github-deploy@$project.iam.gserviceaccount.com"
scheduler="wildcard-scheduler@$project.iam.gserviceaccount.com"

gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudscheduler.googleapis.com

exists gcloud artifacts repositories describe wildcard --location "$region" ||
  gcloud artifacts repositories create wildcard --repository-format docker --location "$region"

for account in wildcard-api github-deploy wildcard-scheduler; do
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
condition="assertion.repository_id == '$repo_id' && assertion.ref == 'refs/heads/main' && assertion.workflow_ref == 'tmeng53/wildcard/.github/workflows/deploy.yml@refs/heads/main' && assertion.environment == 'beta'"
# Every claim the condition reads is mapped too, as Google asks.
mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref,attribute.workflow_ref=assertion.workflow_ref,attribute.environment=assertion.environment"
if exists gcloud iam workload-identity-pools providers describe wildcard --location global \
  --workload-identity-pool github; then
  gcloud iam workload-identity-pools providers update-oidc wildcard --location global \
    --workload-identity-pool github --attribute-mapping "$mapping" --attribute-condition "$condition"
else
  gcloud iam workload-identity-pools providers create-oidc wildcard --location global \
    --workload-identity-pool github --issuer-uri https://token.actions.githubusercontent.com \
    --attribute-mapping "$mapping" \
    --attribute-condition "$condition"
fi
gcloud iam service-accounts add-iam-policy-binding "$deployer" --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/github/attribute.repository_id/$repo_id" \
  >/dev/null

# The scheduler's jobs. The API takes a job's call only with an ID token for `wildcard-scheduler`
# and its own URL as the audience (JOBS_SCHEDULER_ACCOUNT, set by the deploy). The account
# needs no role: the API is public and checks the token itself.
# https://cloud.google.com/scheduler/docs/http-target-auth
schedule() {
  local verb=create
  if exists gcloud scheduler jobs describe "$1" --location "$region"; then verb=update; fi
  gcloud scheduler jobs "$verb" http "$1" --location "$region" --schedule "$2" --time-zone Etc/UTC \
    --uri "$api_url/jobs/$1" --http-method POST --attempt-deadline 300s \
    --oidc-service-account-email "$scheduler" --oidc-token-audience "$api_url" >/dev/null
}
# Each member's push goes out at 6pm on their own clock, so the job looks every 15 minutes.
schedule daily-progress-push '*/15 * * * *'
# A squad's awards that couldn't be written are tried again on the next run.
schedule weekly-awards '5 * * * *'

echo
echo "gcp-setup: done. Send Claude this line (none of it is secret):"
echo "GCP_PROJECT_ID=$project GCP_PROJECT_NUMBER=$number GCP_REGION=$region"
