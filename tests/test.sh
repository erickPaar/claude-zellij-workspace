#!/usr/bin/env bash
# Tests. The end-to-end one needs zellij and `script` (util-linux), and never runs the
# real claude: a fake one on PATH stands in for it.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'zellij delete-session --force czw-test >/dev/null 2>&1; pkill -f "^sleep 6[0-9][0-9]$" 2>/dev/null; rm -rf "$tmp"' EXIT
fails=0
ok() { echo "ok   $1"; }
ko() { echo "FAIL $1"; fails=$((fails + 1)); }
wait_for() { for _ in $(seq 1 "${2:-15}"); do eval "$1" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }

# 1. The resurrection hook turns every claude invocation into a resume of the same session.
hook="$root/share/resurrect-hook.sh"
check_hook() { local got; got="$(RESURRECT_COMMAND="$1" "$hook")"; [[ "$got" == "$2" ]] && ok "hook: $1" || ko "hook: '$1' gave '$got', not '$2'"; }
check_hook "/usr/local/bin/claude --resume alpha" "claude --resume alpha"
check_hook "claude -n beta" "claude --resume beta"
check_hook "claude --name=gamma" "claude --resume gamma"
check_hook "claude" "claude --resume"
check_hook "claude -p summarize" "claude -p summarize"
check_hook "bash /x/czw claude alpha" "bash /x/czw claude alpha"
check_hook "htop" "htop"

# 1b. The status line: every field optional, never a traceback.
sl="$(printf '%s' '{"session_name":"api","workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":85},"pr":{"number":7,"review_state":"approved"}}' | "$root/bin/czw" statusline | sed 's/\x1b\[[0-9;]*m//g')"
[[ "$sl" == *"api"* && "$sl" == *"Opus"* && "$sl" == *"#7 approved"* && "$sl" == *"85%"* ]] && ok "statusline: all fields" || ko "statusline: '$sl'"
[[ -n "$(echo '{}' | "$root/bin/czw" statusline)" ]] && ok "statusline: empty input" || ko "statusline: empty input"
[[ -n "$(echo 'not json' | "$root/bin/czw" statusline 2>&1)" ]] && ok "statusline: bad input" || ko "statusline: bad input"

# 1c. czw status, from the tab names of a fake zellij (a file, or a session that is gone).
mkdir -p "$tmp/fake"
# shellcheck disable=SC2016 # the fake's own arguments, expanded when it runs
printf '#!/usr/bin/env bash\n[[ "$1 $2 $3 $4" == "--session fake action query-tab-names" && -f "%s/tabs" ]] && cat "%s/tabs"\n' "$tmp" "$tmp" > "$tmp/fake/zellij"
chmod +x "$tmp/fake/zellij"
status() { PATH="$tmp/fake:$PATH" "$root/bin/czw" status "$@" --session fake; }
printf '● a\n✓ b\n c\n… d\n○ e\nf\n● g\n' > "$tmp/tabs"
want="$(printf '## Sessions\n● needs you  a, g\n✓ your turn  b\n⠋ working    c, d')"
[[ "$(status --panel)" == "$want" ]] && ok "status --panel: a line per state, idle and plain tabs left out" || ko "status --panel: '$(status --panel)'"
printf '✓ b\n' > "$tmp/tabs"
[[ "$(status --panel)" == "$(printf '## Sessions\n✓ your turn  b')" ]] && ok "status --panel: only the states present" || ko "status --panel one state: '$(status --panel)'"
printf ' c\n' > "$tmp/tabs"
[[ "$(status --panel)" == "$(printf '## Sessions\n⠋ working    c')" ]] && ok "status --panel: working alone" || ko "status --panel working: '$(status --panel)'"
printf '○ e\nf\n' > "$tmp/tabs"
[[ "$(status --panel)" == "$(printf '## Sessions\nnothing waiting')" ]] && ok "status --panel: tabs, none waiting" || ko "status --panel idle: '$(status --panel)'"
rm "$tmp/tabs"
got="$(status --panel)" && [[ "$got" == "$(printf '## Sessions\nno sessions')" ]] && ok "status --panel: a session that is gone is no sessions, exit 0" || ko "status --panel gone: '$got'"
! status >/dev/null && ok "status: a session that is gone still fails" || ko "status: a gone session exits 0"
! status --bar >/dev/null && ok "status --bar: a session that is gone still fails" || ko "status --bar: a gone session exits 0"
for args in '--session ""' '--session'; do
  got="$(unset ZELLIJ_SESSION_NAME; eval "\"$root/bin/czw\" status --panel $args")" && [[ "$got" == "$(printf '## Sessions\nno sessions')" ]] && ok "status --panel $args: no sessions, exit 0" || ko "status --panel $args: '$got'"
done
got="$(unset ZELLIJ_SESSION_NAME; "$root/bin/czw" status --panel)" && [[ "$got" == "$(printf '## Sessions\nno sessions')" ]] && ok "status --panel: outside zellij, no sessions, exit 0" || ko "status --panel outside zellij: '$got'"
(unset ZELLIJ_SESSION_NAME; "$root/bin/czw" status >/dev/null 2>&1) && ko "status: outside zellij should still fail" || ok "status: outside zellij still asks for --session"
printf '● a\n✓ b\n c\n… d\n○ e\nf\n● g\n' > "$tmp/tabs"
got="$(PATH="$tmp/fake:$PATH" ZELLIJ_SESSION_NAME=fake "$root/bin/czw" status --panel)"
[[ "$got" == "$(printf '## Sessions\n● needs you  a, g\n✓ your turn  b\n⠋ working    c, d')" ]] && ok "status --panel: the session from ZELLIJ_SESSION_NAME" || ko "status --panel from the environment: '$got'"
[[ "$(status)" == "$(printf 'needs you  a, g\nyour turn  b\nworking    c, d')" ]] && ok "status: unchanged" || ko "status: '$(status)'"
[[ "$(status --bar)" == "● 2  ✓ 1   2" ]] && ok "status --bar: unchanged" || ko "status --bar: '$(status --bar)'"
[[ "$(status --zjstatus)" == "#[fg=#f38ba8,bg=#181825,bold]● 2  #[fg=#a6e3a1,bg=#181825,bold]✓ 1  #[fg=#89b4fa,bg=#181825] 2  " ]] && ok "status --zjstatus: unchanged" || ko "status --zjstatus: '$(status --zjstatus)'"
: > "$tmp/tabs"
[[ "$(status)" == "nothing waiting" ]] && ok "status: nothing waiting, unchanged" || ko "status empty: '$(status)'"

# 1d. The bell on "needs you", from a fake zellij that knows one pane. `script` gives the run a
# terminal, as a session's pane does; setsid leaves czw itself without one, as a hook is.
mkdir -p "$tmp/fakemark"
cat > "$tmp/fakemark/zellij" <<'ZJ'
#!/usr/bin/env bash
case "$*" in
  "action list-panes --tab --json") echo "[{\"id\": 1, \"is_plugin\": false, \"tab_id\": 3, \"tab_name\": \"${FAKE_TAB:-a}\"}]" ;;
  "action list-tabs --json") echo '[]' ;;
esac
exit 0
ZJ
chmod +x "$tmp/fakemark/zellij"
nomnt="$(tr ':' '\n' <<<"$PATH" | grep -v '^/mnt/' | paste -sd: -)"
bell() { # mark [CZW_NOTIFY]: did the run's terminal get a bell? (FAKE_TAB, BELL_PATH from the caller)
  local out="$tmp/bell.out"; rm -f "$out"
  env -u DISPLAY -u WAYLAND_DISPLAY PATH="${BELL_PATH:-$tmp/fakemark:$nomnt}" XDG_STATE_HOME="$tmp/state-bell" \
    ZELLIJ_PANE_ID=1 ZELLIJ_SESSION_NAME=fake CZW_NOTIFY="${2:-auto}" \
    script -qfc "setsid -w $root/bin/czw mark $1" "$out" >/dev/null 2>&1 </dev/null
  grep -q $'\a' "$out" && echo yes || echo no
}
[[ "$(bell attention)" == yes ]] && ok "mark attention rings the bell in the pane" || ko "mark attention: no bell"
[[ "$(bell "done")" == no ]] && ok "mark done rings no bell" || ko "mark done rang the bell"
[[ "$(bell attention bar)" == no ]] && ok "CZW_NOTIFY=bar: no bell" || ko "CZW_NOTIFY=bar rang the bell"
[[ "$(bell attention off)" == no ]] && ok "CZW_NOTIFY=off: no bell" || ko "CZW_NOTIFY=off rang the bell"
[[ "$(FAKE_TAB="● a" bell attention)" == no ]] && ok "a tab already marked needs-you rings no second bell" || ko "a repeated attention mark rang again"
# A ps that fails (an ancestor gone mid-walk, no ps at all) never aborts the mark.
mkdir -p "$tmp/failps"; printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/failps/ps"; chmod +x "$tmp/failps/ps"
rm -rf "$tmp/state-bell"
BELL_PATH="$tmp/failps:$tmp/fakemark:$nomnt" bell attention >/dev/null
[[ -s "$tmp/state-bell/czw/status/fake" ]] && ok "a failing ps still lets the mark write the bar's status" || ko "a failing ps aborted the mark"
# A ps that answers the tty (none) and then fails on the parent: the walk's second step.
mkdir -p "$tmp/failppid"; printf '#!/usr/bin/env bash\ncase "$*" in *tty=*) echo "?" ;; *) exit 1 ;; esac\n' > "$tmp/failppid/ps"; chmod +x "$tmp/failppid/ps"
rm -rf "$tmp/state-bell"
BELL_PATH="$tmp/failppid:$tmp/fakemark:$nomnt" bell attention >/dev/null
[[ -s "$tmp/state-bell/czw/status/fake" ]] && ok "a ps failing on the parent still lets the mark write the bar's status" || ko "a ps failing on the parent aborted the mark"

# 1e. czw shell, from the panes of a fake zellij: each state gives its calls. The helper
# (pane 7, floating) runs in tab 1 unless helper_tab says otherwise; keep is the id czw kept.
mkdir -p "$tmp/fake-shell"
cat > "$tmp/fake-shell/zellij" <<SH
#!/usr/bin/env bash
case "\$2" in
  list-panes) cat "$tmp/panes.json" ;;
  new-pane) echo "\${*:2}" >> "$tmp/shell-calls"; echo terminal_12 ;;
  *) echo "\${*:2}" >> "$tmp/shell-calls" ;;
esac
SH
chmod +x "$tmp/fake-shell/zellij"
# Each pane: "ID|TAB|TITLE|COMMAND[|FLAG...]", COMMAND - for none; FLAG exited, plugin,
# floating, nocwd, proc (COMMAND is the running process's, not zellij's), fs (the tab is
# full screen: every pane in it says so) or fs1 (only this pane says so).
shell_case() {
  local label="$1" want="$2" got; shift 2
  python3 -c '
import json, sys
specs = [s.split("|") for s in sys.argv[1:]]
fs_tabs = {f[1] for f in specs if "fs" in f[4:]}
out = []
for f in specs:
    cmd = None if f[3] == "-" else f[3]
    out.append({"id": int(f[0]), "tab_id": int(f[1]), "title": f[2], **({"pane_command": cmd} if "proc" in f[4:] else {"terminal_command": cmd}),
                "is_fullscreen": f[1] in fs_tabs or "fs1" in f[4:], "exited": "exited" in f[4:], "is_plugin": "plugin" in f[4:],
                "is_floating": "floating" in f[4:], **({} if "nocwd" in f[4:] else {"pane_cwd": "/w/p"})})
print(json.dumps(out))' "$@" "7|${helper_tab:-1}|czw shell|czw shell|floating" > "$tmp/panes.json"
  : > "$tmp/shell-calls"
  rm -rf "$tmp/shell-state"; mkdir -p "$tmp/shell-state/czw/shells/fake"
  [[ -n "${keep:-}" ]] && echo "$keep" > "$tmp/shell-state/czw/shells/fake/${helper_tab:-1}"
  (cd "$tmp" && PATH="$tmp/fake-shell:$PATH" XDG_STATE_HOME="$tmp/shell-state" ZELLIJ_SESSION_NAME=fake ZELLIJ_PANE_ID=7 SHELL=/bin/sh \
    "$root/bin/czw" shell) || { ko "shell: $label: czw shell failed"; return; }
  got="$(tr '\n' ';' < "$tmp/shell-calls")"
  [[ "$got" == "$want" ]] && ok "shell: $label" || ko "shell: $label: '$got', not '$want'"
}
kept_is() { [[ "$(cat "$tmp/shell-state/czw/shells/fake/${helper_tab:-1}" 2>/dev/null)" == "$1" ]] && ok "shell: $2" || ko "shell: $2: kept '$(cat "$tmp/shell-state/czw/shells/fake/${helper_tab:-1}" 2>/dev/null)', not '$1'"; }
session="0|1|✳ Claude Code|czw claude alpha"
noise=("4|1|shell|-|plugin" "9|1|shell|-|floating" "5|0|shell|-")
open_in() { echo "new-pane --direction right --name shell --tab-id $1 --close-on-exit --cwd $2 -- /bin/sh;"; }
shell_case "no shell: one opens right of the session, in its folder" \
  "focus-pane-id terminal_0;$(open_in 1 /w/p)" "$session" "${noise[@]}"
kept_is 12 "the new shell's id is kept for its tab"
shell_case "a shell showing: the session goes full screen" \
  "focus-pane-id terminal_0;toggle-fullscreen;" "$session" "3|1|shell|-" "${noise[@]}"
kept_is 3 "a shell found by its title is kept"
shell_case "the session full screen: back to the split, the shell focused" \
  "focus-pane-id terminal_0;toggle-fullscreen;focus-pane-id terminal_3;" "$session|fs" "3|1|shell|-" "${noise[@]}"
shell_case "the same, only the session pane saying full screen" \
  "focus-pane-id terminal_0;toggle-fullscreen;focus-pane-id terminal_3;" "$session|fs1" "3|1|shell|-"
shell_case "no shell while the session is full screen: back to the split, then a shell" \
  "focus-pane-id terminal_0;toggle-fullscreen;$(open_in 1 /w/p)" "$session|fs"
shell_case "an exited shell counts as none and is replaced" \
  "close-pane --pane-id terminal_3;focus-pane-id terminal_0;$(open_in 1 /w/p)" "$session" "3|1|shell|-|exited"
shell_case "a tab with no session pane: nothing" "" "2|1|bash|-" "3|1|shell|-"
shell_case "only czw claude NAME is a session" "" "2|1|a|myczw claude a" "3|1|b|claude --resume b" "6|1|c|czw claude"
shell_case "a session known by its process only, as after a resurrection" \
  "focus-pane-id terminal_0;toggle-fullscreen;" "0|1|claude|bash /x/czw claude alpha|proc" "3|1|shell|-"
shell_case "no folder known: the current one" "focus-pane-id terminal_0;$(open_in 1 "$tmp")" "$session|nocwd"
helper_tab=2 shell_case "two clients: the helper's own tab, not the first active one" \
  "focus-pane-id terminal_10;$(open_in 2 /w/p)" "$session" "3|1|shell|-" "10|2|claude|czw claude beta"
keep=6 shell_case "the kept id wins over the title" \
  "focus-pane-id terminal_0;toggle-fullscreen;focus-pane-id terminal_6;" "$session|fs" "3|1|shell|-" "6|1|user@host: ~|-"
keep=6 shell_case "a retitled shell is still known by its kept id" \
  "focus-pane-id terminal_0;toggle-fullscreen;" "$session" "6|1|user@host: ~|-" "8|1|htop|-"
shell_case "two other panes, none kept: the one titled shell" \
  "focus-pane-id terminal_0;toggle-fullscreen;" "$session" "8|1|htop|-" "3|1|shell|-"
shell_case "two other panes, none kept nor titled shell exactly: a new shell" \
  "focus-pane-id terminal_0;$(open_in 1 /w/p)" "$session" "6|1|my shell|-" "8|1|shell2|-"
keep=3 shell_case "after a resurrection, the one other pane is adopted, not doubled" \
  "focus-pane-id terminal_0;toggle-fullscreen;" "0|1|bash /x/czw claude alpha|bash /x/czw claude alpha" "1|1|Pane #2|-" "3|0|shell|-"
kept_is 1 "the adopted shell is kept"
shell_case "a session named shell is the session, not the shell" \
  "focus-pane-id terminal_0;toggle-fullscreen;focus-pane-id terminal_3;" "0|1|shell|czw claude shell|fs" "3|1|shell|-"
shell_case "two session panes: the shell goes beside the first" \
  "focus-pane-id terminal_0;$(open_in 1 /w/p)" "$session" "2|1|claude|czw claude beta"
usage="$("$root/bin/czw" 2>/dev/null)"
[[ "$usage" == *"czw version" && "$usage" != *"set -"* ]] && ok "usage: the header's commands, no code" || ko "usage: '$usage'"

# 2. The layout: one tab per session, run through czw, then tabs.kdl.
ws="$tmp/ws"; mkdir -p "$ws/sub"
cat > "$ws/sessions.txt" <<TXT
# a comment
proj-alpha
proj-beta   $ws/sub   b
TXT
printf 'folder = %s   # a trailing comment\nstrip_prefix = proj-\nname = czw-test\n' "$ws" > "$ws/workspace.conf"
# shellcheck disable=SC2016 # the layout's own ${HOME} and ${WORKSPACE}, for layout.py
printf 'tab name="extra" cwd="${HOME}" {\n    pane command="bash" { args "${WORKSPACE}/x.sh"; }\n}\n' > "$ws/tabs.kdl"
python3 "$root/lib/layout.py" "$ws" "$tmp/layout.kdl" && ok "layout written" || ko "layout.py failed"
grep -q 'tab name="alpha" cwd="'"$ws"'" focus=true' "$tmp/layout.kdl" && ok "layout: prefix stripped, default folder" || ko "layout: first tab"
grep -q 'tab name="b" cwd="'"$ws"'/sub"' "$tmp/layout.kdl" && ok "layout: folder and tab from the line" || ko "layout: second tab"
grep -q 'args "claude" "proj-beta"' "$tmp/layout.kdl" && ok "layout: runs czw claude NAME" || ko "layout: command"
grep -q "\"$ws/x.sh\"" "$tmp/layout.kdl" && ok "layout: tabs.kdl added, \${WORKSPACE} replaced" || ko "layout: tabs.kdl"
grep -q "cwd=\"$HOME\"" "$tmp/layout.kdl" && ok "layout: \${HOME} replaced" || ko "layout: \${HOME}"

# 3. End to end: open, save, die like a reboot, resurrect waiting, wake the right session.
if ! command -v zellij >/dev/null || ! command -v script >/dev/null; then
  echo "skip end-to-end (needs zellij and script)"; exit $((fails > 0))
fi
mkdir -p "$tmp/bin" "$tmp/state"
# shellcheck disable=SC2016 # expanded by the fake claude when it runs, not here
printf '#!/usr/bin/env bash\necho "fake claude $* (CZW_SESSION=${CZW_SESSION:-})" >> "%s/calls"\nexec sleep 600\n' "$tmp" > "$tmp/bin/claude"
ln -s "$root/bin/czw" "$tmp/bin/czw"
chmod +x "$tmp/bin/claude"
mkdir -p "$tmp/state/czw/known" && touch "$tmp/state/czw/known/proj-alpha"
rm "$ws/tabs.kdl"
cfg="$tmp/zellij"; mkdir -p "$cfg"
sed "s#@CZW_ROOT@#$root#g" "$root/share/config.kdl" | sed 's/^serialization_interval 30/serialization_interval 2/' > "$cfg/config.kdl"
python3 "$root/lib/layout.py" --default "$cfg/layouts/czw.kdl" czw-test
grep -q 'Run "czw" "next"' "$cfg/config.kdl" && ok "config: Alt a runs czw next" || ko "config: no Alt a"
grep -q 'bind "Alt n" { Run "czw" "shell"' "$cfg/config.kdl" && grep -q 'bind "n" { Run "czw" "shell"' "$cfg/config.kdl" && ok "config: Alt n and Alt g, n run czw shell" || ko "config: no Alt n or Alt g, n"
env_run() { PATH="$tmp/bin:$PATH" XDG_STATE_HOME="$tmp/state" "$@"; }
python3 "$root/lib/layout.py" "$ws" "$tmp/layout.kdl"
# A czw-test left by a run that just ended may still be shutting down: wait until it is gone.
zellij delete-session --force czw-test >/dev/null 2>&1
wait_for "! zellij list-sessions -n 2>/dev/null | grep -q '^czw-test '" 10 || ko "an old czw-test session is still there"
(env_run setsid script -qfc "zellij --config-dir $cfg --session czw-test --new-session-with-layout $tmp/layout.kdl" /dev/null >/dev/null 2>&1 </dev/null &)
wait_for "zellij --session czw-test action query-tab-names" && ok "session started" || ko "session did not start"
[[ "$(zellij --session czw-test action query-tab-names | tr '\n' ' ')" == "alpha b " ]] && ok "tabs come from the workspace layout" || ko "tabs are not the layout's (zellij used another layout)"
mark() { (cd "$tmp" && CZW_NOTIFY=off XDG_STATE_HOME="$tmp/state" ZELLIJ_SESSION_NAME=czw-test ZELLIJ_PANE_ID=0 "$root/bin/czw" mark "$1"); zellij --session czw-test action query-tab-names | head -1; }
[[ "$(mark "done")" == "✓ alpha" ]] && ok "mark: done" || ko "mark done"
[[ "$(mark attention)" == "● alpha" ]] && ok "mark: attention replaces the old marker" || ko "mark attention"
[[ "$(mark unblock)" == " alpha" ]] && ok "mark: unblock turns attention into working" || ko "mark unblock"
[[ "$(mark unblock)" == " alpha" ]] && ok "mark: unblock leaves other states alone" || ko "mark unblock twice"
[[ "$(mark idle)" == "○ alpha" ]] && ok "mark: idle" || ko "mark idle"
[[ "$(mark working)" == " alpha" ]] && ok "mark: working replaces idle" || ko "mark working"
grep -q '● 1' "$tmp/state/czw/status/czw-test" 2>/dev/null || [[ -f "$tmp/state/czw/status/czw-test" ]] && ok "mark: writes the bar's status file in the state folder" || ko "mark: no status file"
[[ ! -e "$tmp/working" && ! -e "$tmp/unblock" && ! -e "$tmp/attention" ]] && ok "mark: nothing written to the current folder" || ko "mark wrote into the current folder"
[[ "$(mark clear)" == "alpha" ]] && ok "mark: clear" || ko "mark clear"
ZELLIJ_SESSION_NAME=czw-test ZELLIJ_PANE_ID=1 XDG_STATE_HOME="$tmp/state" CZW_NOTIFY=off "$root/bin/czw" mark attention
ZELLIJ_SESSION_NAME=czw-test "$root/bin/czw" next
active="$(zellij --session czw-test action list-tabs --json | python3 -c 'import json,sys; print(next(t["name"] for t in json.load(sys.stdin) if t["active"]))')"
[[ "$active" == "● b" ]] && ok "next: goes to the tab that needs you" || ko "next went to '$active'"
ZELLIJ_SESSION_NAME=czw-test ZELLIJ_PANE_ID=1 XDG_STATE_HOME="$tmp/state" CZW_NOTIFY=off "$root/bin/czw" mark clear
zellij --session czw-test action go-to-tab 1
[[ "$(zellij --session czw-test action query-tab-names | sed -n 2p)" == "b" ]] && ok "mark: only the pane's own tab changes" || ko "mark touched another tab"
(unset ZELLIJ_PANE_ID; "$root/bin/czw" mark "done") && ok "mark: no-op outside zellij" || ko "mark failed outside zellij"
wait_for "[[ \$(grep -c . $tmp/calls 2>/dev/null) -ge 2 ]]" 10 && ok "both sessions ran" || ko "sessions did not run"
grep -q 'fake claude --resume proj-alpha' "$tmp/calls" && ok "known session resumed by name" || ko "alpha not resumed"
grep -q 'fake claude -n proj-beta' "$tmp/calls" && ok "new session started with its name" || ko "beta not created"
grep -q 'fake claude --resume proj-alpha (CZW_SESSION=proj-alpha)' "$tmp/calls" && ok "a resumed session gets CZW_SESSION" || ko "alpha without CZW_SESSION"
grep -q 'fake claude -n proj-beta (CZW_SESSION=proj-beta)' "$tmp/calls" && ok "a new session gets CZW_SESSION" || ko "beta without CZW_SESSION"
# Wait for a save made after go-to-tab 1: an earlier one keeps tab b focused (from next), and Enter would go to beta.
wait_for "grep -qs 'tab name=\"alpha\" focus=true' $HOME/.cache/zellij/*/session_info/czw-test/session-layout.kdl" 10 && ok "layout saved for resurrection, alpha focused" || ko "nothing saved with alpha focused"
# shellcheck disable=SC2012 # zellij's cache folder names are its own, plain
saved="$(ls -d "$HOME/.cache"/zellij/*/session_info/czw-test | head -1)"
grep -q '"claude" "proj-alpha"' "$saved/session-layout.kdl" && ok "saved command keeps the session name" || ko "saved command lost the name"
pkill -9 -f 'zellij --server .*czw-test'; pkill -f '^sleep 600$'; : > "$tmp/calls"
wait_for "zellij list-sessions -n | grep -q 'czw-test.*EXITED'" && ok "session died like a reboot, resurrectable" || ko "no exited session"
(env_run setsid script -qfc "zellij --config-dir $cfg attach czw-test" /dev/null >/dev/null 2>&1 </dev/null &)
wait_for "zellij --session czw-test action query-tab-names" && ok "resurrected" || ko "did not resurrect"
sleep 2
[[ ! -s "$tmp/calls" ]] && ok "resurrected commands wait for Enter" || ko "commands ran without Enter"
zellij --session czw-test action write 13
wait_for "grep -q 'fake claude --resume proj-alpha' $tmp/calls" && ok "Enter resumes the same session" || ko "Enter did not resume alpha"
grep -q 'fake claude --resume proj-alpha (CZW_SESSION=proj-alpha)' "$tmp/calls" && ok "the resumed session gets CZW_SESSION again" || ko "resurrected alpha without CZW_SESSION"

[[ $fails -eq 0 ]] && echo "all passed" || echo "$fails failed"
exit $((fails > 0))
