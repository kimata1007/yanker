# Choosing a clipboard command
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

YANKER_CLIPBOARD='my-clip --paste' _yanker_clipboard_command
assert_equal 'YANKER_CLIPBOARD wins over auto-detection' 'my-clip --paste' "$REPLY"

# Swap PATH to exercise auto-detection. `commands` caches PATH, so rehash first.
probe_with_path() {
  local dir=$1
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
  assert_equal 'finds xclip on PATH' '0:xclip -selection clipboard' "$(probe_with_path $tmp)"

  print -r -- '#!/bin/sh' > $tmp/pbcopy; chmod +x $tmp/pbcopy
  assert_equal 'prefers whichever candidate is listed first' '0:pbcopy' "$(probe_with_path $tmp)"

  typeset empty=$(mktemp -d)
  assert_equal 'reports failure when no candidate exists' '1:' "$(probe_with_path $empty)"
  rmdir $empty
} always {
  rm -rf $tmp
}

# With no clipboard available yanker stops rather than discarding the output.
# A PATH holding only an empty directory reproduces that state.
typeset none=$(mktemp -d)
typeset out=$(zsh -f -c "
  source ${(q)YANKER_ROOT}/yanker.plugin.zsh
  PATH=${(q)none}; rehash
  unset YANKER_CLIPBOARD
  yanker echo hi >/dev/null 2>/dev/null
  print -r -- \$?
" 2>/dev/null)
rmdir $none
assert_equal 'exits 127 when no clipboard command is found' '127' "$out"

typeset none2=$(mktemp -d)
typeset err=$(zsh -f -c "
  source ${(q)YANKER_ROOT}/yanker.plugin.zsh
  PATH=${(q)none2}; rehash
  unset YANKER_CLIPBOARD
  yanker echo hi 2>&1 >/dev/null
" 2>&1)
rmdir $none2
assert_equal 'and says why on stderr' \
  'yanker: no clipboard command found; set YANKER_CLIPBOARD' "$err"
