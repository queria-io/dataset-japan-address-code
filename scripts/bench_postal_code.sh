#!/usr/bin/env bash
# 郵便番号の当て方の答え合わせを当て方ごとの表で出す。公開物は作らない。
# ビルドでは tests/town_postal_code_accuracy.sql が同じ数字の下限を見る
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
FDL_WORKING="$tmp/work.sqlite" FDL_DATA_PATH="$tmp/data/" \
    uv run dbt show --inline "{{ postal_code_bench() }}" --limit 20
