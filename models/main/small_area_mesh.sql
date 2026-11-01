-- 国勢調査の小地域 (令和2年) と 3 次メッシュ (標準地域メッシュ、約 1km) の重なり。
-- 1 行が小地域とメッシュの 1 組で、重なりの面積と、それぞれに占める割合を持つ。
-- メッシュは緯度 30 秒 × 経度 45 秒。小地域の外接矩形にかかるメッシュを作って形と重ねる
WITH small_area AS (
    SELECT CAST(key_code AS VARCHAR) AS key_code, geometry
    FROM e_stat.boundary.small_area
),
cell AS (
    SELECT s.key_code, s.geometry, r.y, c.x
    FROM small_area s,
        LATERAL (SELECT unnest(range(floor(ST_YMin(s.geometry) * 120)::BIGINT, floor(ST_YMax(s.geometry) * 120)::BIGINT + 1)) AS y) r,
        LATERAL (SELECT unnest(range(floor((ST_XMin(s.geometry) - 100) * 80)::BIGINT, floor((ST_XMax(s.geometry) - 100) * 80)::BIGINT + 1)) AS x) c
),
piece AS (
    SELECT
        key_code,
        y,
        x,
        -- 度の面積を、メッシュの中心の緯度で平方メートルに直す (1km 四方の中では十分)
        ST_Area(ST_Intersection(geometry, ST_MakeEnvelope(100 + x / 80, y / 120, 100 + (x + 1) / 80, (y + 1) / 120)))
            * 111320.0 * 111320.0 * cos(radians((y + 0.5) / 120)) AS area_m2
    FROM cell
)
SELECT
    key_code,
    -- 3 次メッシュコード: 1 次 (緯度 2 桁・経度 2 桁) + 2 次 (各 1 桁) + 3 次 (各 1 桁)
    lpad(CAST(y // 80 AS VARCHAR), 2, '0')
        || lpad(CAST(x // 80 AS VARCHAR), 2, '0')
        || CAST((y % 80) // 10 AS VARCHAR)
        || CAST((x % 80) // 10 AS VARCHAR)
        || CAST(y % 10 AS VARCHAR)
        || CAST(x % 10 AS VARCHAR) AS mesh_code,
    area_m2,
    area_m2 / sum(area_m2) OVER (PARTITION BY key_code) AS small_area_share,
    -- メッシュの面積は 111,320m × 111,320m × cos(緯度) / (80 × 120)
    area_m2 / (111320.0 * 111320.0 * cos(radians((y + 0.5) / 120)) / 9600) AS mesh_share
FROM piece
WHERE area_m2 > 0
ORDER BY key_code, mesh_code
