select
    cast(ad_id as string)                                     as ad_id,
    cast(account_id as string)                                as account_id,
    cast(ad_date as date)                                     as ad_date,
    cast(nullif(trim(ad_spend), 'null') as decimal(18, 6))    as spend,
    cast(nullif(trim(ad_impressions), 'null') as bigint)      as impressions,
    cast(nullif(trim(ad_clicks), 'null') as bigint)           as clicks
from {{ source('facebook_ads', 'ads_stats') }}
