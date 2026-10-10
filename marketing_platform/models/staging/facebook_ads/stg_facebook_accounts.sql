select
    cast(account_id as string)              as account_id,
    trim(account_name)                      as account_name,
    upper(trim(ad_currency_code))           as currency,
    cast(account_created_at as timestamp)   as account_created_at,
    cast(account_updated_at as timestamp)   as account_updated_at
from {{ source('facebook_ads', 'accounts') }}
