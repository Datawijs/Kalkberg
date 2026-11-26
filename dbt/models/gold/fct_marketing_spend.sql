{#-
    Actual marketing cost (M3, M4, F1), one row per day, channel and campaign.
      paid_search   Google Ads cost, from the platform report
      paid_social   Meta cost, from the platform report (ad sets added up)
      influencer    the monthly fee of each contract, spread evenly over the days of the month, only
                    on the days the contract runs (so a contract that starts on the 15th costs half a fee)
      affiliate     estimated commission: 8% of the affiliate orders' revenue excl. VAT and shipping
                    (orders with order_channel_key = affiliate, not cancelled). The network's invoices
                    are not in any source, so is_estimated = true.
    Email (the Marketing Cloud licence) and SEO have a budget but no actual cost in any source; they
    are compared with the budget in Power BI.
-#}
WITH google AS (
    SELECT report_date AS spend_date, channel_key, {{ campaign_key('channel_key', 'campaign_name') }} AS campaign_key,
           sum(cost) AS cost, 'platform report' AS cost_source, false AS is_estimated
    FROM {{ ref('ads_google_daily') }}
    GROUP BY 1, 2, 3
),

meta AS (
    SELECT report_date, channel_key, {{ campaign_key('channel_key', 'campaign_name') }},
           sum(cost), 'platform report', false
    FROM {{ ref('ads_meta_daily') }}
    GROUP BY 1, 2, 3
),

influencer AS (
    SELECT
        d::date,
        'influencer',
        {{ campaign_key("'influencer'", 'c.creator') }},
        round(c.monthly_fee_eur
              / extract(day FROM date_trunc('month', d) + interval '1 month - 1 day'), 2),
        'contract fee',
        false
    FROM {{ ref('budget_influencer_contracts') }} AS c
    CROSS JOIN LATERAL generate_series(c.contract_start_date, c.contract_end_date, interval '1 day') AS d
),

affiliate AS (
    SELECT order_date, 'affiliate', NULL::text,
           round(sum(merchandise_excl_vat) * {{ var('affiliate_commission_rate') }}, 2),
           'commission estimate', true
    FROM {{ ref('fct_orders') }}
    WHERE order_channel_key = 'affiliate' AND NOT is_cancelled
    GROUP BY order_date
)

SELECT * FROM google
UNION ALL SELECT * FROM meta
UNION ALL SELECT * FROM influencer
UNION ALL SELECT * FROM affiliate
