-- 町字の郵便番号。ABR の町字マスタにも郵便番号の列はあるが、ほとんどの町字で空なので、
-- 日本郵便の郵便番号データの町域と町字を名前で突き合わせる。1 つの町字に郵便番号が
-- 複数当たることがある (町域が丁目や番地で分かれている所)。作り方は match_type:
--   abr     ABR の町字マスタの郵便番号
--   name    町域の名前が大字・町の名前と同じ
--   prefix  町域の名前が大字・町の名前の頭と同じ (ABR の「里白石字小野久保」に郵便番号の「里白石」)。最も長いもの
--   sub     町域が大字・町より細かく分かれていて (「南田中西原」「南田中北原」…)、それが全部同じ郵便番号
--   city    当たる町域が無いので、市区町村の「以下に掲載がない場合」の郵便番号。村全体で 1 つ (「山形村一円」) ならそれ
-- 名前の突き合わせは town_postal_code_match。名前は「大字」と頭の「字」を外し、全角数字を漢数字に、異体字 (曾・峯・澤・瀧・驒 など) と「の」を片方にそろえる。
-- 町域の括弧書き (丁目・番地の範囲) は名前から外して比べる。ビルの階ごとの郵便番号は使わない
WITH town AS (
    SELECT lg_code, machiaza_id, replace(any_value(post_code) FILTER (WHERE post_code IS NOT NULL), '-', '') AS post_code
    FROM address_br.main.mart_town
    GROUP BY lg_code, machiaza_id
),
city AS (
    SELECT lg_code, coalesce(
        any_value(zipcode) FILTER (WHERE town = '以下に掲載がない場合'),
        CASE WHEN count(DISTINCT zipcode) = 1 THEN any_value(zipcode) END
    ) AS zipcode
    FROM zipcode.main.mart_zipcode
    GROUP BY lg_code
    HAVING zipcode IS NOT NULL
),
matched AS (
    SELECT lg_code, machiaza_id, post_code AS zipcode, 'abr' AS match_type
    FROM town
    WHERE post_code IS NOT NULL
    UNION ALL
    SELECT m.*
    FROM {{ ref('town_postal_code_match') }} m
    JOIN town t USING (lg_code, machiaza_id)
    WHERE t.post_code IS NULL
)
SELECT * FROM matched
UNION ALL
SELECT t.lg_code, t.machiaza_id, c.zipcode, 'city' AS match_type
FROM town t
JOIN city c USING (lg_code)
WHERE NOT EXISTS (SELECT 1 FROM matched m WHERE m.lg_code = t.lg_code AND m.machiaza_id = t.machiaza_id)
ORDER BY lg_code, machiaza_id, zipcode
