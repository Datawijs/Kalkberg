{#-
    Influencer contracts from the budget workbook (decision 0003).
    Typed, codes normalised (SH-11), and the rule from the Remarks column made explicit:
    a code stays valid 14 days after the contract ends (confirmed by profiling check shop_17).
-#}
SELECT
    btrim(creator)                                   AS creator,
    {{ name_key('creator') }}                        AS creator_key,
    btrim(platform)                                  AS platform,
    {{ normalise_code('discount_code') }}            AS discount_code,
    btrim(start_date)::date                          AS contract_start_date,
    btrim(end_date)::date                            AS contract_end_date,
    btrim(end_date)::date + {{ var('influencer_code_grace_days') }} AS code_valid_until,
    nullif(btrim(monthly_fee_eur), '')::numeric(10, 2) AS monthly_fee_eur,
    {{ clean_text('remarks') }}                      AS remarks,
    _source_file                                     AS source_file,
    _row_number                                      AS source_row_number,
    _loaded_at                                       AS loaded_at
FROM {{ source('budget', 'influencer_contracts') }}
