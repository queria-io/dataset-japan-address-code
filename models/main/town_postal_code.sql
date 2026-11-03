-- 町字の郵便番号。ABR の町字マスタにも郵便番号の列はあるが、ほとんどの町字で空なので、
-- 日本郵便の郵便番号データの町域と町字を名前で突き合わせる。1 つの町字に郵便番号が
-- 複数当たることがある (町域が丁目や番地で分かれている所)。作り方は match_type:
--   abr     ABR の町字マスタの郵便番号
--   name    町域の名前が大字・町の名前と同じ
--   prefix  町域の名前が大字・町の名前の頭と同じ (ABR の「里白石字小野久保」に郵便番号の「里白石」)。最も長いもの
--   city    当たる町域が無いので、市区町村の「以下に掲載がない場合」の郵便番号
-- 町域の括弧書き (丁目・番地の範囲) は名前から外して比べる。ビルの階ごとの郵便番号は使わない
{%- macro normalize(expr) -%}
{{ kanji_number("translate(regexp_replace(regexp_replace(" ~ expr ~ ", '大字', '', 'g'), '^字', ''), 'ヶヵ', 'ケカ')") }}
{%- endmacro %}
WITH town AS (
    SELECT lg_code, machiaza_id, any_value(oaza_cho) AS oaza_cho, any_value(post_code) FILTER (WHERE post_code IS NOT NULL) AS post_code
    FROM address_br.main.mart_town
    GROUP BY lg_code, machiaza_id
),
named AS (
    SELECT *, {{ normalize('oaza_cho') }} AS name
    FROM town
),
zip AS (
    SELECT DISTINCT lg_code, zipcode, {{ normalize("regexp_replace(town, '（.*$', '')") }} AS name
    FROM zipcode.main.mart_zipcode
    WHERE town <> '以下に掲載がない場合' AND NOT regexp_matches(town, '（.*階.*）$')
),
city AS (
    SELECT lg_code, any_value(zipcode) AS zipcode
    FROM zipcode.main.mart_zipcode
    WHERE town = '以下に掲載がない場合'
    GROUP BY lg_code
),
abr AS (
    SELECT lg_code, machiaza_id, replace(post_code, '-', '') AS zipcode, 'abr' AS match_type
    FROM town
    WHERE post_code IS NOT NULL
),
exact AS (
    SELECT t.lg_code, t.machiaza_id, z.zipcode, 'name' AS match_type
    FROM named t
    JOIN zip z USING (lg_code, name)
    WHERE t.post_code IS NULL
),
prefix AS (
    SELECT t.lg_code, t.machiaza_id, z.zipcode, 'prefix' AS match_type
    FROM named t
    JOIN zip z ON z.lg_code = t.lg_code AND length(z.name) >= 2 AND starts_with(t.name, z.name)
    WHERE t.post_code IS NULL
        AND NOT EXISTS (SELECT 1 FROM exact e WHERE e.lg_code = t.lg_code AND e.machiaza_id = t.machiaza_id)
    QUALIFY rank() OVER (PARTITION BY t.lg_code, t.machiaza_id ORDER BY length(z.name) DESC) = 1
),
matched AS (
    SELECT * FROM abr
    UNION ALL SELECT * FROM exact
    UNION ALL SELECT * FROM prefix
)
SELECT * FROM matched
UNION ALL
SELECT t.lg_code, t.machiaza_id, c.zipcode, 'city' AS match_type
FROM town t
JOIN city c USING (lg_code)
WHERE NOT EXISTS (SELECT 1 FROM matched m WHERE m.lg_code = t.lg_code AND m.machiaza_id = t.machiaza_id)
ORDER BY lg_code, machiaza_id, zipcode
