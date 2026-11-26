{#-
    Use the schema name from the configuration as-is (silver, gold) instead of dbt's default
    "<target schema>_<custom schema>". The layers are fixed schemas in this project, see docs/03-silver.md.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
