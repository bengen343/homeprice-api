config {
  type:"table",
  name:"dte_bend_or__listings",
}


with timeseries as (
  select
    -- date/time dimensions
    dim_collected_date,

    -- boolean dimensions
    -- we cast to string and ifnull so we dont end up with nulls in the grouping sets.
    ifnull(cast(is_target as string), 'all') as is_target_segment,
    
    -- metrics
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
),

moving_averages as (
  select
    *,
    
    -- 4-week moving average
    avg(met_price_median) over(
      partition by is_target_segment 
      order by dim_collected_date 
      rows between 3 preceding and current row
    ) as met_04_week_ma,
    
    -- 12-week moving average
    avg(met_price_median) over(
      partition by is_target_segment 
      order by dim_collected_date 
      rows between 11 preceding and current row
    ) as met_12_week_ma,
    
    -- 52-week moving average
    avg(met_price_median) over(
      partition by is_target_segment 
      order by dim_collected_date 
      rows between 51 preceding and current row
    ) as met_52_week_ma
  from timeseries
),

yoy_comparison as (
  select
    moving_averages.*,

    -- prior year moving averages
    prior_year.met_04_week_ma as met_prior_04_week_ma,
    prior_year.met_12_week_ma as met_prior_12_week_ma,
    prior_year.met_52_week_ma as met_prior_52_week_ma,
    
    -- crossover signals
    case
      when moving_averages.met_12_week_ma < moving_averages.met_52_week_ma
        and lag(moving_averages.met_12_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc) > lag(moving_averages.met_52_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc)
        then true
      else false
    end as is_macd_cross_down,
    case
      when moving_averages.met_12_week_ma > moving_averages.met_52_week_ma
        and lag(moving_averages.met_12_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc) < lag(moving_averages.met_52_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc)
        then true
      else false
    end as is_macd_cross_up,

    case
      when moving_averages.met_12_week_ma < prior_year.met_04_week_ma
        and lag(moving_averages.met_12_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc) > lag(prior_year.met_04_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc)
        then true
      else false
    end as is_yoy_cross_down,
    case
      when moving_averages.met_12_week_ma > prior_year.met_04_week_ma
        and lag(moving_averages.met_12_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc) < lag(prior_year.met_04_week_ma, 1) over (partition by moving_averages.is_target_segment order by moving_averages.dim_collected_date asc)
        then true
      else false
    end as is_yoy_cross_up

  from moving_averages
  -- self join to 52 weeks prior to safely grab the yoy moving average
  left join moving_averages as prior_year
    on moving_averages.is_target_segment = prior_year.is_target_segment
    and prior_year.dim_collected_date = date_sub(moving_averages.dim_collected_date, interval 52 week)
)

select *
from yoy_comparison
