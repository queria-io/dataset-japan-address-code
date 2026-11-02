"""法務省の地図の筆の形を、大字・丁目・小字ごとに合わせて Parquet にする。

筆は全国 2.45 億あり、dbt の 1 つの集約で合わせるとメモリに乗らないので、公開済みの
moj.chizu.parcel を市区町村ごとに読んで合わせる。形の無い筆（任意座標系）と、図面の外の
土地を指す筆（地番に「地区外」「別図」）は使わない。コードは登記所ごとに振られていることが
あるので、名前の組でまとめる。

全国を合わせるには数時間かかる。法務省の地図は年 1 回しか変わらないので、前回公開した
main.aza_shape が今の moj と同じバージョンから作ったものなら、それを使い回す。

出力: data/aza/*.parquet（models/main/aza_shape.sql が読む）
"""

import logging
import os
from datetime import datetime, timezone
from multiprocessing import Pool
from pathlib import Path

import duckdb

logger = logging.getLogger("pipelines")

AZA_DIR = Path("data/aza")
MOJ = "ducklake:https://data.queria.io/datasets/queria/moj/ducklake.duckdb"
PREVIOUS = "ducklake:https://data.queria.io/datasets/queria/japan_address_code/ducklake.duckdb"

SQL = """
COPY (
    SELECT
        lg_code, oaza, chome, koaza,
        count(*) AS parcels,
        ST_AsWKB(ST_CollectionExtract(ST_MakeValid(ST_Union_Agg(geometry)), 3)) AS geometry,
        '{moj_version}' AS moj_version
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
moj_version = ""


def connect() -> duckdb.DuckDBPyConnection:
    c = duckdb.connect(config={"custom_user_agent": os.environ.get("QUERIA_USER_AGENT", "")})
    c.execute("INSTALL spatial; LOAD spatial; INSTALL ducklake; INSTALL httpfs; SET threads = 1; SET enable_progress_bar = false")
    c.execute(f"ATTACH '{MOJ}' AS moj (READ_ONLY)")
    return c


def init_worker(version: str) -> None:
    global con, moj_version
    con = connect()
    moj_version = version


def union_city(lg_code: str) -> str:
    assert lg_code.isdigit(), lg_code
    output = AZA_DIR / f"{lg_code}.parquet"
    if output.exists():
        return lg_code
    partial = output.with_name(output.name + ".part")
    con.execute(SQL.format(lg_code=lg_code, moj_version=moj_version, output=partial))
    # 形のある筆が 1 つも無い市区町村は、DuckDB がファイルを作らない
    if partial.exists():
        partial.replace(output)
    return lg_code


def current_version(c: duckdb.DuckDBPyConnection) -> str:
    """moj の今のバージョンの目印（最後のスナップショットの番号と時刻）。"""
    snapshot_id, time = c.execute(
        "SELECT snapshot_id, snapshot_time FROM ducklake_snapshots('moj') ORDER BY snapshot_id DESC LIMIT 1"
    ).fetchone()
    return f"{snapshot_id}@{time.astimezone(timezone.utc).isoformat()}"


def same_version(a: str, b: str) -> bool:
    """目印が同じスナップショットを指すか。時刻は書いた手元の時間帯によらず瞬間で比べる。"""
    (id_a, time_a), (id_b, time_b) = (v.split("@", 1) for v in (a, b))
    return id_a == id_b and datetime.fromisoformat(time_a) == datetime.fromisoformat(time_b)


def reuse_previous(c: duckdb.DuckDBPyConnection, version: str) -> bool:
    """前回の aza_shape が同じ moj から作ったものなら data/aza に書き出す。"""
    try:
        c.execute(f"ATTACH '{PREVIOUS}' AS previous (READ_ONLY)")
        versions = c.execute("SELECT DISTINCT moj_version FROM previous.main.aza_shape").fetchall()
    except duckdb.Error as e:
        logger.info("  前回の aza_shape を読めない: %s", e)
        return False
    if len(versions) != 1 or not same_version(versions[0][0], version):
        logger.info("  前回の aza_shape は別の moj から作ったもの: %s", versions)
        return False
    for old in AZA_DIR.glob("*.parquet*"):
        old.unlink()
    c.execute(
        f"COPY (SELECT lg_code, oaza, chome, koaza, parcels, ST_AsWKB(geometry) AS geometry, moj_version "
        f"FROM previous.main.aza_shape) TO '{AZA_DIR / 'previous.parquet'}' (FORMAT parquet, COMPRESSION zstd)"
    )
    return True


def union_all() -> None:
    """途中で止まったら、同じ moj のバージョンで済んだ市区町村は合わせ直さない。"""
    AZA_DIR.mkdir(parents=True, exist_ok=True)
    marker = AZA_DIR / "moj_version"
    with connect() as c:
        version = current_version(c)
        logger.info("  moj のバージョン %s", version)
        if not marker.exists() or marker.read_text() != version:
            for old in AZA_DIR.glob("*.parquet*"):
                old.unlink()
            marker.write_text(version)
        if reuse_previous(c, version):
            logger.info("  前回の aza_shape を使い回す")
            return
        cities = [r[0] for r in c.execute("SELECT DISTINCT lg_code FROM moj.chizu.source ORDER BY 1").fetchall()]
    logger.info("  %d 市区町村を合わせる", len(cities))
    for part in AZA_DIR.glob("*.part"):
        part.unlink()
    with Pool(initializer=init_worker, initargs=(version,)) as pool:
        for done, city in enumerate(pool.imap_unordered(union_city, cities), 1):
            if done % 100 == 0 or done == len(cities):
                logger.info("  [%d/%d] %s", done, len(cities), city)
