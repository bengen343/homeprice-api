# Homeprice API Fetcher

This repository contains an automated data pipeline that fetches real estate listings from the [Rentcast API](https://rentcast.io/api), formats the data into CSV files, and stores them in a Google Cloud Storage (GCS) bucket. 

The project is designed to run entirely on Google Cloud Platform (GCP) using serverless infrastructure.

## Architecture Overview

- **Compute**: Google Cloud Run Job executes the Python script (`main.py`).
- **Scheduling**: Google Cloud Scheduler triggers the Cloud Run Job automatically every Sunday at 10:00 AM.
- **Storage**: Google Cloud Storage holds the resulting daily CSV extracts.
- **Security**: Google Secret Manager securely stores the Rentcast API Key.
- **CI/CD**: Google Cloud Build compiles the Docker container on every push to the `main` branch and stores it in Artifact Registry.

## Prerequisites

Before deploying this project, you will need:
1. A **Google Cloud Project** with an active billing account.
2. The **Google Cloud SDK (`gcloud`)** installed and authenticated on your local machine.
3. A **Rentcast API Key**.
4. Your code hosted in a **GitHub repository**.

---

## GCP Environment Setup & Configuration

This repository includes a `setup_infrastructure.sh` script that automates the creation of all required GCP resources, IAM roles, and service accounts.

### Step 1: Link your GitHub Repository to GCP
Before running the automated script, you must manually authorize Google Cloud to access your GitHub repository. This is a one-time OAuth requirement.

1. Navigate to **Cloud Build > Repositories** in the Google Cloud Console.
2. Click **Create Host Connection** and select **GitHub**.
3. Follow the OAuth prompts to authorize the Google Cloud Build GitHub App.
4. Name the connection `github-connection` (or update the `GITHUB_CONNECTION` variable in the setup script to match your custom name).

### Step 2: Configure Setup Variables
Open `setup_infrastructure.sh` and update the `Configuration Variables` block at the top of the file to match your environment:

```bash
PROJECT_ID="your-gcp-project-id"
REGION="us-west1"
BUCKET_NAME="your-unique-bucket-name" 
ZIP_CODES="80428,80467,80469,80477,80479,80483,80487,80488"
GITHUB_REPO="your-github-username/your-repo-name"
```

### Step 3: Run the Infrastructure Script
Execute the setup script from your terminal:

```bash
bash setup_infrastructure.sh
```

**Note on the first run:** The script will successfully create your service accounts, IAM bindings, GCS Bucket, Secret, Artifact Registry, and Cloud Build triggers. However, the **Cloud Run Job creation will fail gracefully** (printing a warning) because the Docker image has not been built yet. This is expected behavior!

### Step 4: Add your Rentcast API Key to Secret Manager
The script creates an empty secret placeholder. You need to add your actual API key as a new version:

```bash
echo -n "YOUR_RENTCAST_API_KEY" | gcloud secrets versions add rentcast-api --data-file=-
```

### Step 5: Trigger the First Build
Now that the Cloud Build trigger is created, push a commit to the `main` branch of your GitHub repository. 

Alternatively, you can manually trigger the first build to compile and push your Docker image to Artifact Registry:

```bash
gcloud builds submit --config cloudbuild.yaml .
```

### Step 6: Complete the Infrastructure Setup
Once the Docker image is successfully built and pushed to Artifact Registry (tagged as `:latest`), run the setup script one final time:

```bash
bash setup_infrastructure.sh
```

This time, the script will successfully detect the `:latest` image and create the **Cloud Run Job** and the **Cloud Scheduler** trigger.

---

## Environment Variables

The Python script (`main.py`) expects the following environment variables, which are injected automatically by the Cloud Run Job configuration:

| Variable | Description | Example |
|---|---|---|
| `GOOGLE_CLOUD_PROJECT` | Your GCP Project ID | `home-prices-59122` |
| `RENTCAST_API` | Rentcast API Key (Injected via Secret Manager) | `abc123xyz` |
| `ZIP_CODES` | Comma-separated list of Zip Codes to query | `80428,80467,80469` |
| `BUCKET_NAME` | The GCS bucket where CSVs will be saved | `routt-co-home-prices` |

## Local Development

To test the Python script locally without deploying to GCP:

1. Set the required environment variables locally:
   ```bash
   export RENTCAST_API="your_api_key"
   export ZIP_CODES="80487,80488"
   export BUCKET_NAME="your-test-bucket"
   ```
2. Authenticate your local shell with Google Cloud so the script can access your GCS bucket:
   ```bash
   gcloud auth application-default login
   ```
3. Run the script:
   ```bash
   python main.py
   ```