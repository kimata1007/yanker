# Integration test over a pty. Whether the line actually gets rewritten when
# Enter is pressed cannot be told from the widget registry alone, so it is
# checked here for real.
if (( ! ${+commands[expect]} )); then
  print -r -- '  skip pty tests (expect not installed)'
  return 0
fi

# Type one line and return what landed on the clipboard.
# The second argument is setup to run before the plugin is sourced.
type_line() {
  local line=$1 extra=$2
  local dir=$(mktemp -d)
  {
    expect $YANKER_ROOT/test/integration/accept_line.exp \
      "$YANKER_ROOT/yanker.plugin.zsh" "$dir/clip.txt" "$line" "$extra" > $dir/log 2>&1
    # On failure, dump the terminal transcript so the cause is visible in CI
    if [[ ! -s $dir/clip.txt ]]; then
      print -ru2 -- '       --- expect transcript ---'
      sed 's/^/       /' $dir/log >&2
    fi
    cat $dir/clip.txt 2>/dev/null
  } always {
    rm -rf $dir
  }
}

assert_equal 'pressing Enter hands the whole pipeline to yanker' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'yanker echo hello | tr a-z A-Z')"

assert_equal 'the short alias takes the same path' \
  $'$ echo hello | tr a-z A-Z\nHELLO' \
  "$(type_line 'y echo hello | tr a-z A-Z')"

assert_equal 'a message on stderr is copied too' \
  $'$ print -ru2 -- no-such-file\nno-such-file' \
  "$(type_line "yanker 'print -ru2 -- no-such-file'")"

# With the ZLE integration disabled. Driving this by configuration rather than
# by terminal type keeps it deterministic: TERM=dumb behaves differently on
# macOS and Linux.
assert_equal 'works as a plain function when the ZLE hook is off' \
  $'$ echo hello\nhello' \
  "$(type_line 'yanker echo hello | tr a-z A-Z' 'YANKER_BIND_ACCEPT_LINE=0')"
