# yanker

Copy a command **and its output** to the clipboard, in one keystroke's worth of typing.

```console
$ yanker ls
$ ls
LICENSE
README.md
test
yanker.plugin.zsh
```

The command and its output are now on your clipboard together — ready to paste
into a pull request, an issue, or a chat. No re-typing the command, no
selecting text with the mouse.

## Why

Pasting terminal output into a conversation usually means pasting output
*without* the command that produced it, and readers are left guessing. Selecting
with the mouse fixes that but breaks on scrollback and wrapped lines.

`yanker` prefixes the output with the command line you actually ran, captures
**stdout and stderr together**, and still prints everything to your terminal as
usual. That second part matters more than it sounds: errors, warnings, and
"nothing matched" messages go to stderr, so a plain `cmd | pbcopy` hands you an
empty clipboard and drops the one line you wanted to share.

## Install

<details open>
<summary><b>Homebrew</b></summary>

```zsh
brew install kimata1007/tap/yanker
echo 'source "$(brew --prefix yanker)/share/yanker/yanker.plugin.zsh"' >> ~/.zshrc
```
</details>

<details>
<summary><b>sheldon</b></summary>

```toml
[plugins.yanker]
github = "kimata1007/yanker"
```
</details>

<details>
<summary><b>zinit</b></summary>

```zsh
zinit light kimata1007/yanker
```
</details>

<details>
<summary><b>antidote</b> / <b>zplug</b></summary>

```zsh
# .zsh_plugins.txt
kimata1007/yanker
```
</details>

<details>
<summary><b>oh-my-zsh</b></summary>

```zsh
git clone https://github.com/kimata1007/yanker \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/yanker"
# then add `yanker` to plugins=(...) in .zshrc
```
</details>

<details>
<summary><b>Manual</b></summary>

```zsh
git clone https://github.com/kimata1007/yanker ~/.zsh/yanker
echo 'source ~/.zsh/yanker/yanker.plugin.zsh' >> ~/.zshrc
```
</details>

## Usage

```zsh
yanker pwd                     # copies "$ pwd" and the output
yanker -o pwd                  # copies the output only
yanker ls -l | grep '\.zsh$'   # pipes work unquoted — see below
y git status -sb               # `y` is a shorter alias
```

Past copies are kept, so the next `y` does not lose the last one:

```zsh
y -s        # pick an earlier copy with fzf — or press Ctrl-V
y -l        # list what is kept
y -g 3      # put the third-newest copy back on the clipboard
y -p 3      # print it instead, to pipe somewhere
y -c        # forget everything
```

`yanker` returns the exit status of the command it ran, so it composes with
`&&`, `||`, and `$?` the way you would expect.

## How pipes work

zsh splits a line into pipeline segments *before* running anything, so a plain
function only ever sees its own segment. Writing `yanker ls | grep foo` would
hand `ls` to `yanker` and pipe yanker's output into `grep` — the copy would miss
the filtering, and `grep` would receive nothing because the clipboard already
consumed the stream.

`yanker` therefore hooks the `accept-line` widget and rewrites the line
*before* zsh splits it:

```
yanker ls | grep foo   →   yanker 'ls | grep foo'
```

The rewrite only fires when the line starts with `yanker` (or its alias) and
contains an **unquoted** operator, so `yanker echo "a|b"` is left alone.

The hook chains onto whatever `accept-line` widget is already installed, so it
coexists with `zsh-syntax-highlighting`, `zsh-autosuggestions`, and friends.
On a terminal where zsh does not load ZLE (`TERM=dumb`, non-interactive
shells), the hook is skipped and `yanker` still works as a plain function —
you just have to quote pipes yourself.

## Yank history

The clipboard holds one thing. `yanker` keeps the last 20 copies as well, so an
earlier one can be taken back out:

```console
$ y -l
  1  09-06 12:19     412 B  $ git status -sb
  2  09-06 12:18    1.4 KB  $ make test
  3  09-06 12:17      48 B  $ ls
$ y -g 3
```

`y -s` opens an fzf picker with a preview of each copy, and **Ctrl-V** does the
same without typing anything. The key is only claimed while it still holds one
of zsh's builtin widgets — if you bound `^V` yourself, `yanker` leaves it alone.
Set `YANKER_PICK_KEY` to move it, or to an empty string to skip it.

History lives in `~/.yanker_history`, beside the shell's own `~/.zsh_history`
and created with the same private permissions. The format follows suit — one
header line per record, so the file stays greppable:

```console
$ grep '^: ' ~/.yanker_history | tail -3
: 1788664630:48:;ls
: 1788664712:1433:;make test
: 1788664759:412:;git status -sb
```

A payload is arbitrary bytes, NUL included, so it is stored base64-encoded on
the lines that follow its header. `y -p N` hands it back byte for byte.

> **Copies can contain secrets.** Command output holds tokens, keys, and auth
> headers as readily as it holds a diff, and this file keeps them on disk until
> twenty more copies push them out. `y -c` clears it, `YANKER_HISTORY=0` turns
> it off, and a copy larger than `YANKER_HISTMAXSIZE` is listed but never
> written.

Keeping the history costs one extra process per copy — about 5 ms on top of
`yanker`'s own 7 ms here — because the payload goes through `base64`. Sizes,
timestamps, and formatting all come from zsh builtins, and trimming the file
happens in batches rather than on every copy.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `YANKER_CLIPBOARD` | auto-detected | Command that reads the text on stdin. Evaluated as a shell snippet, so `ssh host pbcopy` works. |
| `YANKER_ALIAS` | `y` | Short alias. Set to an empty string to skip it. An existing command, function, or alias of that name is never overwritten. |
| `YANKER_BIND_ACCEPT_LINE` | `1` | Set to `0` to leave `accept-line` untouched. |
| `YANKER_HISTORY` | `1` | Set to `0` to keep no history at all. |
| `YANKER_HISTFILE` | `~/.yanker_history` | Where past copies are kept. |
| `YANKER_HISTSIZE` | `20` | How many copies to keep. |
| `YANKER_HISTMAXSIZE` | `1048576` | Copies larger than this are listed but not stored. `0` stores everything. |
| `YANKER_PICK_KEY` | `^V` | Key that opens the fzf picker. Empty string skips the binding. |

Clipboard auto-detection tries, in order: `pbcopy`, `wl-copy`,
`xclip -selection clipboard`, `xsel --clipboard --input`, `clip.exe`. If none
are found, `yanker` fails with exit status 127 and says so, rather than
silently discarding your output.

## Argument handling

- **One argument** is treated as a shell command line, like `sh -c`:
  `yanker 'ls | grep foo'`.
- **Multiple arguments** are quoted individually, so nothing is re-interpreted:
  `yanker echo '$HOME'` prints `$HOME`. Operators passed as their own argument
  (`'|'`, `'>'`, `'2>&1'`, …) are kept as operators.

## What gets captured

Everything the command writes to **stdout and stderr**, byte for byte:

- No truncation. 50,000 lines round-trip intact (there is a test for it).
- No added or stripped trailing newline.
- Binary-safe, NUL bytes included.
- The command's exit status is `yanker`'s exit status.

## Requirements

zsh 5.0 or newer. No compiled dependencies.

`base64` is needed for the history; it ships with macOS and every mainstream
Linux. [fzf](https://github.com/junegunn/fzf) is optional and only powers `y -s`
and Ctrl-V — `y -l` and `y -g N` work without it.

## Development

```zsh
zsh test/run.zsh
```

The suite covers command-line construction, clipboard selection, the ZLE
rewrite, widget chaining, and exit-status propagation. The pty-backed
integration tests require `expect` and are skipped when it is absent.

## License

MIT
