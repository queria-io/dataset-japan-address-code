"""公開中の japan_address_code を作ったあとに、元のデータセットが新しくなったかを見る。

全国のビルドは GitHub のランナーのメモリに収まらないので手元で流す。ここは確かめるだけで、
新しくなった元のデータセットの名前を 1 行ずつ出す（何も出なければ作り直さなくてよい）。
e_stat の小地域の形は国勢調査ごと（5 年に 1 回）にしか変わらないので見ない。
geospatial はほかのスキーマの更新でもバージョンが進むので、chizu のデータの目印を、公開中の
aza_shape が元にした目印（moj_version 列）と比べる（pipelines/aza.py と同じ目印）。
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


def latest(c: duckdb.DuckDBPyConnection, name: str):
    c.execute(f"ATTACH 'ducklake:https://data.queria.io/datasets/queria/{name}/ducklake.duckdb' AS {name} (READ_ONLY)")
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
    print("\n".join(stale))


if __name__ == "__main__":
    main()
