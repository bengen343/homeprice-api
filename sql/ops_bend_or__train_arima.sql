config {
  type: "operations",
  hasOutput: true,
  name: "ops_bend_or__train_arima"
}


-- create the bigquery ml arima_plus model
create or replace model ${self()}
options(
  model_type='ARIMA_PLUS',
  time_series_timestamp_col='dim_collected_date',
  time_series_data_col='met_metric_value',
  time_series_id_col=['is_target_segment', 'dim_metric_name'],
  data_frequency='WEEKLY',
  holiday_region='US'
) as
select
  dim_collected_date,
  is_target_segment,
  dim_metric_name,
  met_metric_value
from (
  select
    dim_collected_date,
    is_target_segment,
    cast(met_listings_count as float64) as met_listings_count,
    cast(met_price_avg as float64) as met_price_avg,
    cast(met_price_median as float64) as met_price_median,
    cast(met_price_per_sqft_avg as float64) as met_price_per_sqft_avg,
    cast(met_price_per_sqft_median as float64) as met_price_per_sqft_median
  from ${ref("dte_bend_or__listings")}
)
unpivot(met_metric_value for dim_metric_name in (
  met_listings_count,
  met_price_avg,
  met_price_median,
  met_price_per_sqft_avg,
  met_price_per_sqft_median
))
where met_metric_value is not null
;
