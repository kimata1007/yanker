# Rewriting the line the user pressed Enter on
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

assert_equal 'the short alias is registered as a name' 'yanker y' "${_yanker_names[*]}"

rewrite() { _yanker_rewrite_line "$1"; }

rewrite 'yanker ls | grep foo'
assert_equal 'everything after an unquoted pipe folds into one argument' \
  "yanker 'ls | grep foo'" "$REPLY"

rewrite 'y ls | grep foo'
assert_equal 'the short alias is rewritten too' "y 'ls | grep foo'" "$REPLY"

rewrite 'yanker -o ls | grep foo'
assert_equal '-o stays on the command side' "yanker -o 'ls | grep foo'" "$REPLY"

rewrite 'yanker find . -type f -name "*.zsh" | sort | head -5'
assert_equal 'a long command line still splits at the right place' \
  "yanker 'find . -type f -name \"*.zsh\" | sort | head -5'" "$REPLY"

rewrite 'yanker ls'
assert_equal 'a line without a pipe is left alone' 'yanker ls' "$REPLY"

rewrite "yanker 'ls | grep foo'"
assert_equal 'an already-quoted line is not wrapped twice' "yanker 'ls | grep foo'" "$REPLY"

rewrite 'echo a | grep b'
assert_equal 'a line that does not start with yanker is left alone' 'echo a | grep b' "$REPLY"

rewrite ''
assert_equal 'an empty line is left alone' '' "$REPLY"

rewrite '  yanker ls | grep foo'
assert_equal 'leading whitespace is preserved' "  yanker 'ls | grep foo'" "$REPLY"

rewrite 'yanker echo "a|b"'
assert_equal 'a pipe inside quotes is not an operator' 'yanker echo "a|b"' "$REPLY"
