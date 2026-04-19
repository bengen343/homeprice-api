config {
  type:"table",
  name:"dte_bend_or__listings",
}


with timeseries as (
  select
    dim_collected_date,
    -- we cast to string and IFNULL so Dataform's incremental MERGE statement doesn't fail on grouping set NULLs.
    ifnull(cast(is_target as string), 'all') as is_target_segment,
    
    count(id) as met_listings_count,
    avg(met_price) as met_price_avg,
    approx_quantiles(met_price, 2)[offset(1)] as met_price_median,
    avg(met_price_per_sqft) as met_price_per_sqft_avg,
    approx_quantiles(met_price_per_sqft, 2)[offset(1)] as met_price_per_sqft_median,

  from
    ${ref("fct_bend_or__listings")}

  where is_active

  group by
    grouping sets (
      (dim_collected_date),
      (dim_collected_date, is_target)
    )
)

select *
from timeseries
