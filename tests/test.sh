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
printf '#!/usr/bin/env bash\n[[ -f "%s/tabs" ]] && cat "%s/tabs"\n' "$tmp" "$tmp" > "$tmp/fake/zellij"
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
got="$(unset ZELLIJ_SESSION_NAME; "$root/bin/czw" status --panel)" && [[ "$got" == "$(printf '## Sessions\nno sessions')" ]] && ok "status --panel: outside zellij, no sessions, exit 0" || ko "status --panel outside zellij: '$got'"
(unset ZELLIJ_SESSION_NAME; "$root/bin/czw" status >/dev/null 2>&1) && ko "status: outside zellij should still fail" || ok "status: outside zellij still asks for --session"
printf '● a\n✓ b\n c\n… d\n○ e\nf\n● g\n' > "$tmp/tabs"
[[ "$(status)" == "$(printf 'needs you  a, g\nyour turn  b\nworking    c, d')" ]] && ok "status: unchanged" || ko "status: '$(status)'"
[[ "$(status --bar)" == "● 2  ✓ 1   2" ]] && ok "status --bar: unchanged" || ko "status --bar: '$(status --bar)'"
[[ "$(status --zjstatus)" == "#[fg=#f38ba8,bg=#181825,bold]● 2  #[fg=#a6e3a1,bg=#181825,bold]✓ 1  #[fg=#89b4fa,bg=#181825] 2  " ]] && ok "status --zjstatus: unchanged" || ko "status --zjstatus: '$(status --zjstatus)'"
: > "$tmp/tabs"
[[ "$(status)" == "nothing waiting" ]] && ok "status: nothing waiting, unchanged" || ko "status empty: '$(status)'"

# 2. The layout: one tab per session, run through czw, then tabs.kdl.
ws="$tmp/ws"; mkdir -p "$ws/sub"
cat > "$ws/sessions.txt" <<TXT
# a comment
proj-alpha
proj-beta   $ws/sub   b
TXT
printf 'folder = %s   # a trailing comment\nstrip_prefix = proj-\nname = czw-test\n' "$ws" > "$ws/workspace.conf"
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
printf '#!/usr/bin/env bash\necho "fake claude $*" >> "%s/calls"\nexec sleep 600\n' "$tmp" > "$tmp/bin/claude"
ln -s "$root/bin/czw" "$tmp/bin/czw"
chmod +x "$tmp/bin/claude"
mkdir -p "$tmp/state/czw/known" && touch "$tmp/state/czw/known/proj-alpha"
rm "$ws/tabs.kdl"
cfg="$tmp/zellij"; mkdir -p "$cfg"
sed "s#@CZW_ROOT@#$root#g" "$root/share/config.kdl" | sed 's/^serialization_interval 30/serialization_interval 2/' > "$cfg/config.kdl"
python3 "$root/lib/layout.py" --default "$cfg/layouts/czw.kdl" czw-test
grep -q 'Run "czw" "next"' "$cfg/config.kdl" && ok "config: Alt a runs czw next" || ko "config: no Alt a"
env_run() { PATH="$tmp/bin:$PATH" XDG_STATE_HOME="$tmp/state" "$@"; }
python3 "$root/lib/layout.py" "$ws" "$tmp/layout.kdl"
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
wait_for "grep -qs czw $HOME/.cache/zellij/*/session_info/czw-test/session-layout.kdl" 10 && ok "layout saved for resurrection" || ko "nothing saved"
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

[[ $fails -eq 0 ]] && echo "all passed" || echo "$fails failed"
exit $((fails > 0))
