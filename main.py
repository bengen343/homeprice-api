import os
import csv
import io
import requests
from datetime import datetime

# Google Cloud libraries
from google.cloud import secretmanager
from google.cloud import storage

# Ensure your Cloud Run Job has the appropriate service account with permissions for:
# - Secret Manager Secret Accessor
# - Storage Object Admin

# Google Cloud automatically populates GOOGLE_CLOUD_PROJECT in most serverless environments
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "your-project-id")

def get_api_key() -> str:
    """Retrieve the RentCast API key from Google Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/rentcast-api/versions/latest"
    
    response = client.access_secret_version(request={"name": name})
    # Decode and return the secret payload
    return response.payload.data.decode("UTF-8").strip()


def get_listings_sale(api_key: str, zip_lst: list) -> list:
    """Fetch homes for sale."""
    headers = {
        "accept": "application/json",
        "X-Api-Key": api_key
    }
    
    all_listings = []
    limit = 500 # Max results per page per API documentation
    
    for zip_code in zip_lst:
        offset = 0
        
        while True:
            # Construct the endpoint URL using ZIP code and Property Type
            url = (
                f"https://api.rentcast.io/v1/listings/sale"
                f"?zipCode={zip_code}"
                f"&propertyType=Single%20Family"
                f"&limit={limit}"
                f"&offset={offset}"
            )
            
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            data = response.json()
            
            if not data:
                break
                
            all_listings.extend(data)
            
            # If the length of the data returned is less than the limit, it means we hit the last page
            if len(data) < limit:
                break
                
            # Paginate forward
            offset += limit

    return all_listings


def save_to_gcs_as_csv(listings: list):
    """Format results to one per row and save to Cloud Storage."""
    if not listings:
        print("No listings found to save.")
        return
        
    # Dynamically extract all possible field names from the results to form the CSV headers
    fieldnames = set()
    for listing in listings:
        fieldnames.update(listing.keys())
    
    # Add collected_date to the fieldnames
    fieldnames.add('collected_date')
    fieldnames = sorted(list(fieldnames))
    
    date_str = datetime.now().strftime("%Y%m%d")
    csv_buffer = io.StringIO()
    writer = csv.DictWriter(csv_buffer, fieldnames=fieldnames)
    writer.writeheader()
    
    for listing in listings:
        row = {}
        for key in fieldnames:
            value = listing.get(key, "")
            
            # Rentcast contains nested objects (like 'history', 'hoa', 'listingAgent').
            # We stringify nested lists/dicts to guarantee strict "one result per row" formatting in standard CSV.
            if isinstance(value, (dict, list)):
                value = str(value)
                
            row[key] = value
        
        # Add the collected_date value
        row['collected_date'] = date_str
        writer.writerow(row)
        
    # Generate the YYYYMMDD filename
    filename = f"routt_county_sales_{date_str}.csv"
    
    # Upload to Cloud Storage Bucket
    storage_client = storage.Client()
    bucket = storage_client.bucket("routt-co-home-prices")
    blob = bucket.blob(filename)
    
    blob.upload_from_string(csv_buffer.getvalue(), content_type="text/csv")
    print(f"Successfully uploaded {len(listings)} listings to gs://routt-co-home-prices/{filename}")


def main():
    print("Starting RentCast data fetch job...")
    try:
        api_key = get_api_key()
        zip_codes = ["80428", "80467", "80469", "80477", "80479", "80483", "80487", "80488"]
        listings = get_listings_sale(api_key, zip_codes)
        save_to_gcs_as_csv(listings)
    except Exception as e:
        print(f"Cloud Run Job failed: {e}")
        raise

if __name__ == "__main__":
    main()