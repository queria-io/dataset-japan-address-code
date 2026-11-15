-- raw_aza_shape の形 (WKB) を GEOMETRY にする
SELECT lg_code, oaza, chome, koaza, parcels, ST_GeomFromWKB(geometry) AS geometry, moj_version
FROM {{ ref('raw_aza_shape') }}
