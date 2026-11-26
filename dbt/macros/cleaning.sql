{#- Small, reusable cleaning rules. Each one points back to an issue in docs/02-profiling.md. -#}

{#- SH-06, SH-07, MC-03, X-02: one notation for an email address, used to match people across sources -#}
{% macro normalise_email(column) -%}
    nullif(lower(btrim({{ column }})), '')
{%- endmacro %}

{#- SH-11: one notation for a discount code -#}
{% macro normalise_code(column) -%}
    nullif(upper(btrim({{ column }})), '')
{%- endmacro %}

{#- Empty text -> NULL, after trimming -#}
{% macro clean_text(column) -%}
    nullif(btrim({{ column }}), '')
{%- endmacro %}

{#- AD-02: US number notation with thousands separators ('1,000.25') -> numeric -#}
{% macro us_number(column, type='numeric') -%}
    nullif(replace(btrim({{ column }}), ',', ''), '')::{{ type }}
{%- endmacro %}

{#-
    GA-02: a key that is the same for 'Prospecting - Lookalike 1% Buyers' and 'prospecting_lookalike_1_buyers',
    and for 'lena.sends' and 'lena_sends': lowercase, every run of other characters than letters, digits and '+' -> '_'.
-#}
{% macro name_key(column) -%}
    btrim(regexp_replace(lower(btrim({{ column }})), '[^a-z0-9+]+', '_', 'g'), '_')
{%- endmacro %}

{#-
    SH-10: placeholder and impossible birth dates -> NULL.
    Placeholder 01/01/1900, born after the account was created, or younger than 14 at sign-up.
-#}
{% macro clean_birth_date(birth_date, created_at) -%}
    (CASE
        WHEN {{ birth_date }} = DATE '1900-01-01' THEN NULL
        WHEN {{ birth_date }} > ({{ created_at }})::date THEN NULL
        WHEN age(({{ created_at }})::date, {{ birth_date }}) < interval '14 years' THEN NULL
        ELSE {{ birth_date }}
    END)
{%- endmacro %}

{#-
    SH-05: test accounts, recognised on their email address or their name.
    Emails like test+N@kalkberg.example and qa.kalkberg+N@gmail.com, or any address on a kalkberg domain;
    first names Test, QA, Test Klant; last name Account.
-#}
{% macro is_test_email(email) -%}
    coalesce(lower(btrim({{ email }})) ~ '^(test|qa\.kalkberg)\+[0-9]+@' OR lower(btrim({{ email }})) LIKE '%@kalkberg.%', false)
{%- endmacro %}

{% macro is_test_name(first_name, last_name) -%}
    coalesce(lower(btrim({{ first_name }})) IN ('test', 'qa', 'test klant') OR lower(btrim({{ last_name }})) = 'account', false)
{%- endmacro %}
