config {
  type: "table",
  name: "mrt_bend_or__anomalies"
}

-- uses the trained arima_plus model to evaluate the timeseries for structural anomalies
with arima as (
  select
    cast(dim_collected_date as date) as dim_collected_date,
    is_target_segment,
    dim_metric_name,
    is_anomaly,
    lower_bound as met_lower_bound,
    upper_bound as met_upper_bound,
    anomaly_probability as met_anomaly_probability
  from ml.detect_anomalies(
    model ${ref("ops_bend_or__train_arima")},
    struct(0.95 as anomaly_prob_threshold)
  )
),

-- re-orient the unpivoted long format back into a wide format matching the original table
pivoted_arima as (
  select * from (
    select
      dim_collected_date,
      is_target_segment,
      dim_metric_name,
      is_anomaly,
      met_lower_bound as lower_bound,
      met_upper_bound as upper_bound,
      met_anomaly_probability as anomaly_prob
    from arima
  )
  pivot(
    max(is_anomaly) as is_anomaly,
    max(lower_bound) as lower_bound,
    max(upper_bound) as upper_bound,
    max(anomaly_prob) as anomaly_prob
    for dim_metric_name in (
      'met_listings_count',
      'met_price_avg',
      'met_price_median',
      'met_price_per_sqft_avg',
      'met_price_per_sqft_median'
    )
  )
),

timeseries as (
  -- join back to the original timeseries data for presentation
  select
    dte.*,

    -- listings count anomalies
    pivoted_arima.is_anomaly_met_listings_count as is_listings_count_anomaly,
    pivoted_arima.lower_bound_met_listings_count as met_listings_count_lower_bound,
    pivoted_arima.upper_bound_met_listings_count as met_listings_count_upper_bound,
    pivoted_arima.anomaly_prob_met_listings_count as met_listings_count_anomaly_probability,

    -- price avg anomalies
    pivoted_arima.is_anomaly_met_price_avg as is_price_avg_anomaly,
    pivoted_arima.lower_bound_met_price_avg as met_price_avg_lower_bound,
    pivoted_arima.upper_bound_met_price_avg as met_price_avg_upper_bound,
    pivoted_arima.anomaly_prob_met_price_avg as met_price_avg_anomaly_probability,

    -- price median anomalies
    pivoted_arima.is_anomaly_met_price_median as is_price_median_anomaly,
    pivoted_arima.lower_bound_met_price_median as met_price_median_lower_bound,
    pivoted_arima.upper_bound_met_price_median as met_price_median_upper_bound,
    pivoted_arima.anomaly_prob_met_price_median as met_price_median_anomaly_probability,

    -- price per sqft avg anomalies
    pivoted_arima.is_anomaly_met_price_per_sqft_avg as is_price_per_sqft_avg_anomaly,
    pivoted_arima.lower_bound_met_price_per_sqft_avg as met_price_per_sqft_avg_lower_bound,
    pivoted_arima.upper_bound_met_price_per_sqft_avg as met_price_per_sqft_avg_upper_bound,
    pivoted_arima.anomaly_prob_met_price_per_sqft_avg as met_price_per_sqft_avg_anomaly_probability,

    -- price per sqft median anomalies
    pivoted_arima.is_anomaly_met_price_per_sqft_median as is_price_per_sqft_median_anomaly,
    pivoted_arima.lower_bound_met_price_per_sqft_median as met_price_per_sqft_median_lower_bound,
    pivoted_arima.upper_bound_met_price_per_sqft_median as met_price_per_sqft_median_upper_bound,
    pivoted_arima.anomaly_prob_met_price_per_sqft_median as met_price_per_sqft_median_anomaly_probability

  from ${ref("dte_bend_or__listings")} as dte
  left join pivoted_arima
    on dte.dim_collected_date = pivoted_arima.dim_collected_date
    and dte.is_target_segment = pivoted_arima.is_target_segment
  order by dte.dim_collected_date desc, dte.is_target_segment
)

select *
from timeseries
