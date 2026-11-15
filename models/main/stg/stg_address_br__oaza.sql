{# アドレス・ベース・レジストリの大字・町。廃止（status_flg = 3）の町字は除く #}

select
    left(lg_code, 5) as city_code,
    lg_code,
    machiaza_id,
    {{ oaza_name_normalize("oaza_cho") }} as name,
    left(machiaza_id, 4) as oaza_id
from address_br.main.mart_town
where oaza_cho is not null
  and status_flg <> '3'
