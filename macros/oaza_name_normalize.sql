{# 不動産取引の地区名と大字・町の名前を突き合わせられる形にそろえる:
   「ヶ」と「ケ」、頭の「大字」「字」、末尾の「一丁目」「1丁」 #}
{% macro oaza_name_normalize(col) -%}
regexp_replace(
    regexp_replace(
        translate({{ col }}, 'ヶｹ', 'ケケ'),
        '^(大字|字)', ''
    ),
    '[０-９0-9一二三四五六七八九十]+丁目?$', ''
)
{%- endmacro %}
