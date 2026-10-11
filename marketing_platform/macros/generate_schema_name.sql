{% macro generate_schema_name(custom_schema_name, node) -%}
    {#- Only production uses the schema named in dbt_project.yml.
        Dev and CI use the schema set in the profile (your own or the PR schema). -#}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
