# 住所コード対応表

アドレス・ベース・レジストリの町字と、国勢調査の小地域・郵便番号・3 次メッシュなどの地域コードの対応表を、SQL で結合できるテーブルにしたデータセットです。公式の形がない町字の形と、不動産取引の地区・ハローワークの管轄区域を地域コードに当てた対応表も収録しています。

## 出典と利用条件

Queria の公開データセット address_br・e_stat・geospatial・zipcode・reinfolib・mhlw を読んで作ります。

| 原典 | 使うテーブル |
| --- | --- |
| [アドレス・ベース・レジストリ](https://dataset.address-br.digital.go.jp/)（デジタル庁） | `address_br.main.mart_town`、`address_br.main.mart_rsdtdsp_blk` |
| [国勢調査 町丁・字等別境界データ](https://www.e-stat.go.jp/gis)（総務省統計局、令和2年） | `e_stat.boundary.small_area` |
| [登記所備付地図データ](https://www.moj.go.jp/MINJI/minji05_00494.html)（法務省） | `geospatial.chizu.parcel` |
| [郵便番号データ](https://www.post.japanpost.jp/zipcode/download.html)（日本郵便） | `zipcode.main.mart_zipcode` |
| [不動産情報ライブラリ](https://www.reinfolib.mlit.go.jp/)（国土交通省） | `reinfolib.main.mart_trade_prices` |
| [都道府県労働局（労働基準監督署、公共職業安定所）所在地一覧](https://www.mhlw.go.jp/kouseiroudoushou/shozaiannai/roudoukyoku/index.html)（厚生労働省） | `mhlw.hellowork.jurisdiction_area` |

- 各原典の利用規約に従います。使うときは原典の出典と、Queria が加工したものであることを明記してください
- 不動産情報ライブラリ: 「このサービスは、国土交通省の不動産情報ライブラリのAPI機能を使用していますが、提供情報の最新性、正確性、完全性等が保証されたものではありません。」

## テーブル

| テーブル | 内容 |
| --- | --- |
| `main.town_small_area` | 1 行が町字と小地域の 1 組。対応の種類・按分の割合・当て方 |
| `main.town_postal_code` | 1 行が町字と郵便番号の 1 組。当て方は `match_type` |
| `main.town_shape` | 1 行が 1 町字の形。作り方は `shape_method` |
| `main.town_mesh` | 1 行が町字と 3 次メッシュの 1 組。重なりの面積と、それぞれに占める割合 |
| `main.small_area_mesh` | 1 行が小地域と 3 次メッシュ（約 1km 四方）の 1 組。重なりの面積と、それぞれに占める割合 |
| `main.aza_shape` | 1 行が法務省の地図の 1 つの大字・丁目・小字。筆の形を合わせた形 |
| `main.trade_district_small_area` | 1 行が不動産取引の地区と小地域の 1 組 |
| `main.hellowork_city` | 1 行が市区町村と公共職業安定所（ハローワーク）の 1 組 |

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

取引ごとに小地域コードを付ける（地区が 1 つの大字・町に決まるものだけ）:

```sql
SELECT t.*, d.key_code
FROM reinfolib.main.mart_trade_prices AS t
JOIN japan_address_code.main.trade_district_small_area AS d USING (municipality_code, district_name)
WHERE d.oaza_count = 1;
```

つくば市を受け持つハローワークと、その所在地:

```sql
SELECT h.office_name, h.office_kind, h.coverage, o.full_address, o.phone
FROM japan_address_code.main.hellowork_city AS h
JOIN mhlw.hellowork.office AS o USING (prefecture_code, office_name, office_kind)
WHERE h.lg_code = '082201';
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

## 不動産取引の地区と小地域の対応（trade_district_small_area）

- 地区名をアドレス・ベース・レジストリの大字・町の名前に当て、その町字を `town_small_area` で小地域に結合します
- 1 つの地区は、大字・町にかかる小地域すべてと組になります。取引がその中のどこかは判定できません
- `mart_trade_prices` とは `municipality_code` と `district_name` の 2 つで結合します（どちらも `mart_trade_prices` の値のままです。北海道などは先頭の 0 が落ちた 4 桁です）
- 地区名が住所の台帳にない地区は、`key_code` が空の 1 行になります。同じ名前の大字・町が市区町村に複数あるときは、そのすべての小地域と組になり、`oaza_count` が 2 以上になります
- 名前は「ヶ」と「ケ」、先頭の「大字」「字」、末尾の丁目を正規化して比較します

## 市区町村ごとの管轄ハローワーク（hellowork_city）

- 厚生労働省の管轄一覧表の項目（`mhlw.hellowork.jurisdiction_area`）を、アドレス・ベース・レジストリの市区町村の名前（`address_br.main.mart_city`）と照合します
- 「水戸市」「愛知郡東郷町」のような市区町村の名前はそのまま、「猿島郡」は郡の町村すべて、「横浜市」は区すべてに当てます
- 「稲敷郡のうち阿見町」「横浜市のうち鶴見区」の後ろに続く項目は、同じ郡の町村、同じ市の区として照合します
- 「長岡市のうち川口相川」「青森市（黒石公共職業安定所の管轄区域を除く。）」のような項目は、市区町村の一部として `coverage` を `partial` にします。「のうち」の後ろに続く町・字は市区町村には当てません。その市区町村の大字・町（`address_br.main.mart_town`）に同じ名前が無く、市区町村の名前と一致する項目だけを市区町村として照合します
- 名前は「ヶ」と「ケ」を正規化して比較します。同じ都道府県に同じ名前の市区町村が 2 つあるとき（北海道の泊村）は照合しません
- 管轄一覧表に合併・改称の前の名前が残っている市区町村（篠山市、塩釜市）と、廃止された郡（東磐井郡）の項目は照合できず、行になりません
