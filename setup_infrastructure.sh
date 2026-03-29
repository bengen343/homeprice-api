#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
# Configuration Variables
# ==============================================================================
PROJECT_ID="home-prices-59122"
REGION="us-west1"
REPO_NAME="homeprice-api"
BUCKET_NAME="routt-co-home-prices" # Change this to your actual desired bucket name
JOB_NAME="homeprice-api-routt-co"
ZIP_CODES="80428,80467,80469,80477,80479,80483,80487,80488"
SECRET_NAME="rentcast-api"
SERVICE_ACCOUNT=" @${PROJECT_ID}.iam.gserviceaccount.com"
GITHUB_CONNECTION="github-connection"
GITHUB_REPO=""
CLOUD_BUILD_REPO="homeprice-api-repo-gcp"
TRIGGER_NAME="homeprice-api-build-trigger"

echo "Starting GCP infrastructure setup for $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# ==============================================================================
# 1. Enable Required APIs
# ==============================================================================
echo "Enabling required GCP APIs..."
gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    storage.googleapis.com

# ==============================================================================
# 2. Create Artifact Registry Repository (if it doesn't exist)
# ==============================================================================
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create $REPO_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository for Homeprice API" || echo "Repository may already exist, skipping."

# ==============================================================================
# 6. Create Cloud Build Repository and Trigger
# ==============================================================================
echo "Creating Cloud Build Repository..."
# Note: The connection ($GITHUB_CONNECTION) must be created beforehand (often via the GCP Console) 
# to handle the one-time OAuth authorization between Google Cloud and GitHub.
gcloud builds repositories create $CLOUD_BUILD_REPO \
    --project=$PROJECT_ID \
    --location=$REGION \
    --connection=$GITHUB_CONNECTION \
    --repo-id=$GITHUB_REPO || echo "Cloud Build Repository may already exist."

echo "Creating Cloud Build Trigger..."
gcloud builds triggers create github \
    --name=$TRIGGER_NAME \
    --repository=$CLOUD_BUILD_REPO \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --project=$PROJECT_ID \
    --region=$REGION || echo "Trigger may already exist."

# ==============================================================================
# 3. Create Cloud Storage Bucket
# ==============================================================================
echo "Creating Cloud Storage bucket..."
gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION || echo "Bucket may already exist, skipping."

# ==============================================================================
# 4. Create Secret Manager Secret (Placeholder)
# ==============================================================================
echo "Creating Secret for Rentcast API..."
gcloud secrets create $SECRET_NAME --replication-policy="automatic" || echo "Secret may already exist."
# Note: You will still need to manually add a new version with the actual key value.

# ==============================================================================
# 5. Create Cloud Run Job
# ==============================================================================
echo "Creating Cloud Run Job..."
IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${REPO_NAME}:latest"

gcloud run jobs create $JOB_NAME \
    --region=$REGION \
    --image=$IMAGE_URL \
    --execution-environment=gen2 \
    --set-env-vars="^@^BUCKET_NAME=${BUCKET_NAME}@ZIP_CODES=${ZIP_CODES}" \
    --set-secrets="RENTCAST_API=${SECRET_NAME}:latest" \
    --cpu=1 \
    --memory=1Gi \
    --max-retries=3 \
    --task-timeout=600s \
    --service-account=$SERVICE_ACCOUNT || echo "Job creation failed (it may already exist or the image is missing)."



echo "Infrastructure setup complete!"