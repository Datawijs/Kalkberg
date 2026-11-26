{#-
    Marketing channels, from the channels seed (GA-01). Shared with the budget sheets in Power Query
    through budget_channel. 'unattributed' holds orders that no source can link to a channel (GA-06).
-#}
SELECT
    channel_key,
    channel_name,
    channel_group,
    is_paid,
    budget_channel,
    sort_order
FROM {{ ref('channels') }}
