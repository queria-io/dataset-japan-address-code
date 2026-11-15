# dataset-japan-address-code

Queria のデータセット `japan_address_code`（住所コード対応表）のリポジトリです。データセットの説明は [docs/index.md](docs/index.md) にあります。

## ビルド

全国のビルドは GitHub のランナーのメモリに収まらないため、メモリの多い手元の Mac で実行します。毎月 address_br の更新の翌日に `Check upstream` のワークフローが元のデータセットを確認し、address_br・geospatial の chizu・zipcode のどれかが新しくなっていれば Discord に通知します。通知が来たら次を実行します。

```bash
uv sync
FDL_TOKEN=... scripts/build.sh
```

法務省の地図の字の形（`aza_shape`）は、geospatial の chizu のデータファイルが変わっていなければ公開中のものを使い回します。

### 郵便番号の当て方のテストとベンチマーク

町字マスタに郵便番号がある町字（約 9.3 万件）を正解にして、名前での当て方が同じ郵便番号を出すかを当て方ごとに数えます。

- ビルドの `dbt test` が `tests/` のテストを実行し、落ちたら公開しません。正解率が name 99.5%・prefix 80%・sub 99% を下回るか、郵便番号のない町字が出るか、市区町村全体の郵便番号（city）に落ちる町字が 5% を超えると落ちます
- `scripts/bench_postal_code.sh` は同じ数字を表で出力します。当て方を変える前と後に実行して比較します

2026 年 11 月の値: name 99.9%（92,040 件）、prefix 86%（179 件）、sub 100%（345 件）。
