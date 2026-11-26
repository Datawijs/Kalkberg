{#- Gold helpers. -#}

{#- The key of dim_campaign: '<channel_key> | <campaign name>', NULL when there is no campaign -#}
{% macro campaign_key(channel_key, campaign_name) -%}
    (CASE WHEN {{ campaign_name }} IS NOT NULL THEN {{ channel_key }} || ' | ' || {{ campaign_name }} END)
{%- endmacro %}

{#- An amount incl. VAT -> excl. VAT -#}
{% macro excl_vat(amount, vat_rate) -%}
    round(({{ amount }}) / (1 + {{ vat_rate }}), 2)
{%- endmacro %}
