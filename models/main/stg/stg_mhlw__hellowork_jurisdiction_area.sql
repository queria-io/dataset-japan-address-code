{# 公共職業安定所（ハローワーク）の管轄一覧表の項目（mhlw.hellowork.jurisdiction_area） #}

select prefecture_code, prefecture_name, office_name, office_kind, item_order, area_text
from mhlw.hellowork.jurisdiction_area
