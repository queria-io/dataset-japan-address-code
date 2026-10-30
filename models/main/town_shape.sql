-- 町字の形。公式の町字ポリゴンは無いので作る。作り方は shape_method:
--   small_area  名前で 1 対 1 に当たる国勢調査の小地域 (令和2年) の形
--   parent_oaza 小字。同じ大字・町 (町字 ID の末尾 000) の形
-- 小地域に町字が複数入る所 (点で切り分ける) と地番の地域 (登記所備付地図) はまだ作らない
WITH own AS (
    SELECT p.lg_code, p.machiaza_id, s.geometry, 'small_area' AS shape_method
    FROM {{ ref('town_small_area') }} p
    JOIN e_stat.boundary.small_area s ON CAST(s.key_code AS VARCHAR) = p.key_code
    WHERE p.match_type = 'one_to_one' AND p.method = 'name'
),
koaza AS (
    SELECT DISTINCT t.lg_code, t.machiaza_id, o.geometry, 'parent_oaza' AS shape_method
    FROM address_br.main.mart_town t
    JOIN own o
        ON o.lg_code = t.lg_code
        AND o.machiaza_id = left(t.machiaza_id, 4) || '000'
    WHERE t.koaza IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM own x WHERE x.lg_code = t.lg_code AND x.machiaza_id = t.machiaza_id
        )
)
SELECT * FROM own
UNION ALL
SELECT * FROM koaza
ORDER BY lg_code, machiaza_id
