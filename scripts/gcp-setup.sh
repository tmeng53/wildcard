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
#   sits in a job. Two jobs fit in Cloud Scheduler's free tier (three a billing account);
# - an uptime check on the API's /health and four alert policies, which email the account running
#   this (or ALERT_EMAIL): the API is down, it answers 5xx, a scheduled job's call failed, or the
#   daily push or weekly awards logged an ERROR. Alerting costs nothing until September 2027 at
#   the earliest; then Google charges $0.35 a month for the 5xx condition (uptime and log-match
#   conditions return no points), and the uptime check's ~26k calls a month stay in its free tier.
#   https://cloud.google.com/stackdriver/pricing#monitoring-pricing-summary
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
  cloudscheduler.googleapis.com monitoring.googleapis.com logging.googleapis.com

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
# The AI coach wakes for each check-in and once a day; while coaching is off a run does nothing.
schedule coach '*/10 * * * *'

# Alerts, by email to whoever runs this in Cloud Shell, unless ALERT_EMAIL names someone else.
alert_email="${ALERT_EMAIL:-$(gcloud config get account 2>/dev/null)}"
[[ "$alert_email" == *@* ]] || { echo "gcp-setup: set ALERT_EMAIL to where alerts should go" >&2; exit 1; }
channel="$(gcloud beta monitoring channels list \
  --filter "type=\"email\" AND labels.email_address=\"$alert_email\"" --format 'value(name)' | head -n 1)"
[ -n "$channel" ] || channel="$(gcloud beta monitoring channels create --type email \
  --display-name "Wildcard alerts" --channel-labels "email_address=$alert_email" --format 'value(name)')"

# Is the API up? Three US regions call /health every five minutes; it checks the database too.
api_host="${api_url#https://}"
uptime_check() {
  gcloud monitoring uptime list-configs --filter 'displayName="wildcard-api health"' \
    --format 'value(name)' | head -n 1
}
[ -n "$(uptime_check)" ] ||
  gcloud monitoring uptime create "wildcard-api health" --resource-type uptime-url \
    --resource-labels "host=$api_host,project_id=$project" --protocol https --path /health \
    --period 5 --timeout 10 --regions usa-virginia,usa-oregon,usa-iowa \
    --matcher-content '"ok"' --matcher-type contains-string >/dev/null
check_id="$(uptime_check)"
check_id="${check_id##*/}"

# Each policy is created by its display name, or replaced when it exists, so a rerun applies
# changes made here. Log-match policies email at most once an hour each.
policy_file="$(mktemp)"
trap 'rm -f "$policy_file"' EXIT
alert() {
  cat >"$policy_file"
  local existing
  existing="$(gcloud monitoring policies list --filter "displayName=\"$1\"" --format 'value(name)' | head -n 1)"
  if [ -n "$existing" ]; then
    gcloud monitoring policies update "$existing" --policy-from-file "$policy_file" >/dev/null
  else
    gcloud monitoring policies create --policy-from-file "$policy_file" >/dev/null
  fi
}
logs="https://console.cloud.google.com/logs/query?project=$project"
# Cloud Logging's filter syntax, for the log-match policies (metric filters say resource.label).
api_logs='resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"wildcard-api\"'

alert "Wildcard API is down" <<JSON
{
  "displayName": "Wildcard API is down",
  "documentation": { "mimeType": "text/markdown",
    "content": "$api_url/health failed from more than one region. It fails when the server can't start or can't reach the database. Logs: $logs" },
  "combiner": "OR",
  "conditions": [{
    "displayName": "/health failing",
    "conditionThreshold": {
      "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"$check_id\"",
      "aggregations": [{ "alignmentPeriod": "1200s", "perSeriesAligner": "ALIGN_NEXT_OLDER",
        "crossSeriesReducer": "REDUCE_COUNT_FALSE", "groupByFields": ["resource.label.host"] }],
      "comparison": "COMPARISON_GT", "thresholdValue": 1, "duration": "60s",
      "trigger": { "count": 1 }
    }
  }],
  "notificationChannels": ["$channel"]
}
JSON

alert "Wildcard API answers 5xx" <<JSON
{
  "displayName": "Wildcard API answers 5xx",
  "documentation": { "mimeType": "text/markdown",
    "content": "More than 5 requests in 5 minutes answered 5xx. Unexpected failures are ERROR entries naming their route, with X-Request-Id's value as requestId; a 503 from AI drafts while no model key is set is expected and logs nothing. Logs: $logs" },
  "combiner": "OR",
  "conditions": [{
    "displayName": "More than 5 server errors in 5 minutes",
    "conditionThreshold": {
      "filter": "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wildcard-api\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.response_code_class=\"5xx\"",
      "aggregations": [{ "alignmentPeriod": "300s", "perSeriesAligner": "ALIGN_SUM",
        "crossSeriesReducer": "REDUCE_SUM" }],
      "comparison": "COMPARISON_GT", "thresholdValue": 5, "duration": "0s",
      "trigger": { "count": 1 }
    }
  }],
  "notificationChannels": ["$channel"]
}
JSON

alert "Wildcard scheduled job failed" <<JSON
{
  "displayName": "Wildcard scheduled job failed",
  "documentation": { "mimeType": "text/markdown",
    "content": "Cloud Scheduler's call to a job (daily-progress-push, weekly-awards or coach) failed or timed out. Logs: $logs" },
  "combiner": "OR",
  "conditions": [{
    "displayName": "A Cloud Scheduler attempt failed",
    "conditionMatchedLog": {
      "filter": "resource.type=\"cloud_scheduler_job\" AND severity>=ERROR",
      "labelExtractors": { "job": "EXTRACT(resource.labels.job_id)" }
    }
  }],
  "alertStrategy": { "notificationRateLimit": { "period": "3600s" }, "autoClose": "1800s" },
  "notificationChannels": ["$channel"]
}
JSON

alert "Wildcard job logged an error" <<JSON
{
  "displayName": "Wildcard job logged an error",
  "documentation": { "mimeType": "text/markdown",
    "content": "The daily push, the weekly awards or the coach logged an ERROR (the job label says which). Logs: $logs" },
  "combiner": "OR",
  "conditions": [{
    "displayName": "An ERROR from the daily push, weekly awards or coach",
    "conditionMatchedLog": {
      "filter": "$api_logs AND severity>=ERROR AND jsonPayload.job=(\"daily-progress-push\" OR \"weekly-awards\" OR \"coach\")",
      "labelExtractors": { "job": "EXTRACT(jsonPayload.job)" }
    }
  }],
  "alertStrategy": { "notificationRateLimit": { "period": "3600s" }, "autoClose": "1800s" },
  "notificationChannels": ["$channel"]
}
JSON

echo
echo "gcp-setup: alerts go to $alert_email."
echo "gcp-setup: done. Send Claude this line (none of it is secret):"
echo "GCP_PROJECT_ID=$project GCP_PROJECT_NUMBER=$number GCP_REGION=$region"
