# ZLE ウィジェットの割り込み。他プラグインとの共存と二重読み込みを検証する。
# zle モジュールを明示的に読めば、端末が無くてもウィジェットの登録状態は調べられる

probe() {
  zsh -f -c "
    zmodload zsh/zle
    $1
    print -r -- \"accept-line=\${widgets[accept-line]} parent=\${_yanker_parent_widget} alias=\${widgets[_yanker_parent_accept_line]:-none}\"
  " 2>&1
}

typeset load="source ${(q)YANKER_ROOT}/yanker.plugin.zsh"

assert_equal '他プラグインが居なければ組み込みへ橋渡しする' \
  'accept-line=user:_yanker_accept_line parent=.accept-line alias=none' \
  "$(probe "$load")"

assert_equal '既存の accept-line は別名で退避して呼び継ぐ' \
  'accept-line=user:_yanker_accept_line parent=_yanker_parent_accept_line alias=user:prior' \
  "$(probe "prior() { : }; zle -N accept-line prior; $load")"

assert_equal '二重に読み込んでも自分自身を親にしない' \
  'accept-line=user:_yanker_accept_line parent=_yanker_parent_accept_line alias=user:prior' \
  "$(probe "prior() { : }; zle -N accept-line prior; $load; $load")"

assert_equal 'YANKER_BIND_ACCEPT_LINE=0 なら accept-line に触らない' \
  'accept-line=user:prior parent=.accept-line alias=none' \
  "$(probe "prior() { : }; zle -N accept-line prior; YANKER_BIND_ACCEPT_LINE=0; $load")"

# ウィジェット本体が BUFFER を書き換えてから親を呼ぶこと。
# 実行までは端末が要るので、ここでは呼び出しの流れだけを差し替えて確かめる
typeset trace=$(zsh -f -c "
  zmodload zsh/zle
  $load
  zle() { print -r -- \"zle:\$1\" }
  BUFFER='yanker ls | grep foo'
  _yanker_accept_line
  print -r -- \"BUFFER=\$BUFFER\"
" 2>&1)
assert_equal 'BUFFER を書き換えてから親ウィジェットを呼ぶ' \
  $'zle:.accept-line\nBUFFER=yanker \'ls | grep foo\'' "$trace"
