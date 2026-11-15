{# 不動産取引価格（reinfolib.main.mart_trade_prices）の地区と国勢調査の小地域の対応。
   地区名をアドレス・ベース・レジストリの大字・町の名前に当て、その町字を town_small_area で小地域に結合する。
   取引には (municipality_code, district_name) で結合する #}

with district as (
    select * from {{ ref('stg_reinfolib__trade_districts') }}
),

oaza as (
    select * from {{ ref('stg_address_br__oaza') }}
),

matched as (
    select d.municipality_code, d.district_name, o.lg_code, o.oaza_id, o.machiaza_id
    from district d
    join oaza o on o.city_code = d.city_code and o.name = d.name
    -- 正規化すると空になる地区名（「一丁目」だけなど）は当てない
    where d.name <> ''
),

-- 同じ市区町村に同じ名前の大字・町が複数あるときは oaza_count に数を出す
oaza_count as (
    select municipality_code, district_name, count(distinct oaza_id) as oaza_count
    from matched
    group by all
),

small_area as (
    select distinct m.municipality_code, m.district_name, m.lg_code, s.key_code
    from matched m
    join {{ ref('town_small_area') }} s using (lg_code, machiaza_id)
    where s.key_code is not null
)

select
    d.municipality_code,
    d.district_name,
    s.lg_code,
    s.key_code,
    left(s.key_code, 9) as town_code,
    coalesce(c.oaza_count, 0) as oaza_count
from district d
left join small_area s using (municipality_code, district_name)
left join oaza_count c using (municipality_code, district_name)
order by d.municipality_code, d.district_name, s.key_code
