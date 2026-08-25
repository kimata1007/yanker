# Running, displaying and copying, end to end.
# The runner itself has no terminal, so this also covers the "works without a
# tty" requirement.
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

typeset tmpdir=$(mktemp -d)
typeset clipfile=$tmpdir/clip.txt

# Write to a file instead of a real clipboard so the content can be compared
export YANKER_CLIPBOARD="cat > ${(q)clipfile}"

clipped() { cat $clipfile }

{
  typeset shown ret

  shown=$(yanker echo hello)
  assert_equal 'prints the command line and the output' $'$ echo hello\nhello' "$shown"
  assert_equal 'copies the same text'                   $'$ echo hello\nhello' "$(clipped)"

  shown=$(yanker -o echo hello)
  assert_equal '-o drops the command line from the display' 'hello' "$shown"
  assert_equal '-o drops it from the copy as well'          'hello' "$(clipped)"

  # The original bug: a message written to stderr must not be lost
  shown=$(yanker 'print -ru2 -- "ls: missing.txt: No such file or directory"')
  assert_equal 'stderr is included in the copy' \
    $'$ print -ru2 -- "ls: missing.txt: No such file or directory"\nls: missing.txt: No such file or directory' \
    "$(clipped)"

  # Both streams together
  yanker -o 'print -r -- out; print -ru2 -- err' >/dev/null
  assert_equal 'takes in both streams' $'out\nerr' "$(clipped)"

  yanker echo hi >/dev/null; ret=$?
  assert_status 'returns the exit status of a command that succeeded' 0 $ret

  yanker 'exit 3' >/dev/null; ret=$?
  assert_status 'returns the exit status of a command that failed' 3 $ret

  yanker >/dev/null 2>/dev/null; ret=$?
  assert_status 'returns 2 when called with no arguments' 2 $ret

  # Display and copy both hold up when the caller pipes yanker's stdout onward
  assert_equal 'the display copy survives a caller-side pipe' '2' \
    "$(yanker -o 'print -r -- a; print -r -- b' | wc -l | tr -d ' ')"
  assert_equal 'and the clipboard copy is complete' $'a\nb' "$(clipped)"
} always {
  rm -rf $tmpdir
  unset YANKER_CLIPBOARD
}
