config {
  type:"table",
  name:"mrt_bend_or__listings",
}


with unique_listings as (
    select *
    from ${ref("fct_bend_or__listings")}
    qualify row_number() over (partition by id order by dim_collected_date desc) = 1
)

select *
from unique_listings
