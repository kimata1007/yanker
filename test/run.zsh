#!/usr/bin/env zsh
# テストランナー。test/test_*.zsh をすべて実行し、1つでも落ちたら 1 を返す。
# err_return は使わない。失敗した assert でそこから先が走らなくなり、
# 何件落ちたのかが分からなくなるため、件数を数えて最後に判定する
emulate -L zsh

typeset -g TEST_DIR=${0:A:h}
source $TEST_DIR/helper.zsh

typeset -a files=($TEST_DIR/test_*.zsh(N))
if (( ! $#files )); then
  print -ru2 -- 'テストファイルが見つかりません'
  exit 1
fi

typeset f
for f in $files; do
  print -r -- "${f:t:r}"
  source $f
done

print -r -- ''
print -r -- "合計 ${YANKER_TEST_RUN} 件 / 失敗 ${YANKER_TEST_FAILED} 件"
(( YANKER_TEST_FAILED == 0 ))
