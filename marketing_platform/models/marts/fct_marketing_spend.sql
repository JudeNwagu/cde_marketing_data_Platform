{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='marketing_spend_key',
        on_schema_change='append_new_columns'
    )
}}

with ads as (
    select * from {{ ref('int_marketing_ads') }}
    {% if is_incremental() %}
    -- Only reprocess the last 3 days; platforms often revise recent numbers
    where ad_date >= (select date_sub(max(report_date), 3) from {{ this }})
    {% endif %}
),

daily as (
    select
        ad_date                                   as report_date,
        platform,
        campaign_id,
        campaign_name,
        account_id,
        country,
        currency,
        sum(spend)                                as spend,
        sum(impressions)                          as impressions,
        sum(clicks)                               as clicks,
        bool_or(clicks is null)                   as has_missing_clicks,
        bool_or(impressions is null)              as has_missing_impressions
    from ads
    group by
        ad_date, platform, campaign_id, campaign_name,
        account_id, country, currency
)

select
    {{ dbt_utils.generate_surrogate_key(
        ['report_date', 'platform', 'campaign_id', 'country', 'currency']
    ) }}                                          as marketing_spend_key,
    report_date,
    platform,
    campaign_id,
    campaign_name,
    account_id,
    country,
    currency,
    spend,
    impressions,
    clicks,
    try_divide(clicks, impressions)               as ctr,
    try_divide(spend, clicks)                     as cpc,
    try_divide(spend, impressions) * 1000         as cpm,
    has_missing_clicks,
    has_missing_impressions
from daily
