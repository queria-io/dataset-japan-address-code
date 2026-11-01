-- 法務省の地図の筆を大字・丁目・小字ごとに合わせた形。main.py (pipelines/aza.py) が data/aza に書く
SELECT lg_code, oaza, chome, koaza, parcels, ST_GeomFromWKB(geometry) AS geometry, moj_version
FROM read_parquet('data/aza/*.parquet')
ORDER BY lg_code, oaza, chome, koaza
