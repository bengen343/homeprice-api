config {
  type:"incremental",
  name:"fct_bend_or__listings",
  bigquery:{
    partitionBy:"dim_collected_date"
  }
}


with field_calculation as (
    select
        listings.*,

        -- boolean dimensions
        case
            when listings.dim_removed_date is null then true
            else false
        end as is_active,
        case
            when listings.met_year_built >= extract(year from current_date()) - 1 then true else false
        end as is_new_construction,
        case
            when (date_diff(current_date(), listings.dim_created_date, day) > 90) and listings.dim_removed_date is null then true
            else false
        end as is_stale,
        case
          when listings.dim_zip = '97703'
            and st_dwithin(st_geogpoint(-121.32954935564848, 44.06101015041879), listings.info_home_location, 3000) 
            and not (
                case
                    when (date_diff(current_date(), listings.dim_created_date, day) > 90) and listings.dim_removed_date is null
                    then true
                    else false
                end
            )
                then true
          else false
        end as is_target,

        -- derived metrics
        listings.met_bathrooms / nullif(listings.met_bedrooms, 0) as met_bath_to_bed_ratio,
        extract(year from current_date()) - listings.met_year_built as met_home_age_years,
        listings.met_price / nullif(listings.met_square_feet, 0) as met_price_per_sqft,
        
        -- Spatial Relative Pricing:
        -- Compares the price of this home to the average price of comparable homes
        -- (same number of bedrooms) within a 1 kilometer radius (1000 meters).
        listings.met_price / nullif((
            select avg(b.met_price)
            from ${ref("bse_bend_or__listings")} as b
            where st_dwithin(listings.info_home_location, b.info_home_location, 1000) 
              and listings.met_bedrooms = b.met_bedrooms 
              and listings.dim_collected_date = b.dim_collected_date
        ), 0) as met_price_vs_comps_ratio

    from ${ref("bse_bend_or__listings")} as listings
    ${when(incremental(), `where listings.dim_collected_date > (select max(dim_collected_date) from ${self()})`)}
)

select *
from field_calculation
