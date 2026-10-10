select
    cast(ad_detail_id as string)                              as ad_id,
    cast(ad_date as date)                                     as ad_date,
    upper(trim(ad_currency_code))                             as currency,
    upper(trim(ad_country))                                   as country,
    cast(nullif(trim(ad_spend), 'null') as decimal(18, 6))    as spend,
    cast(nullif(trim(ad_impressions), 'null') as bigint)      as impressions,
    cast(nullif(trim(ad_clicks), 'null') as bigint)           as clicks
from {{ source('snapchat_ads', 'ads_stats') }}
