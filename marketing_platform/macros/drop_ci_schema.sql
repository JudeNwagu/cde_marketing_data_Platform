{% macro drop_ci_schema() %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schema may only run against the ci target") }}
    {% endif %}
    {% do run_query("drop schema if exists " ~ target.database ~ "." ~ target.schema ~ " cascade") %}
    {{ log("Dropped schema " ~ target.database ~ "." ~ target.schema, info=True) }}
{% endmacro %}
