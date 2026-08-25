# 疑似端末での結合テスト。Enter を押した行が実際に書き換わるかは、
# ウィジェットの登録状態を見るだけでは分からないのでここで確かめる
if (( ! ${+commands[expect]} )); then
  print -r -- '  skip 疑似端末テスト（expect が無い）'
  return 0
fi

# 行を1つ打ち込み、コピーされた内容を返す
type_line() {
  local line=$1
  local term=${2:-vt100}
  local home=$(mktemp -d)
  {
    cat > $home/.zshrc <<ZRC
unsetopt prompt_sp prompt_cr
PS1='READY> '
RPS1=''
YANKER_CLIPBOARD="cat > ${(q)home}/clip.txt"
source ${(q)YANKER_ROOT}/yanker.plugin.zsh
ZRC
    expect $YANKER_ROOT/test/integration/accept_line.exp "$YANKER_ROOT" "$home" "$line" "$term" >/dev/null 2>&1
    cat $home/clip.txt 2>/dev/null
  } always {
    rm -rf $home
  }
}

assert_equal 'Enter を押すとパイプごと yanker へ渡る' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'yanker echo hello | tr a-z A-Z')"

assert_equal '短縮名 y でも同じ経路を通る' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'y echo hello | tr a-z A-Z')"

assert_equal '標準エラー出力へ出るメッセージもコピーされる' \
  $'$ print -ru2 -- no-resources\nno-resources' \
  "$(type_line "yanker 'print -ru2 -- no-resources'")"

# TERM=dumb では zsh が zsh/zle を読み込まないため、ウィジェットを張れない。
# その場合でも関数として動き、パイプの自動クォートだけを諦めることを確かめる
assert_equal 'ZLE が使えない端末では関数として動く' \
  $'$ echo hello\nhello' \
  "$(type_line 'yanker echo hello | tr a-z A-Z' dumb)"
