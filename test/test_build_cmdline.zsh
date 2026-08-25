# 引数から eval できるコマンド行を組み立てられるか
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

_yanker_build_cmdline pwd
assert_equal '単語1つはそのまま' 'pwd' "$REPLY"

_yanker_build_cmdline echo 'a b'
assert_equal '空白を含む引数はクォートする' "echo 'a b'" "$REPLY"

_yanker_build_cmdline echo '$HOME'
assert_equal '展開されうる文字はクォートで守る' "echo '\$HOME'" "$REPLY"

_yanker_build_cmdline ls '|' grep foo
assert_equal '演算子はクォートせず残す' 'ls | grep foo' "$REPLY"

_yanker_build_cmdline kubectl get pods '2>&1'
assert_equal 'リダイレクトも演算子として扱う' 'kubectl get pods 2>&1' "$REPLY"

_yanker_build_cmdline 'ls | grep foo'
assert_equal '単一引数はシェルの文としてそのまま扱う' 'ls | grep foo' "$REPLY"

_yanker_build_cmdline 'exit 3'
assert_equal '演算子を含まない単一引数も文として扱う' 'exit 3' "$REPLY"
