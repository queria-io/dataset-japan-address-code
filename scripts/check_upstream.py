"""公開中の japan_address_code を作ったあとに、元のデータセットが新しくなったかを見る。

全国のビルドは GitHub のランナーのメモリに収まらないので手元で流す。ここは確かめるだけで、
新しくなった元のデータセットの名前を 1 行ずつ出す（何も出なければ作り直さなくてよい）。
e_stat の小地域の形は国勢調査ごと（5 年に 1 回）にしか変わらないので見ない。
"""

import os

import duckdb

DATASET = "japan_address_code"
UPSTREAM = ("address_br", "moj", "zipcode")


def latest(c: duckdb.DuckDBPyConnection, name: str):
    c.execute(f"ATTACH 'ducklake:https://data.queria.io/datasets/queria/{name}/ducklake.duckdb' AS {name} (READ_ONLY)")
    return c.execute(f"SELECT epoch_us(max(snapshot_time)) FROM ducklake_snapshots('{name}')").fetchone()[0]


def main() -> None:
    c = duckdb.connect(config={"custom_user_agent": os.environ.get("QUERIA_USER_AGENT", "queria-build/check")})
    c.execute("INSTALL ducklake; LOAD ducklake; INSTALL httpfs; LOAD httpfs")
    built = latest(c, DATASET)
    print("\n".join(name for name in UPSTREAM if latest(c, name) > built))


if __name__ == "__main__":
    main()
