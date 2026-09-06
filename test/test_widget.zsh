# Hooking the ZLE widget: coexistence with other plugins, and double loading.
# Loading the zle module explicitly makes the widget registry inspectable even
# without a terminal.

probe() {
  zsh -f -c "
    zmodload zsh/zle
    $1
    print -r -- \"accept-line=\${widgets[accept-line]} parent=\${_yanker_parent_widget} alias=\${widgets[_yanker_parent_accept_line]:-none}\"
  " 2>&1
}

typeset load="source ${(q)YANKER_ROOT}/yanker.plugin.zsh"

assert_equal 'delegates to the builtin when no other plugin is present' \
  'accept-line=user:_yanker_accept_line parent=.accept-line alias=none' \
  "$(probe "$load")"

assert_equal 'saves an existing accept-line and delegates to it' \
  'accept-line=user:_yanker_accept_line parent=_yanker_parent_accept_line alias=user:prior' \
  "$(probe "prior() { : }; zle -N accept-line prior; $load")"

assert_equal 'a second load does not make yanker its own parent' \
  'accept-line=user:_yanker_accept_line parent=_yanker_parent_accept_line alias=user:prior' \
  "$(probe "prior() { : }; zle -N accept-line prior; $load; $load")"

assert_equal 'YANKER_BIND_ACCEPT_LINE=0 leaves accept-line untouched' \
  'accept-line=user:prior parent=.accept-line alias=none' \
  "$(probe "prior() { : }; zle -N accept-line prior; YANKER_BIND_ACCEPT_LINE=0; $load")"

# The widget must rewrite BUFFER before calling its parent. Actually running it
# needs a terminal, so stub out `zle` and check the call sequence instead.
typeset trace=$(zsh -f -c "
  zmodload zsh/zle
  $load
  zle() { print -r -- \"zle:\$1\" }
  BUFFER='yanker ls | grep foo'
  _yanker_accept_line
  print -r -- \"BUFFER=\$BUFFER\"
" 2>&1)
assert_equal 'rewrites BUFFER before calling the parent widget' \
  $'zle:.accept-line\nBUFFER=yanker \'ls | grep foo\'' "$trace"

# --- the fzf picker key ----------------------------------------------------
# Same trick: load zle explicitly so bindkey is inspectable without a terminal.

key_probe() {
  zsh -f -c "
    zmodload zsh/zle
    $1
    print -r -- \"\${\${(z)\"\$(bindkey -- ${2:-'^V'})\"}[2]}\"
  " 2>&1
}

assert_equal 'claims ^V while it still holds a builtin widget' \
  'yanker-pick' "$(key_probe "$load")"

assert_equal 'leaves ^V alone when someone else bound it' \
  'mine' "$(key_probe "mine() { : }; zle -N mine; bindkey -- '^V' mine; $load")"

assert_equal 'a second load keeps the picker bound' \
  'yanker-pick' "$(key_probe "$load; $load")"

assert_equal "YANKER_PICK_KEY='' leaves ^V untouched" \
  'quoted-insert' "$(key_probe "YANKER_PICK_KEY=''; $load")"

assert_equal 'YANKER_PICK_KEY chooses a different key' \
  'yanker-pick' "$(key_probe "YANKER_PICK_KEY='^X^Y'; $load" "'^X^Y'")"

assert_equal 'and then leaves ^V for zsh' \
  'quoted-insert' "$(key_probe "YANKER_PICK_KEY='^X^Y'; $load")"
