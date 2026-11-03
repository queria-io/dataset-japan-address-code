-- 郵便番号の無い町字と、市区町村全体の郵便番号 (city) に落ちる町字が 5% を超えたら落とす
WITH town AS (
    SELECT DISTINCT lg_code, machiaza_id FROM address_br.main.mart_town
),
p AS (
    SELECT lg_code, machiaza_id, bool_and(match_type = 'city') AS city
    FROM {{ ref('town_postal_code') }}
    GROUP BY lg_code, machiaza_id
)
SELECT count(*) FILTER (WHERE p.lg_code IS NULL) AS missing,
    count(*) FILTER (WHERE p.city) / count(*) AS city_share
FROM town t
LEFT JOIN p USING (lg_code, machiaza_id)
HAVING missing > 0 OR city_share > 0.05
