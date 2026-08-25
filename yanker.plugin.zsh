#!/usr/bin/env zsh
#
# yanker — copy a command line and its output to the clipboard, together.
#
#   yanker pwd                     … copies "$ pwd" and the output
#   yanker -o pwd                  … copies the output only
#   yanker ls -l | grep '\.zsh$'   … pipes can be written unquoted
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
#
# Configuration:
#   YANKER_CLIPBOARD         command that reads the text on stdin (auto-detected)
#   YANKER_ALIAS             short alias, `y` by default; empty string skips it
#   YANKER_BIND_ACCEPT_LINE  set to 0 to leave `accept-line` untouched

# Names yanker answers to. The ZLE rewrite matches the first word against these.
typeset -ga _yanker_names=(yanker)

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
  local only_output=0
  if [[ $1 == -o ]]; then
    only_output=1
    shift
  fi

  if (( $# == 0 )); then
    print -ru2 -- 'usage: yanker [-o] <command...>'
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

  # Duplicate yanker's own stdout as the destination for the visible copy.
  # Opening /dev/tty directly fails where there is no terminal (scripts, CI,
  # cron) and ignores wherever the caller redirected stdout to.
  local visible
  exec {visible}>&1

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
  } 2>&1 | tee /dev/fd/$visible | { eval "$clip" } >/dev/null

  local ret=$pipestatus[1]
  exec {visible}>&-
  return $ret
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
