create or replace table `home-prices-59122.bend_or.listings_cleaned` as
with unique_homes as (
  select *
  from `home-prices-59122.bend_or.listings`
  qualify row_number() over (partition by id order by daysonmarket desc) = 1
),

field_selection as (
  select
    -- keys & identifiers
    -- primary key for this table
    safe_cast(id as string) as id,

    -- secondary/match keys
    safe_cast(mlsnumber as string) as mls_number,

    -- date/time dimensions
    safe_cast(safe.parse_date('%Y%m%d', safe_cast(collected_date as string)) as date) as dim_collected_date,
    safe_cast(createddate as date) as dim_created_date,
    safe_cast(lastseendate as date) as dim_last_seen_date,
    safe_cast(listeddate as date) as dim_listed_date,
    safe_cast(removeddate as date) as dim_removed_date,

    -- dimensions
    safe_cast(lower(json_extract_scalar(builder, '$.development')) as string) as dim_builder_development,
    safe_cast(lower(json_extract_scalar(builder, '$.name')) as string) as dim_builder_name,
    safe_cast(lower(safe_cast(city as string)) as string) as dim_city,
    safe_cast(lower(safe_cast(county as string)) as string) as dim_county,
    safe_cast(countyfips as string) as dim_fips_county,
    safe_cast(statefips as string) as dim_fips_state,
    safe_cast(lower(json_extract_scalar(listingoffice, '$.name')) as string) as dim_listing_office,
    safe_cast(lower(safe_cast(listingtype as string)) as string) as dim_listing_type,
    safe_cast(lower(safe_cast(mlsname as string)) as string) as dim_mls_name,
    safe_cast(lower(safe_cast(propertytype as string)) as string) as dim_property_type,
    safe_cast(upper(safe_cast(state as string)) as string) as dim_state,
    safe_cast(lower(safe_cast(status as string)) as string) as dim_status,
    safe_cast(zipcode as string) as dim_zip,
        
    -- metrics
    safe_cast(bathrooms as float64) as met_bathrooms,
    safe_cast(bedrooms as float64) as met_bedrooms,
    safe_cast(daysonmarket as int64) as met_days_on_market,
    safe_cast(price as int64) as met_price,
    safe_cast(squarefootage as int64) as met_square_feet,
    safe_cast(yearbuilt as int64) as met_year_built,

    -- info
    safe_cast(lower(json_extract_scalar(builder, '$.phone')) as string) as dim_builder_phone,
    safe_cast(formattedaddress as string) as info_full_address,
    safe_cast(safe.parse_json(replace(replace(history, "'", '"'), "None", "null")) as json) as info_history,
    safe_cast(safe.parse_json(replace(replace(hoa, "'", '"'), "None", "null")) as json) as info_hoa,
    safe_cast(longitude as float64) as info_longitude,
    safe_cast(latitude as float64) as info_latitude,
    safe_cast(st_geogpoint(safe_cast(longitude as float64), safe_cast(latitude as float64)) as geography) as info_home_location,
    safe_cast(lower(json_extract_scalar(listingagent, '$.name')) as string) as info_listing_agent,
    safe_cast(lower(json_extract_scalar(listingagent, '$.email')) as string) as info_listing_agent_email,
    safe_cast(json_extract_scalar(listingagent, '$.phone') as string) as info_listing_agent_phone,
    safe_cast(lower(json_extract_scalar(listingagent, '$.website')) as string) as info_listing_agent_website,
    safe_cast(lower(json_extract_scalar(listingoffice, '$.email')) as string) as info_listing_office_email,
    safe_cast(json_extract_scalar(listingoffice, '$.phone') as string) as info_listing_office_phone,
    safe_cast(addressline1 as string) as info_street1,
    safe_cast(addressline2 as string) as info_street2

  from unique_homes
),

field_calculation as (
    select
        field_selection.*,
        
        -- Spatial Relative Pricing:
        -- Compares the price of this home to the average price of comparable homes
        -- (same number of bedrooms) within a 1 kilometer radius (1000 meters).
        round(field_selection.met_price / nullif((
            select avg(b.met_price)
            from field_selection b
            where st_dwithin(field_selection.info_home_location, b.info_home_location, 1000) 
              and field_selection.met_bedrooms = b.met_bedrooms 
        ), 0), 3) as met_price_vs_nearby_comps_ratio,

        -- Additional Derived Metrics
        round(field_selection.met_price / nullif(field_selection.met_square_feet, 0), 2) as met_price_per_sqft,
        extract(year from current_date()) - field_selection.met_year_built as met_home_age_years,
        round(field_selection.met_bathrooms / nullif(field_selection.met_bedrooms, 0), 2) as met_bath_to_bed_ratio,
        case when field_selection.met_days_on_market > 90 then true else false end as is_stale_listing,
        case when field_selection.met_year_built >= extract(year from current_date()) - 1 then true else false end as is_new_construction

    from field_selection
)

select *
from field_calculation
;