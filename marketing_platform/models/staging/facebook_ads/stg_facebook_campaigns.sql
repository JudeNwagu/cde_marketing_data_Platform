select
    cast(campaign_id as string)             as campaign_id,
    trim(campaign_name)                     as campaign_name,
    cast(campaign_updated_at as timestamp)  as campaign_updated_at
from {{ source('facebook_ads', 'campaigns') }}
