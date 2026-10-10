with stats as (
    select * from {{ ref('stg_facebook_ads_stats') }}
),

ads as (
    select ad_id, ad_name, campaign_id from {{ ref('stg_facebook_ads') }}
),

campaigns as (
    select campaign_id, campaign_name from {{ ref('stg_facebook_campaigns') }}
),

accounts as (
    select account_id, account_name, currency from {{ ref('stg_facebook_accounts') }}
)

select
    'facebook'              as platform,
    stats.ad_date,
    stats.ad_id,
    ads.ad_name,
    ads.campaign_id,
    campaigns.campaign_name,
    stats.account_id,
    accounts.account_name,
    accounts.currency,
    'unknown'               as country,
    stats.spend,
    stats.impressions,
    stats.clicks
from stats
left join ads on stats.ad_id = ads.ad_id
left join campaigns on ads.campaign_id = campaigns.campaign_id
left join accounts on stats.account_id = accounts.account_id
