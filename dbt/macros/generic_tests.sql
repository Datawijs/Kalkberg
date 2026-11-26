{#- Generic tests used in the schema files. -#}

{#- Fails for every combination of the given columns that occurs more than once. -#}
{% test unique_combination_of_columns(model, combination_of_columns) %}
    SELECT {{ combination_of_columns | join(', ') }}, count(*) AS occurrences
    FROM {{ model }}
    GROUP BY {{ combination_of_columns | join(', ') }}
    HAVING count(*) > 1
{% endtest %}

{#- Fails for every row where the expression is not true. -#}
{% test expression_is_true(model, expression, column_name=none) %}
    SELECT *
    FROM {{ model }}
    WHERE NOT coalesce(({{ expression }}), false)
{% endtest %}
