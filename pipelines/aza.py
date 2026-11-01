"""法務省の地図の筆の形を、大字・丁目・小字ごとに合わせて市区町村ごとの Parquet にする。

筆は全国 2.45 億あり、dbt の 1 つの集約で合わせるとメモリに乗らないので、公開済みの
moj.chizu.parcel を市区町村ごとに読んで合わせる。形の無い筆（任意座標系）と、図面の外の
土地を指す筆（地番に「地区外」「別図」）は使わない。コードは登記所ごとに振られていることが
あるので、コードと名前の組でまとめる。

出力: data/aza/<lg_code>.parquet（models/main/town_shape.sql が読む）
"""

import logging
import os
from multiprocessing import Pool
from pathlib import Path

import duckdb

logger = logging.getLogger("pipelines")

AZA_DIR = Path("data/aza")
MOJ = "ducklake:https://data.queria.io/datasets/queria/moj/ducklake.duckdb"

SQL = """
COPY (
    SELECT
        lg_code, oaza, chome, koaza,
        count(*) AS parcels,
        ST_AsWKB(ST_CollectionExtract(ST_MakeValid(ST_Union_Agg(geometry)), 3)) AS geometry
    FROM moj.chizu.parcel
    WHERE lg_code = '{lg_code}'
        AND geometry IS NOT NULL
        AND oaza IS NOT NULL
        AND chiban NOT LIKE '%地区外%'
        AND chiban NOT LIKE '%別図%'
    GROUP BY ALL
    ORDER BY ALL
) TO '{output}' (FORMAT parquet, COMPRESSION zstd)
"""

con: duckdb.DuckDBPyConnection | None = None


def connect() -> duckdb.DuckDBPyConnection:
    c = duckdb.connect(config={"custom_user_agent": os.environ.get("QUERIA_USER_AGENT", "")})
    c.execute("INSTALL spatial; LOAD spatial; INSTALL ducklake; INSTALL httpfs; SET threads = 1")
    c.execute(f"ATTACH '{MOJ}' AS moj (READ_ONLY)")
    return c


def init_worker() -> None:
    global con
    con = connect()


def union_city(lg_code: str) -> str:
    output = AZA_DIR / f"{lg_code}.parquet"
    partial = output.with_name(output.name + ".part")
    assert lg_code.isdigit(), lg_code
    con.execute(SQL.format(lg_code=lg_code, output=partial))
    partial.replace(output)
    return lg_code


def union_all() -> None:
    """筆のある市区町村ごとに合わせる。毎回まるごと作り直す。"""
    with connect() as c:
        cities = [r[0] for r in c.execute("SELECT DISTINCT lg_code FROM moj.chizu.source ORDER BY 1").fetchall()]
    AZA_DIR.mkdir(parents=True, exist_ok=True)
    for old in AZA_DIR.glob("*.parquet*"):
        old.unlink()
    logger.info("  %d 市区町村", len(cities))
    with Pool(initializer=init_worker) as pool:
        for done, city in enumerate(pool.imap_unordered(union_city, cities), 1):
            if done % 100 == 0 or done == len(cities):
                logger.info("  [%d/%d] %s", done, len(cities), city)
