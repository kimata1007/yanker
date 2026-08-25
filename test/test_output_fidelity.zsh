# Nothing captured may go missing or be altered.
# Ordering is explicitly not guaranteed; see the note further down.
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

typeset tmpdir=$(mktemp -d)
typeset clipfile=$tmpdir/clip.txt
export YANKER_CLIPBOARD="cat > ${(q)clipfile}"

{
  yanker -o 'seq 1 50000' >/dev/null
  assert_equal 'does not drop lines from a large output' '50000' "$(wc -l < $clipfile | tr -d ' ')"
  assert_equal 'reaches the end of a large output'       '50000' "$(tail -1 $clipfile)"

  yanker -o 'printf abc' >/dev/null
  assert_equal 'does not append a newline that was not there' '616263' \
    "$(xxd -p $clipfile | tr -d '\n')"

  yanker -o 'printf "a\000b"' >/dev/null
  assert_equal 'passes NUL bytes through untouched' '610062' \
    "$(xxd -p $clipfile | tr -d '\n')"

  yanker -o 'print -r -- "   spaced   "' >/dev/null
  assert_equal 'preserves whitespace within a line' '2020207370616365642020200a' \
    "$(xxd -p $clipfile | tr -d '\n')"

  # A program that buffers stdout through stdio interleaves the two streams
  # differently than it would on a terminal. The order is not guaranteed, but
  # no line may be lost.
  if (( ${+commands[python3]} )); then
    yanker -o 'python3 -c "
import sys
print(\"out1\"); sys.stderr.write(\"err1\n\"); print(\"out2\"); sys.stderr.write(\"err2\n\")
"' >/dev/null
    assert_equal 'keeps all four lines even when stdout is buffered' \
      $'err1\nerr2\nout1\nout2' "$(sort $clipfile)"
  else
    print -r -- '  skip buffered-ordering check (no python3)'
  fi

  # stdout is a pipe, so tools that switch on isatty run in their
  # non-interactive mode. Same behaviour as cmd | tee.
  yanker -o '[[ -t 1 ]] && print -r -- tty || print -r -- pipe' >/dev/null
  assert_equal 'the command sees a pipe on stdout' 'pipe' "$(cat $clipfile)"
} always {
  rm -rf $tmpdir
  unset YANKER_CLIPBOARD
}
