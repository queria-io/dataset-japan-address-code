# dataset-japan-address-code

アドレス・ベース・レジストリの町字と、国勢調査の小地域などの地域コードの対応表を Queria のカタログ（[data.queria.io](https://data.queria.io/)）へ載せるデータセットです。

## データ出典

Queria の公開データセット address_br と e_stat を読んで作ります。取得はしません。

| 原典 | 使う表 |
| --- | --- |
| [アドレス・ベース・レジストリ](https://dataset.address-br.digital.go.jp/)（デジタル庁） | `address_br.main.mart_town` |
| [国勢調査 町丁・字等別境界データ](https://www.e-stat.go.jp/gis)（総務省統計局、令和2年） | `e_stat.boundary.small_area` |

## 収録テーブル

| テーブル | 内容 |
| --- | --- |
| `main.town_small_area` | 1 行が町字と小地域の 1 組。対応の種類・按分の割合・当て方 |
| `main.town_shape` | 1 行が 1 町字の形。作り方は `shape_method` |
| `main.small_area_mesh` | 1 行が小地域と 3 次メッシュ（約 1km）の 1 組。重なりの面積と、それぞれに占める割合 |

- 町字は `lg_code`（6 桁）と `machiaza_id`（7 桁）の組で一意です。`machiaza_id` だけで結合しないでください
- 名前は同じ市区町村の中で突き合わせます。ABR の「１丁目」と小地域の「一丁目」のような数字の書き方はそろえます
- 名前で当たらない町字は、町字の代表点が入る小地域に当てます。代表点の無い小字は大字・町の代表点を使います
- 町字の形は、名前で 1 対 1 に当たる小地域の形と、小字に大字・町の形を当てたものだけです

```sql
-- 町字ごとの人口（小地域と 1 対 1 の町字だけ）
SELECT t.lg_code, t.machiaza_id, p.value AS population
FROM japan_address_code.main.town_small_area AS t
JOIN e_stat.census.census_small_area_age AS p ON p.area = t.key_code
WHERE t.match_type = 'one_to_one'
  AND p.cat01 = '0010'  -- 総数
```

## ビルド

```bash
uv sync
scripts/build.sh
```
