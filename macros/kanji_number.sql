{#
  文字列の中の全角数字 (１〜９９) を漢数字に直す。ABR の町字は「１丁目」「東光８条」、
  国勢調査の小地域は「一丁目」「東光八条」と書くので、名前を突き合わせる前にそろえる。
  長い数字から置き換える (「１２」を「１」より先に)
#}
{% macro kanji_number(expr) %}
list_reduce(
    (
        SELECT list(
            struct_pack(
                fw := translate(i::VARCHAR, '0123456789', '０１２３４５６７８９'),
                kj := CASE WHEN i >= 20 THEN substr('一二三四五六七八九', i // 10, 1) ELSE '' END
                    || CASE WHEN i >= 10 THEN '十' ELSE '' END
                    || CASE WHEN i % 10 > 0 THEN substr('一二三四五六七八九', i % 10, 1) ELSE '' END
            )
            ORDER BY i DESC
        )
        FROM range(1, 100) r(i)
    ),
    (acc, x) -> struct_pack(fw := replace(acc.fw, x.fw, x.kj), kj := ''),
    struct_pack(fw := {{ expr }}, kj := '')
).fw
{% endmacro %}
