#!/usr/bin/env zsh
#
# yanker — copy a command line and its output to the clipboard, together.
#
#   yanker pwd                     … copies "$ pwd" and the output
#   yanker -o pwd                  … copies the output only
#   yanker ls -l | grep '\.zsh$'   … pipes can be written unquoted
#   yanker -l / -g N / -p N        … list, re-copy, or print an earlier copy
#   yanker -s                      … pick an earlier copy with fzf (also ^V)
#
# zsh splits a line into pipeline segments before running anything, so a plain
# function only ever sees its own segment: in `yanker ls | grep foo`, yanker
# receives just `ls`, and tee plus the clipboard consume the stream so `grep`
# gets nothing. The fix is to rewrite the line before zsh splits it, handing the
# whole pipeline to yanker as one argument. Four pieces do the work:
#
#   _yanker_clipboard_command  pick a clipboard command available on this host
#   _yanker_build_cmdline      turn the arguments into an evaluatable command line
#   yanker                     eval it, then stream the result to screen and clipboard
#   _yanker_accept_line        rewrite the line the user pressed Enter on (ZLE)
#   _yanker_history_*          keep past copies so an earlier one can be reused
#
# Configuration:
#   YANKER_CLIPBOARD         command that reads the text on stdin (auto-detected)
#   YANKER_ALIAS             short alias, `y` by default; empty string skips it
#   YANKER_BIND_ACCEPT_LINE  set to 0 to leave `accept-line` untouched
#   YANKER_HISTORY           set to 0 to keep no history at all
#   YANKER_HISTFILE          history path, ~/.yanker_history by default
#   YANKER_HISTSIZE          how many copies to keep, 20 by default
#   YANKER_PICK_KEY          key that opens the fzf picker, ^V by default

# Names yanker answers to. The ZLE rewrite matches the first word against these.
typeset -ga _yanker_names=(yanker)

# Path to this file. The fzf preview runs in a shell of fzf's making, so it has
# to re-source the plugin rather than call back into the current shell.
typeset -g _yanker_source=${${(%):-%x}:A}

# ---------------------------------------------------------------------------
# Clipboard
# ---------------------------------------------------------------------------

# Put a usable clipboard command in REPLY, or return 1 if there is none.
# The value is eval'd as the last stage of a pipeline, so an expression such as
# `ssh host pbcopy` works as well as a bare command name.
_yanker_clipboard_command() {
  if [[ -n ${YANKER_CLIPBOARD-} ]]; then
    REPLY=$YANKER_CLIPBOARD
    return 0
  fi

  local candidate
  for candidate in \
    'pbcopy' \
    'wl-copy' \
    'xclip -selection clipboard' \
    'xsel --clipboard --input' \
    'clip.exe'
  do
    # ${candidate%% *} is the first word, i.e. the executable name
    if (( ${+commands[${candidate%% *}]} )); then
      REPLY=$candidate
      return 0
    fi
  done

  REPLY=''
  return 1
}

# ---------------------------------------------------------------------------
# Building the command line
# ---------------------------------------------------------------------------

# Is this word a pipe or redirection operator? Such words are left unquoted when
# assembling a command line, and they are also what marks a line as containing an
# unquoted pipe, so both callers share this one list.
_yanker_is_operator() {
  [[ $1 == ('|'|'|&'|'||'|'&&'|';'|'>'|'>>'|'<'|'2>'|'2>>'|'2>&1') ]]
}

# Build an evaluatable command line from the arguments and put it in REPLY.
_yanker_build_cmdline() {
  # A single argument is shell source, the same way `sh -c` treats it. The ZLE
  # rewrite emits exactly this shape, so typing `yanker 'exit 3'` by hand takes
  # the same path. Deciding by "only treat it as source when it contains an
  # operator" would make `exit 3` a command name and fail with command not found,
  # which is hard to predict from the outside.
  if (( $# == 1 )); then
    REPLY=$1
    return
  fi

  # Word-by-word invocation: keep operators as operators and quote everything
  # else so eval cannot reinterpret it.
  local word
  local -a parts=()
  for word in "$@"; do
    if _yanker_is_operator "$word"; then
      parts+=("$word")
    else
      parts+=("${(q-)word}")
    fi
  done
  REPLY="${(j: :)parts}"
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

# This function eval's the user's command, so it deliberately does not call
# `emulate` — any option change here would leak into the evaluated code.
yanker() {
  # The history subcommands come first: they take an index, not a command line,
  # and none of the pipeline below applies to them.
  case ${1-} in
    -l|--list)   _yanker_history_list;              return $? ;;
    -s|--select) _yanker_history_select;            return $? ;;
    -c|--clear)  _yanker_history_clear;             return $? ;;
    -p|--print)  _yanker_history_emit   "${2-}";    return $? ;;
    -g|--get)    _yanker_history_recopy "${2-}";    return $? ;;
  esac

  local only_output=0
  if [[ $1 == -o ]]; then
    only_output=1
    shift
  fi

  if (( $# == 0 )); then
    print -ru2 -- 'usage: yanker [-o] <command...>
       yanker -l | -s | -c | -p <n> | -g <n>'
    return 2
  fi

  local clip
  if ! _yanker_clipboard_command; then
    print -ru2 -- 'yanker: no clipboard command found; set YANKER_CLIPBOARD'
    return 127
  fi
  clip=$REPLY

  local cmdline
  _yanker_build_cmdline "$@"
  cmdline=$REPLY

  # Spool the payload so the history can be appended once the copy is done.
  # tee takes the extra target for free, so capturing it costs no new process.
  # A history that cannot be written is never worth failing a copy over — the
  # clipboard is the point of the command — so an unusable spool just disables
  # the history for this call.
  local spool=''
  if _yanker_histfile && _yanker_history_touch "$REPLY" && _yanker_spool_dir; then
    spool=$REPLY/spool.$$
  fi

  # Duplicate yanker's own stdout as the destination for the visible copy.
  # Opening /dev/tty directly fails where there is no terminal (scripts, CI,
  # cron) and ignores wherever the caller redirected stdout to.
  local visible
  exec {visible}>&1

  # tee writes the visible copy and, when the history is on, the spool as well.
  local -a targets=(/dev/fd/$visible)
  [[ -n $spool ]] && targets+=("$spool")

  # 2>&1 sits outside the { } so stderr joins the pipeline too. Failure reasons
  # and "nothing matched" notices go to stderr for most commands; without this
  # they appear on screen but never reach the clipboard, and they are usually
  # the one line worth sharing.
  #
  # The clipboard is the final pipeline stage on purpose. As a process
  # substitution >(...) the shell would not wait for it, and yanker could return
  # before the text was fully written.
  #
  # pipestatus[1] is the exit status of the { } block, i.e. of the eval inside.
  # Wrapping this in an `if` collapses pipestatus to a single element and leaves
  # only the clipboard's status, so the branch lives inside the block instead.
  {
    (( only_output )) || print -r -- "\$ $cmdline"
    eval "$cmdline"
  } 2>&1 | tee "${targets[@]}" | { eval "$clip" } >/dev/null

  # Read pipestatus before running anything else; the next command replaces it.
  local ret=$pipestatus[1]
  exec {visible}>&-

  if [[ -n $spool ]]; then
    _yanker_history_append "$cmdline" "$spool"
    rm -f -- "$spool" 2>/dev/null
  fi

  return $ret
}

# ---------------------------------------------------------------------------
# Yank history
# ---------------------------------------------------------------------------
#
# Every copy is appended to a history file, so an earlier one can be taken back
# out instead of being lost to the next copy. The file sits beside the shell's
# own history and follows the same conventions: one path under $HOME, private
# to its owner, oldest record first.
#
# A payload is arbitrary bytes — NUL included, with no guaranteed trailing
# newline; test_output_fidelity.zsh pins that down — so it cannot be stored
# verbatim in a line-oriented file. Each record is a header and its payload:
#
#   : <epoch>:<bytes>:<flags>;<command line>
#   <base64 of the payload, wrapped>
#
# Only the header starts with ': ', and base64 output always starts with an
# alphanumeric, so a record needs no other delimiter. That keeps the file
# greppable for command lines the way .zsh_history is, while still handing back
# the payload byte for byte.
#
# Indices count from the newest: `yanker -g 1` is the copy you just made.
#
# Cost matters here, because this runs on every copy. Sizes come from zstat,
# times from EPOCHSECONDS, and formatting from `printf -v` and `strftime -s`,
# none of which fork. base64 is the only process a copy adds.

# Builtin mkdir/rm, so bookkeeping costs no extra processes per copy.
zmodload -F zsh/files b:mkdir b:rm 2>/dev/null
zmodload zsh/datetime 2>/dev/null
zmodload zsh/system 2>/dev/null
zmodload zsh/stat 2>/dev/null

# Put the base64 decode flag in REPLY. GNU coreutils accepts only -d, older
# macOS only -D, and current FreeBSD/macOS both; probe once and remember.
_yanker_base64_flag() {
  if [[ -z ${_yanker_b64_flag-} ]]; then
    if print -n '' | base64 -d >/dev/null 2>&1; then
      typeset -g _yanker_b64_flag='-d'
    else
      typeset -g _yanker_b64_flag='-D'
    fi
  fi
  REPLY=$_yanker_b64_flag
}

# Put the history file path in REPLY, or return 1 when history is switched off.
_yanker_histfile() {
  REPLY=''
  (( ${YANKER_HISTORY:-1} )) || return 1
  REPLY=${YANKER_HISTFILE:-$HOME/.yanker_history}
  [[ -n $REPLY ]]
}

# How many copies to keep, and how far past that the file may drift before it
# is worth rewriting. Readers never show more than the limit either way.
_yanker_history_limit() {
  REPLY=${YANKER_HISTSIZE:-20}
  [[ $REPLY == <-> ]] || REPLY=20
}

# Make sure the history file exists and is private. Returns 1 when the path
# cannot be used, which callers treat as "skip the history", never as an error
# worth failing a copy over.
_yanker_history_touch() {
  local file=$1
  if [[ ! -e $file ]]; then
    mkdir -p -- "${file:h}" 2>/dev/null || return 1
    # Create it private from the outset. Widening first and narrowing with
    # chmod afterwards leaves a window where the copies are world-readable.
    ( umask 077; : >| "$file" ) 2>/dev/null || return 1
  fi
  [[ -f $file && -w $file ]] || return 1
  return 0
}

# Header lines, newest first, into `reply`, at most YANKER_HISTSIZE of them.
# Each element is the record's position from the start of the file, a TAB, then
# the header without its ': ' marker.
_yanker_history_headers() {
  reply=()
  local file
  _yanker_histfile || return 1
  file=$REPLY
  [[ -r $file ]] || return 1
  _yanker_history_limit
  # Reversing inside awk keeps this to one process and avoids `tail -r` (BSD)
  # versus `tac` (GNU). The file may hold a few more records than the limit;
  # pruning is amortised, so the cap is applied here as well.
  reply=(${(f)"$(command awk -v keep="$REPLY" '
    /^: / { n++; h[n] = sprintf("%d\t%s", n, substr($0, 3)) }
    END   { for (i = n; i >= 1 && n - i < keep; i--) print h[i] }
  ' "$file" 2>/dev/null)"})
  (( $#reply ))
}

# Resolve a user-facing index (1 = newest) to a record position from the start
# of the file, in REPLY. Complains and returns 2 when it does not name a record.
_yanker_history_resolve() {
  local want=$1
  REPLY=''
  if [[ -z $want || $want != <-> ]]; then
    print -ru2 -- 'yanker: expected a history index, as in `yanker -g 1`'
    return 2
  fi
  local -a headers
  _yanker_history_headers && headers=("${reply[@]}") || headers=()
  if (( want < 1 || want > $#headers )); then
    print -ru2 -- "yanker: no history entry $want (have ${#headers})"
    return 2
  fi
  REPLY=${headers[want]%%$'\t'*}
  _yanker_history_flags=${${headers[want]#*$'\t'}%%;*}
  _yanker_history_flags=${_yanker_history_flags##*:}
  return 0
}

# Write the payload of one entry to stdout, byte for byte. The bytes never pass
# through a shell variable, which would eat NULs and the trailing newline.
_yanker_history_emit() {
  local pos flag file
  local _yanker_history_flags=''
  _yanker_history_resolve "${1-}" || return $?
  pos=$REPLY

  if [[ $_yanker_history_flags == big ]]; then
    print -ru2 -- "yanker: entry $1 was too large to keep; raise YANKER_HISTMAXSIZE"
    return 1
  fi

  _yanker_histfile || return 1
  file=$REPLY
  _yanker_base64_flag
  flag=$REPLY
  command awk -v target="$pos" '
    /^: / { rec++; next }
    rec == target { print }
  ' "$file" | base64 $flag
}

# Put one entry back on the clipboard.
_yanker_history_recopy() {
  local clip
  _yanker_history_resolve "${1-}" || return $?
  if ! _yanker_clipboard_command; then
    print -ru2 -- 'yanker: no clipboard command found; set YANKER_CLIPBOARD'
    return 127
  fi
  clip=$REPLY
  _yanker_history_emit "$1" | { eval "$clip" } >/dev/null
  return $pipestatus[1]
}

# Human-readable byte count in REPLY. printf -v assigns without forking.
_yanker_history_size() {
  local -i b=$1
  if (( b < 1024 )); then
    REPLY="${b} B"
  elif (( b < 1048576 )); then
    printf -v REPLY '%.1f KB' $(( b / 1024.0 ))
  else
    printf -v REPLY '%.1f MB' $(( b / 1048576.0 ))
  fi
}

# One display line per entry into `reply`: the index, a TAB, then the columns.
# The command line comes last so a command full of spaces cannot push the other
# columns around.
_yanker_history_lines() {
  local -a headers
  reply=()
  _yanker_history_headers || return 1
  headers=("${reply[@]}")
  reply=()

  local -i i=0
  local h meta cmd when size note line
  for h in "${headers[@]}"; do
    (( i++ ))
    h=${h#*$'\t'}
    meta=${h%%;*}
    cmd=${h#*;}
    strftime -s when '%m-%d %H:%M' "${meta%%:*}" 2>/dev/null || when='??-?? ??:??'
    _yanker_history_size "${${meta#*:}%%:*}"
    size=$REPLY
    [[ ${meta##*:} == big ]] && note=' (not kept)' || note=''
    printf -v line '%3d  %s  %9s%s  $ %s' "$i" "$when" "$size" "$note" "$cmd"
    reply+=("${i}"$'\t'"$line")
  done
  return 0
}

# `yanker -l`
_yanker_history_list() {
  if ! _yanker_history_lines; then
    print -ru2 -- 'yanker: no history yet'
    return 1
  fi
  local line
  for line in "${reply[@]}"; do
    print -r -- "${line#*$'\t'}"
  done
}

# `yanker -c`
_yanker_history_clear() {
  local file
  _yanker_histfile || return 0
  file=$REPLY
  [[ -e $file ]] || return 0
  : >| "$file" 2>/dev/null || {
    print -ru2 -- "yanker: cannot clear $file"
    return 1
  }
  typeset -g _yanker_hist_count=0
  return 0
}

# `yanker -s` — pick an entry with fzf and put it back on the clipboard.
# The preview runs in a shell of fzf's making, so it re-sources this file rather
# than calling back into the current shell's functions.
_yanker_history_select() {
  if (( ! ${+commands[fzf]} )); then
    print -ru2 -- 'yanker: -s needs fzf; use `yanker -l` then `yanker -g N`'
    return 127
  fi
  if ! _yanker_history_lines; then
    print -ru2 -- 'yanker: no history yet'
    return 1
  fi

  local file
  _yanker_histfile && file=$REPLY || file=''

  local preview="YANKER_HISTFILE=${(q)file} zsh -f -c 'source ${(q)_yanker_source}; yanker -p {1}' 2>&1 | head -500"
  local pick
  pick=$(print -rl -- "${reply[@]}" | command fzf \
    --no-sort --no-multi --delimiter=$'\t' --with-nth='2..' \
    --prompt='yank> ' --height='60%' --border --preview-window='right:60%' \
    --preview="$preview") || return $?

  [[ -n $pick ]] || return 1
  _yanker_history_recopy "${pick%%$'\t'*}"
}

# Append one record. $1 is the command line, $2 a file holding the raw payload.
# Locking matters: the header and the payload are two writes, and a second shell
# appending between them would interleave into an unreadable record.
_yanker_history_append() {
  local cmdline=$1 spool=$2 file
  _yanker_histfile || return 0
  file=$REPLY
  _yanker_history_touch "$file" || return 1

  # A newline would end the header early, so escape it the way -l shows it back.
  local label=${cmdline//\\/\\\\}
  label=${label//$'\n'/\\n}

  # zstat is a builtin, so the size costs no process.
  local -a st
  zstat -A st +size "$spool" 2>/dev/null || st=(0)
  local -i bytes=${st[1]:-0}

  # One enormous copy would otherwise sit in the history until twenty more push
  # it out. Record that it happened, but leave the bytes out of the file.
  local -i cap=${YANKER_HISTMAXSIZE:-1048576}
  local flags=''
  (( cap > 0 && bytes > cap )) && flags='big'

  local lockfd=''
  zsystem flock -t 10 -f lockfd "$file" 2>/dev/null

  {
    printf ': %d:%d:%s;%s\n' "${EPOCHSECONDS:-0}" "$bytes" "$flags" "$label"
    [[ -n $flags ]] || base64 < "$spool"
  } >> "$file"
  local -i ret=$?

  (( _yanker_hist_count++ ))
  _yanker_history_prune "$file"
  [[ -n $lockfd ]] && zsystem flock -u $lockfd 2>/dev/null
  return $ret
}

# Trim the file back to YANKER_HISTSIZE. Rewriting is O(file), so it runs in
# batches rather than on every copy: the file is allowed to drift past the limit
# by a margin first, and readers cap what they show at the limit regardless.
#
# The record count is remembered per shell to keep the common case free of any
# process at all. A second shell appending makes that count low, which only
# delays a trim — it never loses a record, and the next shell to start counts
# afresh. Called with the append lock already held.
_yanker_history_prune() {
  local file=$1
  _yanker_history_limit
  local -i limit=$REPLY
  (( limit > 0 )) || return 0
  local -i slack=$(( limit < 20 ? 10 : limit / 2 ))

  if [[ -z ${_yanker_hist_count-} ]] || (( _yanker_hist_count < 0 )); then
    typeset -g _yanker_hist_count=$(command grep -c '^: ' "$file" 2>/dev/null)
  fi
  (( _yanker_hist_count > limit + slack )) || return 0

  local -i total=$(command grep -c '^: ' "$file" 2>/dev/null)
  typeset -g _yanker_hist_count=$total
  (( total > limit )) || return 0

  local tmp=$file.$$
  ( umask 077
    command awk -v drop=$(( total - limit )) '
      /^: / { rec++ }
      rec > drop
    ' "$file" > "$tmp"
  ) 2>/dev/null || { rm -f -- "$tmp" 2>/dev/null; return 1 }
  command mv -- "$tmp" "$file" 2>/dev/null || { rm -f -- "$tmp" 2>/dev/null; return 1 }
  typeset -g _yanker_hist_count=$limit
  return 0
}

# A private spool directory for this user, made once per shell. tee writes the
# payload here during the copy, which costs no extra process, and the record is
# appended afterwards.
_yanker_spool_dir() {
  if [[ -n ${_yanker_spool-} && -d ${_yanker_spool} ]]; then
    REPLY=$_yanker_spool
    return 0
  fi
  local d=${TMPDIR:-/tmp}/yanker-${UID}
  mkdir -p -m 700 -- "$d" 2>/dev/null
  # Refuse anything we do not own outright; a shared /tmp is not trustworthy.
  [[ -d $d && -O $d && ! -L $d ]] || return 1
  typeset -g _yanker_spool=$d
  REPLY=$d
  return 0
}

# ---------------------------------------------------------------------------
# ZLE integration
# ---------------------------------------------------------------------------

# Inspect the line the user pressed Enter on and, when it is a yanker line
# followed by an unquoted pipe, re-quote it into REPLY. Keeping the decision and
# the rewrite outside the widget makes both testable without ZLE.
_yanker_rewrite_line() {
  emulate -L zsh -o extended_glob
  local line=$1
  REPLY=$line

  # (z) splits the line into words using the shell's own rules. A pipe inside
  # quotes stays within a single word, so only unquoted pipes are visible here,
  # and an already-quoted line does not get wrapped a second time.
  local -a words=(${(z)line})
  (( $#words )) || return

  # Always exactly one group, as in `(yanker|y)`; the backreference numbering
  # below depends on that shape. REPLY already holds the line to return to the
  # caller, so nothing else may be stored in it here.
  local pattern="(${(j:|:)_yanker_names})"
  [[ ${words[1]} == ${~pattern} ]] || return

  local word
  for word in "${words[@]}"; do
    _yanker_is_operator "$word" || continue
    # Leave the command name and -o outside; fold everything after them into a
    # single argument.
    [[ $line == (#b)([[:blank:]]#${~pattern}[[:blank:]]##(-o[[:blank:]]##)#)(*) ]] &&
      REPLY="${match[1]}${(qq)match[4]}"
    return
  done
}

# Name of the saved accept-line widget; the builtin when no other plugin has one.
# Keep any existing value so a second source does not forget where to delegate.
typeset -g _yanker_parent_widget
: ${_yanker_parent_widget:='.accept-line'}

_yanker_accept_line() {
  _yanker_rewrite_line "$BUFFER"
  BUFFER=$REPLY
  zle "$_yanker_parent_widget"
}

# Open the fzf picker from the keyboard. fzf draws on /dev/tty of its own
# accord, so a widget only has to redraw the prompt afterwards.
_yanker_pick_widget() {
  _yanker_history_select
  zle reset-prompt
}

# Bind the picker key, by default ^V. The key is only claimed while it still
# holds one of zsh's builtin widgets: anyone who bound it themselves meant to,
# the same way the `y` alias never overwrites an existing name.
_yanker_install_pick_key() {
  local key=${YANKER_PICK_KEY-'^V'}
  [[ -n $key ]] || return 0

  zle -N yanker-pick _yanker_pick_widget

  local -a bound=(${(z)"$(bindkey -- $key 2>/dev/null)"})
  local current=${bound[2]-}
  if [[ -n $current && $current != undefined-key && ${widgets[$current]-} != builtin ]]; then
    return 0
  fi
  bindkey -- $key yanker-pick
}

# Hook accept-line. To coexist with plugins that claim the same widget, such as
# zsh-syntax-highlighting, save the existing definition under another name and
# delegate to it. An alias made with `zle -A` keeps pointing at the original
# implementation even after accept-line itself is replaced.
_yanker_install_widget() {
  # Do not wrap twice when a plugin manager sources this file more than once.
  [[ ${widgets[accept-line]} == 'user:_yanker_accept_line' ]] && return 0

  if [[ ${widgets[accept-line]} == user:* ]]; then
    zle -A accept-line _yanker_parent_accept_line
    _yanker_parent_widget='_yanker_parent_accept_line'
  else
    _yanker_parent_widget='.accept-line'
  fi

  zle -N accept-line _yanker_accept_line
}

# ---------------------------------------------------------------------------
# Setup on load
# ---------------------------------------------------------------------------

# Short alias, never stealing a name someone else already uses.
# A second source resets _yanker_names to (yanker), so an alias installed by an
# earlier load has to be re-registered; dropping it would break the ZLE rewrite.
: ${YANKER_ALIAS=y}
if [[ -n $YANKER_ALIAS ]]; then
  if [[ ${aliases[$YANKER_ALIAS]-} == 'yanker' ]]; then
    _yanker_names+=("$YANKER_ALIAS")
  elif (( ! ${+aliases[$YANKER_ALIAS]} && ! ${+functions[$YANKER_ALIAS]} && ! ${+commands[$YANKER_ALIAS]} )); then
    alias -- "$YANKER_ALIAS=yanker"
    _yanker_names+=("$YANKER_ALIAS")
  fi
fi

# Where the zle module is absent (a non-interactive shell) skip the integration
# and leave yanker usable as a plain function.
if (( ${YANKER_BIND_ACCEPT_LINE:-1} )) && zmodload -e zsh/zle; then
  _yanker_install_widget
fi

# The picker key is independent of the accept-line rewrite, so it is installed
# on its own terms; YANKER_PICK_KEY='' skips it.
if zmodload -e zsh/zle; then
  _yanker_install_pick_key
fi
