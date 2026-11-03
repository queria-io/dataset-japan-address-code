{{ config(materialized='ephemeral') }}
-- 町字と郵便番号の町域を名前で突き合わせる (町字マスタの郵便番号の有無によらず全町字)。
-- town_postal_code が使い、町字マスタに郵便番号がある町字は答え合わせ (tests/town_postal_code_accuracy.sql) に使う
{%- macro normalize(expr) -%}
{{ kanji_number("translate(regexp_replace(regexp_replace(" ~ expr ~ ", '大字', '', 'g'), '^字', ''), '曾峯澤瀧驒嶋萊篭龍狹檮鶯竈瀨辨蒄藪繫溪鷆のヶヵ', '曽峰沢滝騨島莱籠竜狭梼鴬竃瀬弁蔲薮繋渓鷏ノケカ')") }}
{%- endmacro %}
WITH town AS (
    SELECT lg_code, machiaza_id, any_value(oaza_cho) AS oaza_cho
    FROM address_br.main.mart_town
    GROUP BY lg_code, machiaza_id
),
named AS (
    SELECT lg_code, machiaza_id, {{ normalize('oaza_cho') }} AS name
    FROM town
),
zip AS (
    SELECT DISTINCT lg_code, zipcode, {{ normalize("regexp_replace(town, '（.*$', '')") }} AS name
    FROM zipcode.main.mart_zipcode
    WHERE town <> '以下に掲載がない場合' AND NOT regexp_matches(town, '（.*階.*）$')
),
exact AS (
    SELECT t.lg_code, t.machiaza_id, z.zipcode, 'name' AS match_type
    FROM named t
    JOIN zip z USING (lg_code, name)
),
prefix AS (
    SELECT t.lg_code, t.machiaza_id, z.zipcode, 'prefix' AS match_type
    FROM named t
    JOIN zip z ON z.lg_code = t.lg_code AND length(z.name) >= 2 AND starts_with(t.name, z.name)
    WHERE NOT EXISTS (SELECT 1 FROM exact e WHERE e.lg_code = t.lg_code AND e.machiaza_id = t.machiaza_id)
    QUALIFY rank() OVER (PARTITION BY t.lg_code, t.machiaza_id ORDER BY length(z.name) DESC) = 1
),
sub AS (
    SELECT t.lg_code, t.machiaza_id, any_value(z.zipcode) AS zipcode, 'sub' AS match_type
    FROM named t
    JOIN zip z ON z.lg_code = t.lg_code AND length(t.name) >= 2 AND starts_with(z.name, t.name)
    WHERE NOT EXISTS (SELECT 1 FROM exact e WHERE e.lg_code = t.lg_code AND e.machiaza_id = t.machiaza_id)
        AND NOT EXISTS (SELECT 1 FROM prefix e WHERE e.lg_code = t.lg_code AND e.machiaza_id = t.machiaza_id)
    GROUP BY t.lg_code, t.machiaza_id
    HAVING count(DISTINCT z.zipcode) = 1
)
SELECT * FROM exact
UNION ALL SELECT * FROM prefix
UNION ALL SELECT * FROM sub
