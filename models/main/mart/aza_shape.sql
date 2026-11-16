-- 法務省の地図の筆を大字・丁目・小字ごとに合わせた形
SELECT * FROM {{ ref('stg_aza_shape') }}
ORDER BY lg_code, oaza, chome, koaza
