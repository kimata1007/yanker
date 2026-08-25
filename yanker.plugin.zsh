#!/usr/bin/env zsh
#
# yanker — コマンド行とその出力を、まとめてクリップボードへコピーする
#
#   yanker pwd                          … 「$ pwd」と出力をコピー
#   yanker -o pwd                       … 出力だけをコピー
#   yanker ls -l | grep '\.zsh$'       … パイプもクォートせず書ける
#
# zsh は行を読んだ時点でパイプに分解してから各区間を起動するため、関数の $@ には
# 分解済みの1区間しか入らない。`yanker ls | grep foo` だと yanker に届くのは `ls` だけで、
# 出力も tee とクリップボードが消費しきって後段の grep には何も渡らない。
# そこで分解される前に行を書き換え、パイプごと yanker へ渡す。役割は4つに分かれている。
#
#   _yanker_clipboard_command  この環境で使えるクリップボードコマンドを選ぶ
#   _yanker_build_cmdline      引数から eval できるコマンド行を組み立てる
#   yanker                     コマンド行を eval し、画面とクリップボードへ流す
#   _yanker_accept_line        Enter を押した行を書き換えてから実行に回す（ZLE）
#
# 設定できる変数:
#   YANKER_CLIPBOARD         クリップボードへ書くコマンド。既定は環境から自動判定
#   YANKER_ALIAS             短縮名。既定は y。空文字にすると作らない
#   YANKER_BIND_ACCEPT_LINE  0 にすると ZLE 連携（パイプの自動クォート）を行わない

# 認識する呼び名。ZLE の行書き換えで先頭語を照合するのに使う
typeset -ga _yanker_names=(yanker)

# ---------------------------------------------------------------------------
# クリップボード
# ---------------------------------------------------------------------------

# この環境で使えるクリップボードコマンドを REPLY に入れる。無ければ 1 を返す。
# 中身はパイプの最終段で eval するので、`ssh host pbcopy` のような式も書ける
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
    # ${candidate%% *} は先頭語、すなわち実行ファイル名
    if (( ${+commands[${candidate%% *}]} )); then
      REPLY=$candidate
      return 0
    fi
  done

  REPLY=''
  return 1
}

# ---------------------------------------------------------------------------
# コマンド行の組み立て
# ---------------------------------------------------------------------------

# パイプやリダイレクトの演算子か。コマンド行を組み立てるときクォートせず残す語であり、
# 「素のパイプが書かれている」と判定する語でもあるので、1か所にまとめて持つ
_yanker_is_operator() {
  [[ $1 == ('|'|'|&'|'||'|'&&'|';'|'>'|'>>'|'<'|'2>'|'2>>'|'2>&1') ]]
}

# 引数から eval できるコマンド行を組み立て、REPLY に入れる
_yanker_build_cmdline() {
  # 引数が1つなら、sh -c と同じくシェルの文として扱う。ZLE の書き換えが吐くのも
  # この形なので、手で `yanker 'exit 3'` と書いたときと経路が揃う。
  # 「演算子を含むときだけ文として扱う」という判定にすると、`exit 3` が
  # コマンド名として扱われて command not found になり、挙動が読めなくなる
  if (( $# == 1 )); then
    REPLY=$1
    return
  fi

  # 語ごとに渡された場合。演算子はそのまま残し、それ以外はクォートして
  # eval での再解釈から守る
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
# 本体
# ---------------------------------------------------------------------------

# eval でユーザーのコマンドを走らせるので、ここでは emulate で options を変えない。
# 変えるとその設定が eval の中身にも及んでしまう
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
    print -ru2 -- 'yanker: クリップボードへ書くコマンドが見つかりません。YANKER_CLIPBOARD を設定してください'
    return 127
  fi
  clip=$REPLY

  local cmdline
  _yanker_build_cmdline "$@"
  cmdline=$REPLY

  # 画面へ出す先として yanker 自身の標準出力を複製しておく。/dev/tty を直に開くと
  # 端末が無い場面（スクリプト、CI、cron）で失敗するうえ、リダイレクト先を無視してしまう
  local visible
  exec {visible}>&1

  # 2>&1 は { } の外に置いて標準エラー出力もパイプへ入れる。`ls: no such file` の
  # ような失敗の理由や「該当なし」の知らせは標準エラー出力へ出るコマンドが多く、
  # 付けないと画面に出るだけでコピーから漏れる。共有したいのはその1行のことが多い。
  #
  # クリップボードはパイプの最終段に置く。プロセス置換 >(...) にするとシェルが
  # 完了を待たないため、書き終わる前に yanker が戻って中身が欠けることがある。
  #
  # pipestatus[1] は { } の終了ステータス、すなわち最後に置いた eval の結果を指す。
  # if で囲むと pipestatus が1要素に潰れてクリップボード側しか残らないので、分岐は中に置く
  {
    (( only_output )) || print -r -- "\$ $cmdline"
    eval "$cmdline"
  } 2>&1 | tee /dev/fd/$visible | { eval "$clip" } >/dev/null

  local ret=$pipestatus[1]
  exec {visible}>&-
  return $ret
}

# ---------------------------------------------------------------------------
# ZLE 連携
# ---------------------------------------------------------------------------

# Enter を押した行を見て、素のパイプが続く yanker の行だけを括り直し、REPLY に入れる。
# 判定と書き換えを ZLE から切り離してあるので、ウィジェット抜きで試せる
_yanker_rewrite_line() {
  emulate -L zsh -o extended_glob
  local line=$1
  REPLY=$line

  # (z) はシェルと同じ規則で行を語に割る。引用符の中のパイプは割れずに1語へ収まるため、
  # 素のパイプだけを見分けられる。すでに引用済みの行を二重に括らずに済む
  local -a words=(${(z)line})
  (( $#words )) || return

  # `(yanker|y)` のように必ず1グループにする。下の後方参照の番号がこの形に依存している。
  # REPLY には呼び出し元へ返す行が入っているので、ここで別の値を置かない
  local pattern="(${(j:|:)_yanker_names})"
  [[ ${words[1]} == ${~pattern} ]] || return

  local word
  for word in "${words[@]}"; do
    _yanker_is_operator "$word" || continue
    # コマンド名と -o は外に残し、それ以降を丸ごと1つの引数にまとめる
    [[ $line == (#b)([[:blank:]]#${~pattern}[[:blank:]]##(-o[[:blank:]]##)#)(*) ]] &&
      REPLY="${match[1]}${(qq)match[4]}"
    return
  done
}

# 退避した既存 accept-line の呼び名。他プラグインが未導入なら組み込みを指す。
# プラグインマネージャに二重に読み込まれても退避先を忘れないよう、既存値を残す
typeset -g _yanker_parent_widget
: ${_yanker_parent_widget:='.accept-line'}

_yanker_accept_line() {
  _yanker_rewrite_line "$BUFFER"
  BUFFER=$REPLY
  zle "$_yanker_parent_widget"
}

# accept-line に割り込む。zsh-syntax-highlighting など同じウィジェットを取る
# プラグインと共存させるため、既存の定義を別名で退避してから呼び継ぐ。
# zle -A で付けた別名は、その後 accept-line を差し替えても元の実装を指し続ける
_yanker_install_widget() {
  # プラグインマネージャが二重に source しても、二重に挟まない
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
# 読み込み時の設定
# ---------------------------------------------------------------------------

# 短縮名。すでに他人が使っている名前は奪わない。
# 二重に読み込まれると _yanker_names は (yanker) に戻るので、
# 前回自分が張った別名も名簿へ入れ直す。落とすと ZLE の行書き換えが効かなくなる
: ${YANKER_ALIAS=y}
if [[ -n $YANKER_ALIAS ]]; then
  if [[ ${aliases[$YANKER_ALIAS]-} == 'yanker' ]]; then
    _yanker_names+=("$YANKER_ALIAS")
  elif (( ! ${+aliases[$YANKER_ALIAS]} && ! ${+functions[$YANKER_ALIAS]} && ! ${+commands[$YANKER_ALIAS]} )); then
    alias -- "$YANKER_ALIAS=yanker"
    _yanker_names+=("$YANKER_ALIAS")
  fi
fi

# zle モジュールが無い環境（非対話シェル）では連携を諦め、関数だけ使えるようにする
if (( ${YANKER_BIND_ACCEPT_LINE:-1} )) && zmodload -e zsh/zle; then
  _yanker_install_widget
fi
