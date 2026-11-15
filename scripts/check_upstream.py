"""公開中の japan_address_code を作ったあとに、元のデータセットが新しくなったかを見る。

全国のビルドは GitHub のランナーのメモリに収まらないので手元で流す。ここは確かめるだけで、
新しくなった元のデータセットの名前を 1 行ずつ出す（何も出なければ作り直さなくてよい）。
e_stat の小地域の形は国勢調査ごと（5 年に 1 回）にしか変わらないので見ない。
geospatial はほかのスキーマの更新でもバージョンが進むので、chizu のデータの目印を、公開中の
aza_shape が元にした目印（moj_version 列）と比べる（pipelines/aza.py と同じ目印）。
reinfolib と mhlw はほかの表の更新でもバージョンが進むので、読む表の中身を公開中の表と比べる。
取引の地区が trade_district_small_area に無いとき、管轄一覧表の項目が hellowork_city の元と変わったときに出す。
"""

import os

import duckdb

DATASET = "japan_address_code"
UPSTREAM = ("address_br", "zipcode")
CHIZU_VERSION = """
SELECT 'chizu:' || md5(string_agg(f.path, ',' ORDER BY f.path))
FROM __ducklake_metadata_geospatial.ducklake_data_file AS f
JOIN __ducklake_metadata_geospatial.ducklake_table AS t USING (table_id)
JOIN __ducklake_metadata_geospatial.ducklake_schema AS s USING (schema_id)
WHERE s.schema_name = 'chizu'
    AND s.end_snapshot IS NULL AND t.end_snapshot IS NULL AND f.end_snapshot IS NULL
"""

# 取引の地区は当たらなくても 1 行になるので、行の無い地区は新しい地区
NEW_TRADE_DISTRICTS = f"""
SELECT count(*) FROM (
    SELECT DISTINCT municipality_code, district_name
    FROM reinfolib.main.mart_trade_prices
    WHERE coalesce(district_name, '') NOT IN ('', '（大字なし）')
    EXCEPT
    SELECT municipality_code, district_name FROM {DATASET}.main.trade_district_small_area
)
"""
# 当てた項目が管轄一覧表から消えるか変わると、項目の順（item_order）もずれる
CHANGED_JURISDICTION = f"""
SELECT count(*) FROM (
    SELECT prefecture_code, office_name, office_kind, item_order, area_text
    FROM {DATASET}.main.hellowork_city
    EXCEPT
    SELECT prefecture_code, office_name, office_kind, item_order, area_text
    FROM mhlw.hellowork.jurisdiction_area
)
"""


def changed(c: duckdb.DuckDBPyConnection, sql: str) -> bool:
    # 公開中のデータセットに比べる表がまだ無いときも作り直しが要る。例外で止めると、
    # 先に見つけた address_br などの名前も出せないまま終わる
    try:
        return bool(c.execute(sql).fetchone()[0])
    except duckdb.CatalogException:
        return True


def latest(c: duckdb.DuckDBPyConnection, name: str):
    c.execute(f"ATTACH 'ducklake:https://data.queria.io/datasets/queria/{name}/metadata.db' AS {name} (READ_ONLY)")
    return c.execute(f"SELECT epoch_us(max(snapshot_time)) FROM ducklake_snapshots('{name}')").fetchone()[0]


def main() -> None:
    c = duckdb.connect(config={"custom_user_agent": os.environ.get("QUERIA_USER_AGENT", "queria-build/check")})
    c.execute("INSTALL ducklake; LOAD ducklake; INSTALL httpfs; LOAD httpfs")
    built = latest(c, DATASET)
    stale = [name for name in UPSTREAM if latest(c, name) > built]
    latest(c, "geospatial")
    built_from = c.execute(f"SELECT DISTINCT moj_version FROM {DATASET}.main.aza_shape").fetchall()
    if built_from != [c.execute(CHIZU_VERSION).fetchone()]:
        stale.append("geospatial")
    latest(c, "reinfolib")
    if changed(c, NEW_TRADE_DISTRICTS):
        stale.append("reinfolib")
    latest(c, "mhlw")
    if changed(c, CHANGED_JURISDICTION):
        stale.append("mhlw")
    print("\n".join(stale))


if __name__ == "__main__":
    main()
