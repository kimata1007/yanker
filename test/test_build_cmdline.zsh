# Turning arguments into an evaluatable command line
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

_yanker_build_cmdline pwd
assert_equal 'a lone word passes through unchanged' 'pwd' "$REPLY"

_yanker_build_cmdline echo 'a b'
assert_equal 'an argument containing a space is quoted' "echo 'a b'" "$REPLY"

_yanker_build_cmdline echo '$HOME'
assert_equal 'expandable characters are protected by quoting' "echo '\$HOME'" "$REPLY"

_yanker_build_cmdline ls '|' grep foo
assert_equal 'operators are left unquoted' 'ls | grep foo' "$REPLY"

_yanker_build_cmdline make build '2>&1'
assert_equal 'redirections count as operators' 'make build 2>&1' "$REPLY"

_yanker_build_cmdline 'ls | grep foo'
assert_equal 'a single argument is treated as shell source' 'ls | grep foo' "$REPLY"

_yanker_build_cmdline 'exit 3'
assert_equal 'that holds even without an operator in it' 'exit 3' "$REPLY"
