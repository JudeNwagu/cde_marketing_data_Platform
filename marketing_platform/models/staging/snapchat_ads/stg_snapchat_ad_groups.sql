with typed as (

    select
        cast(ad_group_id as string)               as ad_group_id,
        cast(campaign_id as string)               as campaign_id,
        trim(ad_group_name)                       as ad_group_name,
        cast(ad_group_updated_at as timestamp)    as ad_group_updated_at,
        cast(_surrogate_key as string)            as version_key
    from {{ source('snapchat_ads', 'ad_groups') }}

)

select
    ad_group_id,
    campaign_id,
    ad_group_name,
    ad_group_updated_at
from typed
qualify row_number() over (
    partition by ad_group_id
    order by ad_group_updated_at desc, version_key desc
) = 1
