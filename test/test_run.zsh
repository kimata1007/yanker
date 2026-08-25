# 実行・表示・コピーの結合。テストランナー自体が端末を持たないので、
# 「tty が無くても壊れない」という要件はここで同時に検証している
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

typeset tmpdir=$(mktemp -d)
typeset clipfile=$tmpdir/clip.txt

# クリップボードの代わりにファイルへ書かせ、中身を突き合わせる
export YANKER_CLIPBOARD="cat > ${(q)clipfile}"

clipped() { cat $clipfile }

{
  typeset shown ret

  shown=$(yanker echo hello)
  assert_equal '画面にコマンド行と出力を出す' $'$ echo hello\nhello' "$shown"
  assert_equal '同じ内容をコピーする'         $'$ echo hello\nhello' "$(clipped)"

  shown=$(yanker -o echo hello)
  assert_equal '-o は画面からコマンド行を省く' 'hello' "$shown"
  assert_equal '-o はコピーからも省く'         'hello' "$(clipped)"

  # 本来の不具合。標準エラー出力へ出るメッセージが漏れないこと
  shown=$(yanker 'print -ru2 -- "ls: missing.txt: No such file or directory"')
  assert_equal '標準エラー出力もコピーに含める' \
    $'$ print -ru2 -- "ls: missing.txt: No such file or directory"\nls: missing.txt: No such file or directory' \
    "$(clipped)"

  # 標準出力と標準エラー出力が混ざる場合
  yanker -o 'print -r -- out; print -ru2 -- err' >/dev/null
  assert_equal '両方の出力を順に取り込む' $'out\nerr' "$(clipped)"

  yanker echo hi >/dev/null; ret=$?
  assert_status '成功したコマンドの終了ステータスを返す' 0 $ret

  yanker 'exit 3' >/dev/null; ret=$?
  assert_status '失敗したコマンドの終了ステータスを返す' 3 $ret

  yanker >/dev/null 2>/dev/null; ret=$?
  assert_status '引数が無ければ 2 を返す' 2 $ret

  # 呼び出し側が標準出力をパイプへ流していても、表示とコピーの両方が成立する
  assert_equal '標準出力がパイプでも表示側は流れる' '2' "$(yanker -o 'print -r -- a; print -r -- b' | wc -l | tr -d ' ')"
  assert_equal 'そのときコピー側も欠けない' $'a\nb' "$(clipped)"
} always {
  rm -rf $tmpdir
  unset YANKER_CLIPBOARD
}
