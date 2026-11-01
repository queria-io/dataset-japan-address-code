"""住所の ID と統計の地域コードの対応表を作る。

元は Queria の公開データセット（address_br・e_stat・moj）で、取得はしない。

1. aza: 法務省の地図の筆を大字・丁目・小字ごとに合わせる（市区町村ごと）
2. dbt
"""

import logging

from dbt.cli.main import dbtRunner

from pipelines.aza import union_all

# dbt を読み込むとルートロガーが先に設定されるので、force で上書きする
logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
logger = logging.getLogger("pipelines")


def main():
    logger.info("1/2: aza (筆を大字・丁目・小字ごとに合わせる)")
    union_all()

    logger.info("2/2: dbt")
    dbt = dbtRunner()
    for args in (["deps"], ["run"], ["docs", "generate"]):
        if not dbt.invoke(args).success:
            raise SystemExit(f"dbt {args[0]} failed")


if __name__ == "__main__":
    main()
