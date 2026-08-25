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

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `YANKER_CLIPBOARD` | auto-detected | Command that reads the text on stdin. Evaluated as a shell snippet, so `ssh host pbcopy` works. |
| `YANKER_ALIAS` | `y` | Short alias. Set to an empty string to skip it. An existing command, function, or alias of that name is never overwritten. |
| `YANKER_BIND_ACCEPT_LINE` | `1` | Set to `0` to leave `accept-line` untouched. |

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

## Development

```zsh
zsh test/run.zsh
```

The suite covers command-line construction, clipboard selection, the ZLE
rewrite, widget chaining, and exit-status propagation. The pty-backed
integration tests require `expect` and are skipped when it is absent.

## License

MIT
