{# 市区町村の町・字（大字・町）の名前。管轄一覧表の「Xのうち」の後ろの項目が町・字かどうかを見る #}

select distinct lg_code, translate(oaza_cho, 'ヶヵ', 'ケカ') as name
from address_br.main.mart_town
where oaza_cho is not null
