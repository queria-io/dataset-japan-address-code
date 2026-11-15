{# アドレス・ベース・レジストリの市区町村。管轄一覧表の名前と比較するため「ヶ」「ヵ」を「ケ」「カ」にした名前を持つ #}

select
    lg_code,
    pref_name,
    county_name,
    city_name,
    ward_name,
    translate(city_name, 'ヶヵ', 'ケカ') as city_key,
    translate(coalesce(ward_name, ''), 'ヶヵ', 'ケカ') as ward_key,
    translate(coalesce(county_name, ''), 'ヶヵ', 'ケカ') as county_key,
    bool_or(ward_name is not null) over (partition by pref_name, city_name) as in_designated_city
from address_br.main.mart_city
where lg_code is not null
