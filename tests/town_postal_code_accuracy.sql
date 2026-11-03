-- 当て方ごとの正解率が下限を割ったら落とす。下限は 11/3 の実測 (name 99.9%、prefix 86%、sub 100%) から少し下
SELECT *
FROM ({{ postal_code_bench() }}) b
WHERE (match_type = 'name' AND accuracy < 0.995)
    OR (match_type = 'prefix' AND accuracy < 0.80)
    OR (match_type = 'sub' AND accuracy < 0.99)
