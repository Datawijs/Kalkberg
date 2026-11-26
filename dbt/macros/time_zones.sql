{#-
    Time zone helpers. Every source writes its timestamps differently (docs/02-profiling.md):
      - shop:  Belgian local time before the platform migration, UTC from the migration on (SH-02)
      - sfmc:  US notation, fixed UTC-6 all year round (MC-01, MC-02)
      - ga4:   microseconds since 1970 in UTC
    Silver stores every moment twice, both as timestamp without time zone:
      <name>_utc    the moment in UTC
      <name>_local  the same moment as Belgian clock time
    The conversions below never depend on the time zone of the database session.
-#}

{#- UTC clock time -> Belgian clock time -#}
{% macro utc_to_local(utc_timestamp) -%}
    (({{ utc_timestamp }}) AT TIME ZONE 'UTC' AT TIME ZONE '{{ var("local_time_zone") }}')
{%- endmacro %}

{#-
    SH-02: a raw shop timestamp -> UTC clock time. The old platform wrote Belgian local time, the new
    platform writes UTC. The platform is decided per record, not by the clock time: in the evening of
    01/09/2024 the two overlap (the new platform went live at midnight Belgian time, 22:00 UTC).
-#}
{% macro shop_timestamp_to_utc(raw_timestamp, is_old_platform) -%}
    (CASE
        WHEN {{ is_old_platform }}
            THEN ({{ raw_timestamp }}) AT TIME ZONE '{{ var("local_time_zone") }}' AT TIME ZONE 'UTC'
        ELSE {{ raw_timestamp }}
    END)
{%- endmacro %}

{#-
    MC-01: read a Marketing Cloud timestamp written as 'M/D/YYYY h:mm:ss AM' exactly as written.
    The date and the time are parsed separately, so the session time zone plays no role.
-#}
{% macro sfmc_parse_timestamp(raw_text) -%}
    (CASE
        WHEN nullif(btrim({{ raw_text }}), '') IS NOT NULL
            THEN to_date(split_part(btrim({{ raw_text }}), ' ', 1), 'MM/DD/YYYY')
               + (split_part(btrim({{ raw_text }}), ' ', 2) || ' ' || split_part(btrim({{ raw_text }}), ' ', 3))::time
    END)
{%- endmacro %}

{#- MC-02: Marketing Cloud writes fixed UTC-6, so add 6 hours to get UTC -#}
{% macro sfmc_timestamp_to_utc(raw_text) -%}
    ({{ sfmc_parse_timestamp(raw_text) }} + interval '6 hours')
{%- endmacro %}

{#- GA4: event_timestamp in microseconds since 1970 (UTC) -> UTC clock time -#}
{% macro ga4_micros_to_utc(raw_text) -%}
    (to_timestamp({{ raw_text }}::bigint / 1000000.0) AT TIME ZONE 'UTC')
{%- endmacro %}

{#- Shorthand: the _utc and _local columns of a Marketing Cloud timestamp -#}
{% macro sfmc_timestamp_columns(raw_text, name) -%}
    {{ sfmc_timestamp_to_utc(raw_text) }} AS {{ name }}_utc,
    {{ utc_to_local(sfmc_timestamp_to_utc(raw_text)) }} AS {{ name }}_local
{%- endmacro %}
