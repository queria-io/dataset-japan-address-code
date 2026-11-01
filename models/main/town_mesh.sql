-- 町字の形 (town_shape) と 3 次メッシュ (標準地域メッシュ、約 1km) の重なり。
-- 1 行が町字とメッシュの 1 組で、重なりの面積と、それぞれに占める割合を持つ。
-- 小字のうち大字・町の形を借りたもの (shape_method = parent_oaza) は入れない。
-- 同じ大字・町 (町字 ID の末尾 000) の行を使う
WITH town AS (
    SELECT lg_code, machiaza_id, geometry
    FROM {{ ref('town_shape') }}
    WHERE shape_method <> 'parent_oaza'
),
cell AS (
    SELECT s.lg_code, s.machiaza_id, s.geometry, r.y, c.x
    FROM town s,
        LATERAL (SELECT unnest(range(floor(ST_YMin(s.geometry) * 120)::BIGINT, floor(ST_YMax(s.geometry) * 120)::BIGINT + 1)) AS y) r,
        LATERAL (SELECT unnest(range(floor((ST_XMin(s.geometry) - 100) * 80)::BIGINT, floor((ST_XMax(s.geometry) - 100) * 80)::BIGINT + 1)) AS x) c
),
piece AS (
    SELECT
        lg_code,
        machiaza_id,
        y,
        x,
        -- 度の面積を、メッシュの中心の緯度で平方メートルに直す (1km 四方の中では十分)
        ST_Area(ST_Intersection(geometry, ST_MakeEnvelope(100 + x / 80, y / 120, 100 + (x + 1) / 80, (y + 1) / 120)))
            * 111320.0 * 111320.0 * cos(radians((y + 0.5) / 120)) AS area_m2
    FROM cell
)
SELECT
    lg_code,
    machiaza_id,
    -- 3 次メッシュコード: 1 次 (緯度 2 桁・経度 2 桁) + 2 次 (各 1 桁) + 3 次 (各 1 桁)
    lpad(CAST(y // 80 AS VARCHAR), 2, '0')
        || lpad(CAST(x // 80 AS VARCHAR), 2, '0')
        || CAST((y % 80) // 10 AS VARCHAR)
        || CAST((x % 80) // 10 AS VARCHAR)
        || CAST(y % 10 AS VARCHAR)
        || CAST(x % 10 AS VARCHAR) AS mesh_code,
    area_m2,
    area_m2 / sum(area_m2) OVER (PARTITION BY lg_code, machiaza_id) AS town_share,
    -- メッシュの面積は 111,320m × 111,320m × cos(緯度) / (80 × 120)
    area_m2 / (111320.0 * 111320.0 * cos(radians((y + 0.5) / 120)) / 9600) AS mesh_share
FROM piece
WHERE area_m2 > 0
ORDER BY lg_code, machiaza_id, mesh_code
