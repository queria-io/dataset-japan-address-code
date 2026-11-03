{# 町字と郵便番号の町域の名前を突き合わせられる形にそろえる #}
{%- macro town_name_normalize(expr) -%}
{{ kanji_number("translate(regexp_replace(regexp_replace(" ~ expr ~ ", '大字', '', 'g'), '^字', ''), '曾峯澤瀧驒嶋萊篭龍狹檮鶯竈瀨辨蒄藪繫溪鷆のヶヵ', '曽峰沢滝騨島莱籠竜狭梼鴬竃瀬弁蔲薮繋渓鷏ノケカ')") }}
{%- endmacro %}
