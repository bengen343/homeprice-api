#!/bin/bash
set -e

# ==============================================================================
# Configuration Variables
# ==============================================================================
PROJECT_ID=""
REGION=""
REPO_NAME="homeprice-api"
BUCKET_NAME="routt-co-home-prices" 
JOB_NAME="homeprice-api-routt-co"
ZIP_CODES="80428,80467,80469,80477,80479,80483,80487,80488"
SECRET_NAME="rentcast-api"
GITHUB_CONNECTION="github-connection"
GITHUB_REPO="your-github-username/your-repo-name" # Fill this in
CLOUD_BUILD_REPO="homeprice-api-repo-gcp"
TRIGGER_NAME="homeprice-api-build-trigger"
SCHEDULER_JOB_NAME="homeprice-api-routt-co-schedule"
SCHEDULER_CRON="0 10 * * 7" # Runs every Sunday at 10:00 AM

# Service Account Names
SA_RUN="rentcast-job-sa"
SA_BUILD="rentcast-build-sa"
SA_SCHEDULER="rentcast-scheduler-sa"

echo "Starting GCP infrastructure setup for $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# ==============================================================================
# 1. Enable Required APIs
# ==============================================================================
echo "Enabling required GCP APIs..."
gcloud services enable `
    run.googleapis.com `
    cloudbuild.googleapis.com `
    artifactregistry.googleapis.com `
    secretmanager.googleapis.com `
    storage.googleapis.com `
    iam.googleapis.com `
    cloudscheduler.googleapis.com `
    bigquery.googleapis.com `
    bigquerydatatransfer.googleapis.com

# ==============================================================================
# 2. IAM & Service Accounts
# ==============================================================================
echo "Creating Service Accounts..."
gcloud iam service-accounts create $SA_RUN --display-name="Cloud Run Runtime SA" || echo "SA exists."
gcloud iam service-accounts create $SA_BUILD --display-name="Cloud Build SA" || echo "SA exists."
gcloud iam service-accounts create $SA_SCHEDULER --display-name="Cloud Scheduler Invoker SA" || echo "SA exists."

echo "Assigning IAM Roles..."
# Cloud Run Runtime permissions
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_RUN}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/storage.objectAdmin"
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_RUN}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/secretmanager.secretAccessor"

# Cloud Build permissions
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_BUILD}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/artifactregistry.writer"
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_BUILD}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/logging.logWriter"

# BigQuery permissions for Cloud Build / Scheduled Queries
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:homeprice-api-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/bigquery.jobUser" || echo "Optional SA"
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:homeprice-api-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/bigquery.dataEditor" || echo "Optional SA"
    
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_BUILD}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/bigquery.jobUser"
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_BUILD}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/bigquery.dataEditor"

# Cloud Scheduler permissions
gcloud projects add-iam-policy-binding $PROJECT_ID `
    --member="serviceAccount:${SA_SCHEDULER}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --role="roles/run.invoker"

# ==============================================================================
# 3. Create Storage & Secrets
# ==============================================================================
echo "Creating Artifact Registry..."
gcloud artifacts repositories create $REPO_NAME `
    --repository-format=docker `
    --location=$REGION `
    --description="Docker repository for Homeprice API" || echo "Repo exists."

echo "Creating Cloud Storage bucket..."
gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION || echo "Bucket exists."

echo "Creating Secret Manager Secret..."
gcloud secrets create $SECRET_NAME --replication-policy="automatic" || echo "Secret exists."

# ==============================================================================
# 4. Cloud Build Trigger
# ==============================================================================
echo "Creating Cloud Build Repository Connection..."
gcloud builds repositories create $CLOUD_BUILD_REPO `
    --project=$PROJECT_ID `
    --location=$REGION `
    --connection=$GITHUB_CONNECTION `
    --repo-id=$GITHUB_REPO || echo "Cloud Build Repository may already exist."

echo "Creating Cloud Build Trigger..."
gcloud builds triggers create github `
    --name=$TRIGGER_NAME `
    --repository=$CLOUD_BUILD_REPO `
    --branch-pattern="^main$" `
    --build-config="cloudbuild.yaml" `
    --service-account="projects/${PROJECT_ID}/serviceAccounts/${SA_BUILD}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --project=$PROJECT_ID `
    --region=$REGION || echo "Trigger may already exist."

# ==============================================================================
# 5. Cloud Run Job & Scheduler
# ==============================================================================
echo "Creating Cloud Run Job..."
IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${REPO_NAME}:latest"

gcloud run jobs create $JOB_NAME `
    --region=$REGION `
    --image=$IMAGE_URL `
    --set-env-vars="^@^BUCKET_NAME=${BUCKET_NAME}@ZIP_CODES=${ZIP_CODES}" `
    --set-secrets="RENTCAST_API=${SECRET_NAME}:latest" `
    --service-account="${SA_RUN}@${PROJECT_ID}.iam.gserviceaccount.com" `
    --max-retries=3 || echo "Job creation failed (Ensure the :latest image has been built first)."

echo "Creating Cloud Scheduler Trigger..."
gcloud scheduler jobs create http $SCHEDULER_JOB_NAME `
    --location=$REGION `
    --schedule="$SCHEDULER_CRON" `
    --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" `
    --http-method=POST `
    --oidc-service-account-email="${SA_SCHEDULER}@${PROJECT_ID}.iam.gserviceaccount.com" || echo "Scheduler job exists."

# ==============================================================================
# 6. BigQuery Scheduled Queries
# ==============================================================================
echo "Creating BigQuery Scheduled Query..."

# We use jq to safely escape the multi-line SQL file into a JSON string parameter
PARAMS=$(jq -n --arg q "$(cat sql/listings_cleaned.sql)" '{"query": $q}')

bq mk `
    --transfer_config `
    --project_id=$PROJECT_ID `
    --data_source=scheduled_query `
    --display_name="Weekly Clean Listings Update" `
    --schedule="every sunday 11:00 from America/Denver" `
    --params="$PARAMS" || echo "Scheduled query creation failed or already exists."

echo "Infrastructure setup complete!"