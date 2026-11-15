{# 不動産取引価格（reinfolib.main.mart_trade_prices）の地区。取引は位置を地区名（大字・町）までしか持たない。
   municipality_code は取引の値のまま（北海道などは先頭の 0 が落ちた 4 桁） #}

select distinct
    municipality_code,
    lpad(municipality_code, 5, '0') as city_code,
    district_name,
    {{ oaza_name_normalize("district_name") }} as name
from reinfolib.main.mart_trade_prices
where coalesce(district_name, '') not in ('', '（大字なし）')
