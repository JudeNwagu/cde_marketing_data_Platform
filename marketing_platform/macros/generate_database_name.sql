{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {#- Only production sends each layer to its own catalog.
        Dev and CI build everything in the catalog set in the profile. -#}
    {%- if target.name == 'prod' and custom_database_name is not none -%}
        {{ custom_database_name | trim }}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}
