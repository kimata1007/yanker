# 取り込んだ出力が欠けたり変質したりしないか。
# 順序については下の注記のとおり保証しない
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

typeset tmpdir=$(mktemp -d)
typeset clipfile=$tmpdir/clip.txt
export YANKER_CLIPBOARD="cat > ${(q)clipfile}"

{
  yanker -o 'seq 1 50000' >/dev/null
  assert_equal '大量の行を落とさない' '50000' "$(wc -l < $clipfile | tr -d ' ')"
  assert_equal '大量出力の末尾まで届く' '50000' "$(tail -1 $clipfile)"

  yanker -o 'printf abc' >/dev/null
  assert_equal '末尾に改行が無い出力へ改行を足さない' '616263' "$(xxd -p $clipfile | tr -d '\n')"

  yanker -o 'printf "a\000b"' >/dev/null
  assert_equal 'NUL を含むバイト列をそのまま通す' '610062' "$(xxd -p $clipfile | tr -d '\n')"

  yanker -o 'print -r -- "   前後の空白  "' >/dev/null
  assert_equal '行内の空白を保つ' '202020e5898de5be8ce381aee7a9bae799bd20200a' "$(xxd -p $clipfile | tr -d '\n')"

  # stdout を stdio でバッファする処理系では、標準出力と標準エラー出力の
  # 到着順が端末で見たときと変わる。順序は保証しないが、取りこぼしはしない
  if (( ${+commands[python3]} )); then
    yanker -o 'python3 -c "
import sys
print(\"out1\"); sys.stderr.write(\"err1\n\"); print(\"out2\"); sys.stderr.write(\"err2\n\")
"' >/dev/null
    assert_equal 'バッファされる処理系でも4行すべて残る' \
      $'err1\nerr2\nout1\nout2' "$(sort $clipfile)"
  else
    print -r -- '  skip バッファ順序の確認（python3 が無い）'
  fi

  # 標準出力はパイプなので、色やページャを tty 判定で切り替えるコマンドは
  # 非対話モードで動く。cmd | tee と同じ挙動
  yanker -o '[[ -t 1 ]] && print -r -- tty || print -r -- pipe' >/dev/null
  assert_equal 'コマンドから見た標準出力はパイプになる' 'pipe' "$(cat $clipfile)"
} always {
  rm -rf $tmpdir
  unset YANKER_CLIPBOARD
}
