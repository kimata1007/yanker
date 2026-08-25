# 疑似端末での結合テスト。Enter を押した行が実際に書き換わるかは、
# ウィジェットの登録状態を見るだけでは分からないのでここで確かめる
if (( ! ${+commands[expect]} )); then
  print -r -- '  skip 疑似端末テスト（expect が無い）'
  return 0
fi

# 行を1つ打ち込み、コピーされた内容を返す。
# 第2引数はプラグインを読み込む前に流す設定
type_line() {
  local line=$1 extra=$2
  local dir=$(mktemp -d)
  {
    expect $YANKER_ROOT/test/integration/accept_line.exp \
      "$YANKER_ROOT/yanker.plugin.zsh" "$dir/clip.txt" "$line" "$extra" > $dir/log 2>&1
    # 落ちたときに原因を追えるよう、端末とのやり取りをそのまま出す
    if [[ ! -s $dir/clip.txt ]]; then
      print -ru2 -- '       --- expect の記録 ---'
      sed 's/^/       /' $dir/log >&2
    fi
    cat $dir/clip.txt 2>/dev/null
  } always {
    rm -rf $dir
  }
}

assert_equal 'Enter を押すとパイプごと yanker へ渡る' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'yanker echo hello | tr a-z A-Z')"

assert_equal '短縮名 y でも同じ経路を通る' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'y echo hello | tr a-z A-Z')"

assert_equal '標準エラー出力へ出るメッセージもコピーされる' \
  $'$ print -ru2 -- no-such-file\nno-such-file' \
  "$(type_line "yanker 'print -ru2 -- no-such-file'")"

# ZLE 連携を切った状態。端末の種類に頼らず、設定で確実に同じ経路へ入れる。
# TERM=dumb での判定は macOS と Linux で結果が違うため使わない
assert_equal 'ZLE 連携が無効なら関数として動く' \
  $'$ echo hello\nhello' \
  "$(type_line 'yanker echo hello | tr a-z A-Z' 'YANKER_BIND_ACCEPT_LINE=0')"
