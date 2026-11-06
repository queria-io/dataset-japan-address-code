# 住所コード対応表

アドレス・ベース・レジストリの町字と、国勢調査の小地域・郵便番号・3 次メッシュなどの地域コードの対応表を、SQL で結合できるテーブルにしたデータセットです。公式の形がない町字の形も収録しています。

## 出典と利用条件

Queria の公開データセット address_br・e_stat・moj・zipcode を読んで作ります。

| 原典 | 使うテーブル |
| --- | --- |
| [アドレス・ベース・レジストリ](https://dataset.address-br.digital.go.jp/)（デジタル庁） | `address_br.main.mart_town`、`address_br.main.mart_rsdtdsp_blk` |
| [国勢調査 町丁・字等別境界データ](https://www.e-stat.go.jp/gis)（総務省統計局、令和2年） | `e_stat.boundary.small_area` |
| [登記所備付地図データ](https://www.moj.go.jp/MINJI/minji05_00494.html)（法務省） | `moj.chizu.parcel` |
| [郵便番号データ](https://www.post.japanpost.jp/zipcode/download.html)（日本郵便） | `zipcode.main.mart_zipcode` |

- 各原典の利用規約に従います。使うときは原典の出典と、Queria が加工したものであることを明記してください

## テーブル

| テーブル | 内容 |
| --- | --- |
| `main.town_small_area` | 1 行が町字と小地域の 1 組。対応の種類・按分の割合・当て方 |
| `main.town_postal_code` | 1 行が町字と郵便番号の 1 組。当て方は `match_type` |
| `main.town_shape` | 1 行が 1 町字の形。作り方は `shape_method` |
| `main.town_mesh` | 1 行が町字と 3 次メッシュの 1 組。重なりの面積と、それぞれに占める割合 |
| `main.small_area_mesh` | 1 行が小地域と 3 次メッシュ（約 1km 四方）の 1 組。重なりの面積と、それぞれに占める割合 |
| `main.aza_shape` | 1 行が法務省の地図の 1 つの大字・丁目・小字。筆の形を合わせた形 |

町字は `lg_code`（6 桁）と `machiaza_id`（7 桁）の組で一意です。`machiaza_id` だけで結合しないでください。

## 使い方

町字ごとの人口（小地域と 1 対 1 の町字だけ）:

```sql
SELECT t.lg_code, t.machiaza_id, p.value AS population
FROM japan_address_code.main.town_small_area AS t
JOIN e_stat.census.census_small_area_age AS p ON p.area = t.key_code
WHERE t.match_type = 'one_to_one'
  AND p.cat01 = '0010';  -- 総数
```

`small_area_mesh` と `town_mesh` は重なりの面積と、それぞれに占める割合（`small_area_share`・`town_share`・`mesh_share`）を持つため、集計値を面積で按分できます。面積は経緯度の面積をメッシュの中心の緯度で平方メートルに換算した近似値です。小地域ごとの合計は e_stat の `small_area.area_m2` とほぼ一致します（千代田区で 0.2% 差）。`mesh_share` は海や形のない所があるため、同じメッシュの行を合計しても 1 にならないことがあります。

## 町字と小地域の対応（town_small_area）

- 名前は同じ市区町村の中で照合します。ABR の「１丁目」と小地域の「一丁目」のような数字の表記は正規化します
- 名前で当たらない町字は、町字の代表点が入る小地域に当てます（`method = 'point'`）。代表点のない小字は大字・町の代表点を使います
- `match_type` は対応の種類です。`one_to_one`（互いに 1 つだけ）、`town_split`（町字が複数の小地域に分かれる）、`towns_merged`（複数の町字が 1 つの小地域に入る）、`many_to_many`（両方）
- `town_share` は町字が 1 つの小地域にだけ当たるとき 1 で、それ以外は空です。`small_area_share` は `one_to_one` のとき 1 で、それ以外は空です
- `point_mismatch` が true の行は、名前で当たったものの、町字の代表点がこの小地域の外にあります

## 町字と郵便番号の対応（town_postal_code）

郵便番号は、町字マスタにあればそれを、なければ同じ市区町村の中で郵便番号の町域と名前で照合します。大字・字の有無、数字の表記、ケ・ヶ、の・ノ、よく出る異体字（曾・曽、澤・沢など）は正規化します。`match_type` は次のとおりです。

- `abr`: 町字マスタの郵便番号
- `name`: 町域の名前が大字・町の名前と同じ
- `prefix`: 町域の名前が大字・町の名前の先頭と同じ（最も長いもの）
- `sub`: 町域が大字・町より細かく分かれていて、全部同じ郵便番号
- `city`: 当たる町域がなく、市区町村の「以下に掲載がない場合」の郵便番号

町域が丁目や番地で分かれている所では、1 つの町字に郵便番号が複数当たります。ビルの階ごとの郵便番号は入っていません。

## 町字の形（town_shape・aza_shape）

公式の町字の形はないため、国勢調査の小地域（令和2年）と法務省の地図の筆の形から作っています。`shape_method` は次のとおりです。

- `parcel`: 法務省の地図の筆を合わせた形。筆で覆えない所（形のない筆や登記のない道路など）だけ、下のどれかで作った形を残します。筆の分の割合は `parcel_share` です
- `small_area`: 当たる小地域の形をそのまま使った形。複数なら合わせた形
- `voronoi`: 少なくとも 1 つの小地域を、町字の代表点（住居表示の町字は街区の代表点）のボロノイ図で切り分けた形
- `parent_oaza`: 形のない小字。同じ大字・町の形

筆とは大字・丁目・小字の名前で照合します。`aza_shape` は形を持つ筆（公共座標の図面の筆）だけを合わせるため、任意座標系の図面が多い地域では形が欠けます。地番に「地区外」「別図」とある筆は図面の外の土地を指すため使いません。登記のない道路や水路は穴やすき間として残ります。

`town_mesh` には `parent_oaza` の小字は入っていません。同じ大字・町（`machiaza_id` の末尾 000）の行を使ってください。

## ビルド

全国のビルドは GitHub のランナーのメモリに収まらないため、メモリの多い手元の Mac で実行します。毎月 address_br の更新の翌日に `Check upstream` のワークフローが元のデータセットを確認し、address_br・moj・zipcode のどれかが新しくなっていれば Discord に通知します。通知が来たら次を実行します。

```bash
uv sync
FDL_TOKEN=... scripts/build.sh
```

法務省の地図の字の形（`aza_shape`）は、moj が変わっていなければ公開中のものを使い回します。

### 郵便番号の当て方のテストとベンチマーク

町字マスタに郵便番号がある町字（約 9.3 万件）を正解にして、名前での当て方が同じ郵便番号を出すかを当て方ごとに数えます。

- ビルドの `dbt test` が `tests/` のテストを実行し、落ちたら公開しません。正解率が name 99.5%・prefix 80%・sub 99% を下回るか、郵便番号のない町字が出るか、市区町村全体の郵便番号（city）に落ちる町字が 5% を超えると落ちます
- `scripts/bench_postal_code.sh` は同じ数字を表で出力します。当て方を変える前と後に実行して比較します

2026 年 11 月の値: name 99.9%（92,040 件）、prefix 86%（179 件）、sub 100%（345 件）。
