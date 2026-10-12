{{ config(materialized='ephemeral') }}

with stats as (
    select * from {{ ref('stg_snapchat_ads_stats') }}
),

ads as (
    select ad_id, ad_group_id, ad_name from {{ ref('stg_snapchat_ads') }}
),

ad_groups as (
    select ad_group_id, campaign_id from {{ ref('stg_snapchat_ad_groups') }}
),

campaigns as (
    select campaign_id, account_id, campaign_name from {{ ref('stg_snapchat_campaigns') }}
)

select
    'snapchat'                  as platform,
    stats.ad_date,
    stats.ad_id,
    ads.ad_name,
    ad_groups.campaign_id,
    campaigns.campaign_name,
    campaigns.account_id,
    cast(null as string)        as account_name,
    stats.currency,
    stats.country,
    stats.spend,
    stats.impressions,
    stats.clicks
from stats
left join ads on stats.ad_id = ads.ad_id
left join ad_groups on ads.ad_group_id = ad_groups.ad_group_id
left join campaigns on ad_groups.campaign_id = campaigns.campaign_id
