-- 町字の形。公式の町字ポリゴンは無いので、国勢調査の小地域 (令和2年) の形から作る。
-- 小地域ごとに、そこへ当たる町字を「持ち主」にする:
--   持ち主が 1 つ  小地域の形をそのまま持ち主に渡す
--   持ち主が複数   代表点 (住居表示の町字は小地域の中の街区の代表点) のボロノイ図で小地域を切り分ける
-- 持ち主は小字でない町字と、名前で当たった小字。点だけで当たった小字は、その小地域に
-- ほかの持ち主がいないときに限り、同じ大字・町 (町字 ID の末尾 000) を持ち主にする。
-- 形の無い小字には、同じ大字・町の形を渡す。作り方は shape_method:
--   small_area  小地域の形をそのまま (複数なら合わせた形)
--   voronoi     少なくとも 1 つの小地域を点で切り分けた
--   parent_oaza 小字。同じ大字・町の形
WITH town AS (
    SELECT
        lg_code,
        machiaza_id,
        bool_or(koaza IS NOT NULL) AS is_koaza,
        bool_or(rsdt_addr_flg = '1') AS is_rsdt,
        any_value(geometry) FILTER (WHERE geometry IS NOT NULL) AS point
    FROM address_br.main.mart_town
    GROUP BY lg_code, machiaza_id
),
small_area AS (
    SELECT CAST(key_code AS VARCHAR) AS key_code, geometry
    FROM e_stat.boundary.small_area
),
pair AS (
    SELECT p.lg_code, p.machiaza_id, p.key_code, t.is_koaza AND p.method = 'point' AS folds
    FROM {{ ref('town_small_area') }} p
    JOIN town t USING (lg_code, machiaza_id)
    WHERE p.key_code IS NOT NULL
),
-- 持ち主 (owner_*) と、その点を出す町字 (lg_code, machiaza_id)
member AS (
    SELECT lg_code AS owner_lg, machiaza_id AS owner_id, key_code, lg_code, machiaza_id
    FROM pair
    WHERE NOT folds
    UNION ALL
    SELECT p.lg_code, left(p.machiaza_id, 4) || '000', p.key_code, p.lg_code, p.machiaza_id
    FROM pair p
    JOIN town o ON o.lg_code = p.lg_code AND o.machiaza_id = left(p.machiaza_id, 4) || '000' AND NOT o.is_koaza
    WHERE p.folds AND NOT EXISTS (SELECT 1 FROM pair x WHERE x.key_code = p.key_code AND NOT x.folds)
),
owners AS (
    SELECT key_code, count(DISTINCT (owner_lg, owner_id)) AS n
    FROM member
    GROUP BY key_code
),
whole AS (
    SELECT DISTINCT m.owner_lg, m.owner_id, s.geometry, false AS split
    FROM member m
    JOIN owners o USING (key_code)
    JOIN small_area s USING (key_code)
    WHERE o.n = 1
),
shared AS (
    SELECT m.*, s.geometry AS area
    FROM member m
    JOIN owners o USING (key_code)
    JOIN small_area s USING (key_code)
    WHERE o.n > 1
),
block_point AS (
    SELECT m.owner_lg, m.owner_id, m.key_code, b.geometry AS point
    FROM shared m
    JOIN town t USING (lg_code, machiaza_id)
    JOIN address_br.main.mart_rsdtdsp_blk b USING (lg_code, machiaza_id)
    WHERE t.is_rsdt AND b.geometry IS NOT NULL AND ST_Contains(m.area, b.geometry)
),
-- 小地域の中に街区の点が無い町字は、町字の代表点を使う
generator AS (
    SELECT *
    FROM (
        SELECT * FROM block_point
        UNION ALL
        SELECT m.owner_lg, m.owner_id, m.key_code, t.point
        FROM shared m
        JOIN town t USING (lg_code, machiaza_id)
        WHERE t.point IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM block_point b
                WHERE b.key_code = m.key_code AND b.owner_lg = m.owner_lg AND b.owner_id = m.owner_id
            )
    )
    -- 同じ位置の点が持ち主をまたぐと、切り分けた形が重なる。1 つだけ残す
    QUALIFY row_number() OVER (PARTITION BY key_code, ST_AsWKB(point) ORDER BY owner_lg, owner_id) = 1
),
-- ボロノイ図の外周は点の範囲で決まるので、遠い点を 4 つ足して小地域を覆う。
-- 町字の代表点は小地域の外にもあるので、小地域と点を合わせた外接矩形 (一辺 d 以下) から 3d 離す。
-- 矩形の中ではどの点からも √2·d 以内、足した点からは 3√2·d 以上なので、足した点は小地域の中を取らない
frame AS (
    SELECT key_code, area, points, x0 - 3 * d AS x0, y0 - 3 * d AS y0, x1 + 3 * d AS x1, y1 + 3 * d AS y1
    FROM (
        SELECT *, greatest(x1 - x0, y1 - y0) AS d
        FROM (
            SELECT
                g.key_code,
                s.geometry AS area,
                g.points,
                least(ST_XMin(s.geometry), g.px0) AS x0,
                least(ST_YMin(s.geometry), g.py0) AS y0,
                greatest(ST_XMax(s.geometry), g.px1) AS x1,
                greatest(ST_YMax(s.geometry), g.py1) AS y1
            FROM (
                SELECT
                    key_code,
                    list(point) AS points,
                    min(ST_X(point)) AS px0,
                    min(ST_Y(point)) AS py0,
                    max(ST_X(point)) AS px1,
                    max(ST_Y(point)) AS py1
                FROM generator
                GROUP BY key_code
            ) g
            JOIN small_area s USING (key_code)
        )
    )
),
diagram AS (
    SELECT key_code, area, unnest(ST_Dump(ST_VoronoiDiagram(ST_Collect(
        points || [ST_Point(x0, y0), ST_Point(x1, y0), ST_Point(x0, y1), ST_Point(x1, y1)]
    ))), recursive := true)
    FROM frame
),
cut AS (
    SELECT g.owner_lg, g.owner_id, ST_Intersection(d.geom, d.area) AS geometry, true AS split
    FROM diagram d
    JOIN generator g ON g.key_code = d.key_code AND ST_Contains(d.geom, g.point)
),
own AS (
    SELECT
        owner_lg AS lg_code,
        owner_id AS machiaza_id,
        ST_Union_Agg(geometry) AS geometry,
        CASE WHEN bool_or(split) THEN 'voronoi' ELSE 'small_area' END AS shape_method
    FROM (SELECT * FROM whole UNION ALL SELECT * FROM cut)
    WHERE NOT ST_IsEmpty(geometry)
    GROUP BY owner_lg, owner_id
),
koaza AS (
    SELECT t.lg_code, t.machiaza_id, o.geometry, 'parent_oaza' AS shape_method
    FROM town t
    JOIN own o ON o.lg_code = t.lg_code AND o.machiaza_id = left(t.machiaza_id, 4) || '000'
    WHERE t.is_koaza
        AND NOT EXISTS (SELECT 1 FROM own x WHERE x.lg_code = t.lg_code AND x.machiaza_id = t.machiaza_id)
)
SELECT * FROM own
UNION ALL
SELECT * FROM koaza
ORDER BY lg_code, machiaza_id
