-- 町字と国勢調査の小地域 (令和2年) の対応。1 行が町字と小地域の 1 組。
-- 同じ市区町村の中で名前が一致する小地域に当て、当たらない町字は代表点が入る小地域に当てる
WITH town AS (
    -- 一部だけ住居表示の町字は同じ町字 ID に 2 行あるので 1 行にまとめる
    SELECT
        lg_code,
        machiaza_id,
        any_value(efct_date) AS efct_date,
        any_value({{ kanji_number("oaza_cho || coalesce(chome, '') || coalesce(koaza, '')") }}) AS name,
        any_value(geometry) AS geometry
    FROM address_br.main.mart_town
    GROUP BY lg_code, machiaza_id
),
-- 代表点の無い小字は、同じ大字・町 (町字 ID の末尾 000) の代表点を使う
located AS (
    SELECT t.*, coalesce(t.geometry, p.geometry) AS point
    FROM town t
    LEFT JOIN town p
        ON p.lg_code = t.lg_code
        AND p.machiaza_id = left(t.machiaza_id, 4) || '000'
        AND t.geometry IS NULL
),
small_area AS (
    SELECT
        CAST(key_code AS VARCHAR) AS key_code,
        prefecture_code || city_code AS city_code,
        area_name AS name,
        geometry
    FROM e_stat.boundary.small_area
),
by_name AS (
    SELECT t.lg_code, t.machiaza_id, s.key_code, 'name' AS method,
        t.point IS NOT NULL AND NOT ST_Contains(s.geometry, t.point) AS point_mismatch
    FROM located t
    JOIN small_area s ON s.city_code = left(t.lg_code, 5) AND s.name = t.name
),
by_point AS (
    SELECT t.lg_code, t.machiaza_id, s.key_code, 'point' AS method, false AS point_mismatch
    FROM located t
    JOIN small_area s ON ST_Contains(s.geometry, t.point)
    WHERE NOT EXISTS (
        SELECT 1 FROM by_name n WHERE n.lg_code = t.lg_code AND n.machiaza_id = t.machiaza_id
    )
    -- 境界が重なる場所では代表点が 2 つの小地域に入る。1 つだけ残す
    QUALIFY row_number() OVER (PARTITION BY t.lg_code, t.machiaza_id ORDER BY s.key_code) = 1
),
pairs AS (
    SELECT *,
        count(*) OVER (PARTITION BY lg_code, machiaza_id) AS small_areas_of_town,
        count(*) OVER (PARTITION BY key_code) AS towns_of_small_area
    FROM (SELECT * FROM by_name UNION ALL SELECT * FROM by_point)
)
SELECT
    t.lg_code,
    t.machiaza_id,
    p.key_code,
    CASE
        WHEN p.key_code IS NULL THEN NULL
        WHEN p.small_areas_of_town = 1 AND p.towns_of_small_area = 1 THEN 'one_to_one'
        WHEN p.towns_of_small_area = 1 THEN 'town_split'
        WHEN p.small_areas_of_town = 1 THEN 'towns_merged'
        ELSE 'many_to_many'
    END AS match_type,
    -- 町字の形ができるまでは、1 つの小地域にだけ当たる町字の 1 しか出せない
    CASE WHEN p.small_areas_of_town = 1 THEN 1.0 END AS town_share,
    CASE WHEN p.towns_of_small_area = 1 AND p.small_areas_of_town = 1 THEN 1.0 END AS small_area_share,
    p.method,
    p.point_mismatch,
    2020 AS small_area_year,
    t.efct_date AS valid_from
FROM located t
LEFT JOIN pairs p USING (lg_code, machiaza_id)
ORDER BY t.lg_code, t.machiaza_id, p.key_code
