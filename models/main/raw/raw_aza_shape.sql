-- 法務省の地図の筆を大字・丁目・小字ごとに合わせた形。main.py (pipelines/aza.py) が data/aza に書いた Parquet をそのまま読む（形は WKB）
SELECT * FROM read_parquet('data/aza/*.parquet')
