# クリップボードコマンドの選び方
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

YANKER_CLIPBOARD='my-clip --paste' _yanker_clipboard_command
assert_equal 'YANKER_CLIPBOARD を最優先する' 'my-clip --paste' "$REPLY"

# PATH を差し替えて自動判定を試す。commands は PATH のキャッシュなので rehash が要る
probe_with_path() {
  local dir=$1 name=$2
  zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    PATH=${(q)dir}; rehash
    unset YANKER_CLIPBOARD
    if _yanker_clipboard_command; then print -r -- \"0:\$REPLY\"; else print -r -- \"1:\$REPLY\"; fi
  " 2>&1
}

typeset tmp=$(mktemp -d)
{
  print -r -- '#!/bin/sh' > $tmp/xclip; chmod +x $tmp/xclip
  assert_equal 'PATH にある xclip を見つける' '0:xclip -selection clipboard' "$(probe_with_path $tmp)"

  print -r -- '#!/bin/sh' > $tmp/pbcopy; chmod +x $tmp/pbcopy
  assert_equal '候補が複数あれば先に並べた pbcopy を選ぶ' '0:pbcopy' "$(probe_with_path $tmp)"

  typeset empty=$(mktemp -d)
  assert_equal '候補が1つも無ければ失敗を返す' '1:' "$(probe_with_path $empty)"
  rmdir $empty
} always {
  rm -rf $tmp
}

# クリップボードが無い環境では yanker 自体がエラーで止まる。
# PATH を空ディレクトリだけにすると候補が1つも見つからない状態を作れる
typeset none=$(mktemp -d)
typeset out=$(zsh -f -c "
  source ${(q)YANKER_ROOT}/yanker.plugin.zsh
  PATH=${(q)none}; rehash
  unset YANKER_CLIPBOARD
  yanker echo hi >/dev/null 2>/dev/null
  print -r -- \$?
" 2>/dev/null)
rmdir $none
assert_equal 'クリップボードが無ければ 127 を返す' '127' "$out"

typeset none2=$(mktemp -d)
typeset err=$(zsh -f -c "
  source ${(q)YANKER_ROOT}/yanker.plugin.zsh
  PATH=${(q)none2}; rehash
  unset YANKER_CLIPBOARD
  yanker echo hi 2>&1 >/dev/null
" 2>&1)
rmdir $none2
assert_equal 'そのとき理由を標準エラー出力へ書く' \
  'yanker: クリップボードへ書くコマンドが見つかりません。YANKER_CLIPBOARD を設定してください' "$err"
