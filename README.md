# Homeprice Data Pipeline

This repository contains an automated ELT (Extract, Load, Transform) data pipeline that fetches real estate listings from the [Rentcast API](https://rentcast.io/api), stores the raw data in Google Cloud Storage (GCS), and transforms it into highly modeled, queryable analytical tables in Google BigQuery.

The project is designed to run entirely on Google Cloud Platform (GCP) using serverless infrastructure and follows enterprise data modeling patterns.

## Architecture Overview

- **Extract (Python)**: A Google Cloud Run Job executes a Python script to paginate through the Rentcast API and save the raw JSON responses as flat CSVs in GCS.
- **Load (BigQuery)**: External tables in BigQuery sit on top of the GCS bucket to make the raw CSVs instantly queryable.
- **Transform (SQL)**: A series of modular, incremental SQL models parse, clean, enrich, and aggregate the raw data into fact and dimension tables.
- **Orchestration**: Google Cloud Scheduler triggers the Cloud Run Job automatically every Sunday at 10:00 AM.
- **CI/CD**: Google Cloud Build compiles the Docker container from the `extract/` directory on every push to the `main` branch.

---

## Repository Structure

To keep concerns separated, the repository is organized into three main directories:

```text
homeprice-api/
├── extract/                        # Data Extraction App
│   ├── main.py                     # The Python script executed by Cloud Run
│   ├── requirements.txt            # Python dependencies
│   └── Dockerfile                  # Container definition for Cloud Build
│
├── sql/                            # BigQuery Transformations (Dataform style)
│   ├── bse_bend_or__listings.sql   # Base: Cleans, casts types, parses JSON
│   ├── fct_bend_or__listings.sql   # Fact: Adds derived metrics and spatial comps
│   ├── dte_bend_or__listings.sql   # Date: Time-series aggregations by date/segment
│   ├── mrt_bend_or__listings.sql   # Mart: Latest state snapshot of all homes
│   └── bigquery_external_table.sql # DDL to mount the GCS bucket to BigQuery
│
└── infra/                          # CI/CD and Provisioning
    ├── setup_infrastructure.sh     # PowerShell script to deploy all GCP resources
    └── cloudbuild.yaml             # CI/CD pipeline configuration
```

---

## GCP Environment Setup & Configuration

This repository includes a `setup_infrastructure.sh` script that automates the creation of all required GCP resources, IAM roles, and service accounts. **Note: This script is written using PowerShell syntax.**

### Step 1: Link your GitHub Repository to GCP
Before running the automated script, you must manually authorize Google Cloud to access your GitHub repository.
1. Navigate to **Cloud Build > Repositories** in the Google Cloud Console.
2. Click **Create Host Connection** and select **GitHub**.
3. Follow the OAuth prompts. Name the connection `github-connection` (or update the `GITHUB_CONNECTION` variable in the setup script).

### Step 2: Configure Setup Variables
Open `infra/setup_infrastructure.sh` and update the `Configuration Variables` block at the top of the file:
```powershell
$PROJECT_ID="your-gcp-project-id"
$REGION="us-west1"
$BUCKET_NAME="your-unique-bucket-name" 
$ZIP_CODES="80428,80467,80469,80477,80479,80483,80487,80488"
$GITHUB_REPO="your-github-username/your-repo-name"
```

### Step 3: Run the Infrastructure Script
Execute the setup script from a **PowerShell** terminal:
```powershell
.\infra\setup_infrastructure.sh
```
*Note on the first run:* The script will create your service accounts, GCS Bucket, Secret, Artifact Registry, and Cloud Build triggers. The Cloud Run Job creation will gracefully fail because the Docker image hasn't been built yet.

### Step 4: Add your Rentcast API Key to Secret Manager
The script creates an empty secret placeholder. Add your actual API key:
```powershell
echo -n "YOUR_RENTCAST_API_KEY" | gcloud secrets versions add rentcast-api --data-file=-
```

### Step 5: Trigger the First Build
Push a commit to the `main` branch of your GitHub repository to trigger Cloud Build, or trigger it manually:
```powershell
gcloud builds submit --config infra/cloudbuild.yaml extract/
```

### Step 6: Complete the Infrastructure Setup
Once the Docker image is successfully built and pushed to Artifact Registry (tagged as `:latest`), run the setup script one final time:
```powershell
.\infra\setup_infrastructure.sh
```
This will successfully deploy the **Cloud Run Job** and bind the **Cloud Scheduler**.

---

## Data Modeling 

The transformations in `sql/` follow a modular, incremental architecture. While they contain Dataform/dbt style macros (like `${ref()}` and `${when(incremental()...)}`), they represent a rigorous 4-tier ELT pipeline:

1. **`bse_` (Base)**: An append-only model that strictly handles type-casting, standardizing field names, and parsing messy stringified JSON arrays into native BigQuery JSON/Geography types.
2. **`fct_` (Fact)**: An enrichment layer that derives new metrics (like `is_stale`, `is_target`). It also features advanced BigQuery spatial functions (`ST_DWithin`) to calculate a home's relative pricing against comparable homes within a 1km radius on the exact day it was scraped.
3. **`dte_` (Date/Time-Series)**: Uses BigQuery `GROUPING SETS` to efficiently calculate both overall market medians/averages and segment-specific medians/averages in a single pass. 
4. **`mrt_` (Mart)**: A presentation-layer view that queries the `fct_` table to return only the absolute latest, deduped snapshot of every home ever seen.

## Local Development (Python Extractor)

To test the Python extraction script locally:
1. Set the required environment variables:
   ```powershell
   $env:RENTCAST_API="your_api_key"
   $env:ZIP_CODES="80487,80488"
   $env:BUCKET_NAME="your-test-bucket"
   ```
2. Authenticate your local shell so the script can access your GCS bucket:
   ```powershell
   gcloud auth application-default login
   ```
3. Run the script:
   ```powershell
   python extract/main.py
   ```