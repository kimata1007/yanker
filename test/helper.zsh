# テストの共通処理。各 test_*.zsh はこれを source 済みの環境で読み込まれる

typeset -g YANKER_TEST_RUN=0
typeset -g YANKER_TEST_FAILED=0
typeset -g YANKER_TEST_CURRENT=''

# リポジトリのルート
typeset -g YANKER_ROOT=${0:A:h:h}

assert_equal() {
  local desc=$1 expected=$2 actual=$3
  YANKER_TEST_RUN=$(( YANKER_TEST_RUN + 1 ))
  if [[ "$expected" == "$actual" ]]; then
    print -r -- "  ok   $desc"
    return 0
  fi
  YANKER_TEST_FAILED=$(( YANKER_TEST_FAILED + 1 ))
  print -r -- "  FAIL $desc"
  print -r -- "         expected: [$expected]"
  print -r -- "         actual:   [$actual]"
  return 1
}

assert_status() {
  local desc=$1 expected=$2 actual=$3
  assert_equal "$desc" "$expected" "$actual"
}

# 子 zsh でプラグインを読み込み、渡したコードを走らせて出力を返す。
# 読み込み時の副作用（alias 作成、ウィジェット登録）ごと検証したいので毎回別プロセスにする
run_in_zsh() {
  local code=$1
  zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    $code
  " 2>&1
}
