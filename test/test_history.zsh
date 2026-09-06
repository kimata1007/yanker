# The yank history: every copy is kept so an earlier one can be taken back out.
YANKER_BIND_ACCEPT_LINE=0 source $YANKER_ROOT/yanker.plugin.zsh

typeset histroot=$(mktemp -d)
typeset clipfile=$histroot/clip.txt
export YANKER_HISTFILE=$histroot/yanker_history
export YANKER_CLIPBOARD="cat > ${(q)clipfile}"

{
  # --- pushing -------------------------------------------------------------

  yanker 'echo one'   >/dev/null
  yanker 'echo two'   >/dev/null
  yanker 'echo three' >/dev/null

  _yanker_history_headers
  assert_equal 'keeps one record per copy' '3' "$#reply"

  # Index 1 is the newest, the same way `yanker -g 1` reads.
  assert_equal 'orders newest first' 'echo three' "${${reply[1]}#*;}"
  assert_equal 'and oldest last'     'echo one'   "${${reply[3]}#*;}"

  # --- taking an entry back out --------------------------------------------

  assert_equal 'prints an entry by index' $'$ echo two\ntwo' "$(yanker -p 2)"

  yanker -g 3 >/dev/null
  assert_equal 're-copies an entry by index' $'$ echo one\none' "$(<$clipfile)"

  yanker -p 99 >/dev/null 2>&1
  assert_status 'rejects an index past the end' '2' "$?"

  yanker -p 0 >/dev/null 2>&1
  assert_status 'rejects index zero' '2' "$?"

  yanker -p abc >/dev/null 2>&1
  assert_status 'rejects a non-numeric index' '2' "$?"

  # --- byte fidelity through the history -----------------------------------

  yanker -o 'printf "a\000b"' >/dev/null
  assert_equal 'stores NUL bytes untouched' '610062' \
    "$(yanker -p 1 | xxd -p | tr -d '\n')"

  yanker -o 'printf abc' >/dev/null
  assert_equal 'does not add a trailing newline' '616263' \
    "$(yanker -p 1 | xxd -p | tr -d '\n')"

  yanker -o 'print -r -- "   spaced   "' >/dev/null
  assert_equal 'preserves whitespace within a line' '2020207370616365642020200a' \
    "$(yanker -p 1 | xxd -p | tr -d '\n')"

  yanker -o 'seq 1 50000' >/dev/null
  assert_equal 'stores a large output whole' '50000' \
    "$(yanker -p 1 | wc -l | tr -d ' ')"
  assert_equal 'and reaches its end' '50000' "$(yanker -p 1 | tail -1)"

  # -o keeps the payload bare, but the command line is still recorded so the
  # listing and the picker have something to show.
  _yanker_history_headers
  assert_equal 'records the command line even with -o' 'seq 1 50000' "${${reply[1]}#*;}"
  assert_equal 'and leaves the payload without the $ line' '1' "$(yanker -p 1 | head -1)"

  # A newline in the command line would end the header early.
  yanker $'echo a\necho b' >/dev/null
  _yanker_history_headers
  assert_equal 'escapes a newline in the command line' 'echo a\necho b' \
    "${${reply[1]}#*;}"
  assert_equal 'and keeps the whole command line in the payload' \
    $'$ echo a\necho b\na\nb' "$(yanker -p 1)"

  # --- listing --------------------------------------------------------------

  assert_equal 'numbers the listing from the newest' '1' \
    "$(yanker -l | head -1 | awk '{print $1}')"
  assert_equal 'puts the command last in the listing' 'echo a\necho b' \
    "$(yanker -l | head -1 | sed 's/.*\$ //')"
  assert_equal 'lists every record' "$(_yanker_history_headers; print -r -- $#reply)" \
    "$(yanker -l | wc -l | tr -d ' ')"

  # --- retention ------------------------------------------------------------

  typeset -g YANKER_HISTSIZE=3
  yanker 'echo prune-me' >/dev/null
  _yanker_history_headers
  assert_equal 'never shows more than YANKER_HISTSIZE' '3' "$#reply"
  assert_equal 'keeping the newest' 'echo prune-me' "${${reply[1]}#*;}"
  assert_equal 'and the newest still reads back' $'$ echo prune-me\nprune-me' \
    "$(yanker -p 1)"

  # Rewriting the file is O(file), so it happens in batches: the file may run
  # past the limit by the slack before a trim, and never further.
  typeset -i i
  for (( i = 0; i < 30; i++ )); do yanker "echo fill$i" >/dev/null; done
  assert_equal 'the file is trimmed once the slack is used up' '1' \
    "$(( $(command grep -c '^: ' $YANKER_HISTFILE) <= 3 + 10 ))"
  _yanker_history_headers
  assert_equal 'and reads still stop at the limit' '3' "$#reply"
  assert_equal 'the newest survives the trim' 'echo fill29' "${${reply[1]}#*;}"
  unset YANKER_HISTSIZE

  # --- an outsized copy is recorded but not stored -------------------------

  YANKER_HISTMAXSIZE=64 yanker -o 'seq 1 500' >/dev/null
  assert_equal 'marks a copy too large to keep' '1' \
    "$(yanker -l | head -1 | grep -c '(not kept)')"
  yanker -p 1 >/dev/null 2>&1
  assert_status 'and says so rather than handing back nothing' '1' "$?"

  # --- permissions ----------------------------------------------------------

  # What matters is that nobody else can read the copies. Asserting the exact
  # mode would also pin down the umask, which is the caller's business.
  assert_equal 'keeps the history file unreadable to group and other' '0' \
    "$(zmodload zsh/stat; zstat -H st $YANKER_HISTFILE; printf '%o' $(( st[mode] & 077 )))"

  # --- clearing -------------------------------------------------------------

  yanker -c
  _yanker_history_headers
  assert_equal 'clears every record' '0' "$#reply"
  assert_equal 'and says so rather than printing nothing' '1' \
    "$(yanker -l >/dev/null 2>&1; print -r -- $?)"

  # --- opting out -----------------------------------------------------------

  YANKER_HISTORY=0 yanker 'echo untracked' >/dev/null
  _yanker_history_headers
  assert_equal 'records nothing when YANKER_HISTORY=0' '0' "$#reply"
  assert_equal 'but still copies' $'$ echo untracked\nuntracked' "$(<$clipfile)"

  # --- a history that cannot be written must not break the copy ------------

  typeset blocked=$histroot/blocked
  mkdir -p $blocked
  chmod 500 $blocked
  typeset out=$(zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    export YANKER_CLIPBOARD=cat
    export YANKER_HISTFILE=${(q)blocked}/sub/hist
    yanker 'echo still-works' 2>/dev/null
    print -r -- \"status=\$?\"
  ")
  chmod 700 $blocked
  assert_equal 'copies even when the history is unwritable' \
    $'$ echo still-works\nstill-works\nstatus=0' "$out"

  # --- the fzf picker ------------------------------------------------------
  # Driving fzf for real needs a terminal, so stand in for it with a script that
  # picks a known line. That still exercises the whole path: the lines handed to
  # fzf, the index carried in the hidden first field, and the re-copy.

  yanker -c
  yanker 'echo pick-a' >/dev/null
  yanker 'echo pick-b' >/dev/null

  typeset fakebin=$histroot/bin
  mkdir -p $fakebin
  # Choose the entry whose command line matches $PICK, the way a person would.
  print -r -- '#!/bin/sh
grep "\$ $PICK\$"' > $fakebin/fzf
  chmod +x $fakebin/fzf

  typeset picked=$(PATH=$fakebin:$PATH PICK='echo pick-a' zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    export YANKER_HISTFILE=${(q)YANKER_HISTFILE}
    export YANKER_CLIPBOARD='cat > ${(q)clipfile}'
    rehash
    yanker -s >/dev/null
    print -r -- \$?
  " 2>&1)
  assert_equal 'the picker re-copies the chosen entry' '0' "$picked"
  assert_equal 'and the choice is what lands on the clipboard' \
    $'$ echo pick-a\npick-a' "$(<$clipfile)"

  # Without fzf the picker says what to use instead, rather than failing blankly.
  # Swap PATH after the shell has started; emptying it beforehand would leave
  # zsh itself unfindable. Same technique as test_clipboard.zsh.
  typeset nofzf=$(mktemp -d)
  typeset msg=$(zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    export YANKER_HISTFILE=${(q)YANKER_HISTFILE}
    PATH=${(q)nofzf}; rehash
    yanker -s 2>&1 >/dev/null
    print -r -- \$?
  ")
  rmdir $nofzf
  assert_equal 'says what to use when fzf is absent' \
    'yanker: -s needs fzf; use `yanker -l` then `yanker -g N`
127' "$msg"

  # --- a shell must count what is already in the file ----------------------
  # `(( x++ ))` creates the variable, so seeding the count after the first
  # increment never happens. A shell that made only a few copies would then
  # never trim, and the file would grow across sessions without bound.

  yanker -c
  unset _yanker_hist_count
  typeset -g YANKER_HISTSIZE=5
  typeset -i n
  for (( n = 0; n < 20; n++ )); do yanker "echo seed$n" >/dev/null; done

  # Five separate shells, each doing too few copies to reach the limit on its
  # own. Without the seeding this leaves 24 records behind.
  for (( n = 0; n < 5; n++ )); do
    zsh -f -c "
      source ${(q)YANKER_ROOT}/yanker.plugin.zsh
      export YANKER_HISTFILE=${(q)YANKER_HISTFILE}
      export YANKER_CLIPBOARD=cat
      export YANKER_HISTSIZE=5
      for i in 1 2 3; do yanker \"echo fresh\$i\" >/dev/null; done
    " >/dev/null 2>&1
  done
  assert_equal 'a fresh shell counts the records already in the file' '1' \
    "$(( $(command grep -c '^: ' $YANKER_HISTFILE) <= 5 + 5 ))"
  unset YANKER_HISTSIZE
  unset _yanker_hist_count

  # --- copies running at the same time ------------------------------------
  # Subshells share $$, so a spool named after it would be shared too, and the
  # pruner renames the history file out from under any lock taken on it. Both
  # show up here as records that interleave or go missing.

  yanker -c
  unset _yanker_hist_count
  zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    export YANKER_HISTFILE=${(q)YANKER_HISTFILE}
    export YANKER_CLIPBOARD=cat
    for i in {1..12}; do yanker \"echo concurrent\$i\" >/dev/null & done
    wait
  " >/dev/null 2>&1
  assert_equal 'concurrent copies each leave one record' '12' \
    "$(command grep -c '^: ' $YANKER_HISTFILE)"

  # Each record's header must still describe its own payload.
  check_records() {
    typeset -i bad=0 idx=0 total=$1
    typeset -a payload
    for (( idx = 1; idx <= total; idx++ )); do
      payload=(${(f)"$(yanker -p $idx 2>/dev/null)"})
      [[ $#payload == 2 && ${payload[1]} == "\$ echo ${payload[2]}" ]] || (( bad++ ))
    done
    print -r -- $bad
  }
  assert_equal 'and none of them interleaved' '0' "$(check_records 12)"
  unset _yanker_hist_count

  # Again with a limit small enough that trimming runs *during* the burst. That
  # is what exercises the rename: the pruner replaces the history file, so a
  # lock taken on the file itself would stop holding anyone back.
  yanker -c
  unset _yanker_hist_count
  typeset -g YANKER_HISTSIZE=4
  zsh -f -c "
    source ${(q)YANKER_ROOT}/yanker.plugin.zsh
    export YANKER_HISTFILE=${(q)YANKER_HISTFILE}
    export YANKER_CLIPBOARD=cat
    export YANKER_HISTSIZE=4
    for i in {1..16}; do yanker \"echo racing\$i\" >/dev/null & done
    wait
  " >/dev/null 2>&1

  assert_equal 'trimming under concurrency stays within the limit and slack' '1' \
    "$(( $(command grep -c '^: ' $YANKER_HISTFILE) <= 4 + 4 ))"
  _yanker_history_headers
  assert_equal 'and every surviving record still reads back whole' '0' \
    "$(check_records $#reply)"
  unset YANKER_HISTSIZE
  unset _yanker_hist_count
  unfunction check_records

  # --- the file stays greppable for command lines, like .zsh_history --------

  yanker 'git status -sb' >/dev/null
  assert_equal 'command lines are findable in the file' '1' \
    "$(grep -c '^: .*;git status -sb$' $YANKER_HISTFILE)"
} always {
  rm -rf $histroot
}
