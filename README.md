# claude-zellij-workspace

Run several [Claude Code](https://claude.com/claude-code) sessions as tabs of one
[zellij](https://zellij.dev) session, and get them back, each in the same conversation,
after you close the terminal or reboot the machine.

```
czw open ~/work        # one tab per session in ~/work/sessions.txt
```

- **Close the window**: nothing stops. `czw open ~/work` reattaches, every session mid-task.
- **Reboot**: `czw open ~/work` brings the tabs back, each waiting for Enter, and Enter
  resumes that tab's own conversation. `--all` resumes them all at once.
- **Keys**: zellij starts locked, so Claude Code keeps every shortcut (Ctrl+G, Ctrl+O,
  Ctrl+T, Ctrl+B...). `Alt 1`…`Alt 9` switch tabs; `Alt g` opens zellij's commands.
- Your own `~/.config/zellij/config.kdl` is left alone: czw runs its sessions with its own.

## Why a wrapper

A running `claude` process rewrites its title, hiding its arguments. Zellij's
resurrection reads the command from the process, so a tab started with
`claude --resume alpha` would come back as a bare `claude`: a new, empty conversation.
czw runs each session as `czw claude NAME`, which keeps the name in its own command line
and starts `claude` as a child, so zellij records a command that resumes the right session.

## Install

Needs zellij 0.41 or later, Claude Code, bash, Python 3.9+.

```
git clone https://github.com/erickPaar/claude-zellij-workspace
cd claude-zellij-workspace && make install     # links ~/.local/bin/czw
```

## A workspace

A folder with a `sessions.txt`, and optionally `workspace.conf` and `tabs.kdl`
(see [`examples/basic`](examples/basic)):

```
# sessions.txt: NAME [FOLDER] [TAB]
api          ~/code/my-api
web          ~/code/my-web
review       ~/code/my-api      pr-review
```

```
# workspace.conf
name = work               # the zellij session name (default: the folder's name)
folder = ~/code           # for lines without a folder (default: ~)
strip_prefix = my-        # tab names drop this prefix (optional)
```

`tabs.kdl` adds tabs after the sessions, in zellij's layout language; `${WORKSPACE}`
becomes the workspace folder, so it can run scripts kept beside it (a dev server, a log),
and `${HOME}` the home folder.

## Which session needs you

With a few Claude Code hooks, each tab's name shows its session's state:

| Tab | Means |
|---|---|
| `… api` | working |
| `✓ api` | finished: your turn |
| `● api` | waiting for you: a permission prompt or a question |
| `api` | idle since it started |

Merge [`examples/claude-settings-hooks.json`](examples/claude-settings-hooks.json) into the
`hooks` of `~/.claude/settings.json`. Each hook runs `czw mark STATE`, which renames only
the tab of the pane the session runs in, takes about 70 ms, and does nothing outside zellij.

## Commands

| Command | What it does |
|---|---|
| `czw open DIR` | open the workspace, or reattach to it; after a reboot, resurrect it |
| `czw open DIR --all` | the same, starting every resurrected tab at once |
| `czw open DIR --fresh` | rebuild the tabs from `sessions.txt` (asks first) |
| `czw new NAME [FOLDER] [TAB]` | inside a workspace: a new named session in a new tab, added to `sessions.txt` |
| `czw claude NAME` | run session NAME: resume it, or start it with that name the first time |
| `czw list [DIR]` | the sessions a workspace opens |
| `czw mark STATE` | from a hook: `working`, `done`, `attention`, `unblock` (attention back to working) or `clear` |

A small script per workspace makes it one word: `exec czw open ~/work "$@"`.

## Keys

| Keys | What it does |
|---|---|
| `Alt 1`…`Alt 9`, `Alt 0` | tab 1 to 9; the previous tab |
| `Alt g` | command mode: one of the keys below, then back to locked |
| `Alt g`, `s` / `/` | scroll / search this tab's history |
| `Alt g`, `e` | open the history in `$EDITOR` |
| `Alt g`, `f` | full screen |
| `Alt g`, `w` | session manager |
| `Alt g`, `t` / `p` | tab mode / pane mode (new, rename, close, split) |
| `Alt g`, `d` | detach |
| `Alt g`, `o`, `q` | quit zellij and every session in it |

Copy is by mouse selection, sent through OSC 52 to the system clipboard.

## State

- `~/.local/state/czw/known/NAME`: the sessions czw has started, so it resumes them.
- `~/.local/state/czw/workspaces/SESSION`: which folder a zellij session came from.
- `~/.cache/czw/`: the generated zellij config folder (`zellij/`) and layouts.

## Tests

`make test`: the resurrection hook, the layout, and an end-to-end run with a fake
`claude` that opens a workspace, kills the zellij server like a reboot, resurrects it and
checks that Enter resumes the same session.

## Known gaps

- Inside zellij, Shift+Enter may arrive as Enter; `\` then Enter, or Ctrl+J, make a new line.
- Tested on Linux (WSL 2, Ubuntu 22.04) with zellij 0.45.1.

## License

MIT
