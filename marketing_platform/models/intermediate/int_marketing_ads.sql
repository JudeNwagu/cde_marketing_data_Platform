select
    platform, ad_date, ad_id, ad_name, campaign_id, campaign_name,
    account_id, account_name, currency, country,
    spend, impressions, clicks
from {{ ref('int_facebook_ads') }}

union all

select
    platform, ad_date, ad_id, ad_name, campaign_id, campaign_name,
    account_id, account_name, currency, country,
    spend, impressions, clicks
from {{ ref('int_snapchat_ads') }}
