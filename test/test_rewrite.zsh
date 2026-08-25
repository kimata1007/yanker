# Enter を押した行の書き換え
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

assert_equal '短縮名 y が呼び名に登録される' 'yanker y' "${_yanker_names[*]}"

rewrite() { _yanker_rewrite_line "$1"; }

rewrite 'yanker ls | grep foo'
assert_equal '素のパイプ以降を1つの引数にまとめる' "yanker 'ls | grep foo'" "$REPLY"

rewrite 'y ls | grep foo'
assert_equal '短縮名でも書き換える' "y 'ls | grep foo'" "$REPLY"

rewrite 'yanker -o ls | grep foo'
assert_equal '-o はコマンド名の側に残す' "yanker -o 'ls | grep foo'" "$REPLY"

rewrite 'yanker find . -type f -name "*.zsh" | sort | head -5'
assert_equal '長いコマンドでも境界を誤らない' \
  "yanker 'find . -type f -name \"*.zsh\" | sort | head -5'" "$REPLY"

rewrite 'yanker ls'
assert_equal 'パイプが無ければ触らない' 'yanker ls' "$REPLY"

rewrite "yanker 'ls | grep foo'"
assert_equal 'すでに引用済みの行を二重に括らない' "yanker 'ls | grep foo'" "$REPLY"

rewrite 'echo a | grep b'
assert_equal 'yanker で始まらない行は触らない' 'echo a | grep b' "$REPLY"

rewrite ''
assert_equal '空行は触らない' '' "$REPLY"

rewrite '  yanker ls | grep foo'
assert_equal '行頭の空白を保つ' "  yanker 'ls | grep foo'" "$REPLY"

rewrite 'yanker echo "a|b"'
assert_equal '引用符の中のパイプは演算子と見なさない' 'yanker echo "a|b"' "$REPLY"
