{#- Countries. Kalkberg only ships to the five with is_shipping_country = true (GA-04). -#}
SELECT
    country_code,
    country_name,
    is_shipping_country
FROM {{ ref('countries') }}
