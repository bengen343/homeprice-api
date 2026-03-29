import os
import csv
import io
import requests
from datetime import datetime

# Google Cloud libraries
from google.cloud import secretmanager
from google.cloud import storage


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


def save_to_gcs_as_csv(listings: list, bucket_name: str):
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
    filename = f"{date_str}.csv"
    
    # Upload to Cloud Storage Bucket
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(filename)
    
    blob.upload_from_string(csv_buffer.getvalue(), content_type="text/csv")
    print(f"Successfully uploaded {len(listings)} listings to gs://{bucket_name}/{filename}")


def main():
    print("Starting RentCast data fetch job...")
    try:
        PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT", "home-prices-59122")
        api_key = os.environ.get("RENTCAST_API")
        
        # Get zip codes from environment variable (comma-separated string)
        zip_codes_str = os.environ.get("ZIP_CODES")
        zip_codes = [zip_code.strip() for zip_code in zip_codes_str.split(",")]
        
        # Get bucket name from environment variable
        bucket_name = os.environ.get("BUCKET_NAME")
        
        listings = get_listings_sale(api_key, zip_codes)
        save_to_gcs_as_csv(listings, bucket_name)
    except Exception as e:
        print(f"Cloud Run Job failed: {e}")
        raise

if __name__ == "__main__":
    main()