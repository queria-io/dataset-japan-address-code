{#
  郵便番号の当て方の答え合わせ。町字マスタに郵便番号がある町字で、名前の突き合わせ
  (town_postal_code_match) の答えにその郵便番号が入るかを当て方ごとに数える。
  名前で当たらない町字は city (市区町村全体の郵便番号) として数える
#}
{% macro postal_code_bench() %}
WITH truth AS (
    -- 町字マスタの郵便番号は ; で複数並ぶことがある。どれかが当たれば正解
    SELECT DISTINCT lg_code, machiaza_id, replace(trim(unnest(string_split(post_code, ';'))), '-', '') AS zipcode
    FROM address_br.main.mart_town
    WHERE post_code IS NOT NULL
),
judged AS (
    SELECT t.lg_code, t.machiaza_id,
        coalesce(any_value(m.match_type), 'city') AS match_type,
        coalesce(bool_or(m.zipcode = t.zipcode), false) AS ok
    FROM truth t
    LEFT JOIN {{ ref('town_postal_code_match') }} m USING (lg_code, machiaza_id)
    GROUP BY t.lg_code, t.machiaza_id
)
SELECT match_type, count(*) AS towns, count(*) FILTER (WHERE ok) AS correct,
    round(count(*) FILTER (WHERE ok) / count(*), 4) AS accuracy
FROM judged
GROUP BY match_type
{% endmacro %}
