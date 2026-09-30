#!/usr/bin/env python3
"""Claude Code status line (settings.json statusLine → `czw statusline`), in Catppuccin Mocha.

    api   my-api   feat/login ✚3   #42 approved   Opus 5.5   ▰▰▰▱▱ 63%

Reads the JSON Claude Code sends on stdin; every field is optional. Needs a Nerd Font.
"""
import json
import os
import subprocess
import sys

C = {"lav": (180, 190, 254), "blue": (137, 180, 250), "mauve": (203, 166, 247), "peach": (250, 179, 135),
     "green": (166, 227, 161), "yellow": (249, 226, 175), "red": (243, 139, 168), "dim": (108, 112, 134),
     "sub": (166, 173, 200)}


def paint(text: str, color: str, bold: bool = False) -> str:
    r, g, b = C[color]
    return f"\033[{'1;' if bold else ''}38;2;{r};{g};{b}m{text}\033[0m"


def git(cwd: str, *args: str) -> str:
    try:
        out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=1)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def context_bar(pct: float) -> str:
    filled = max(0, min(5, round(pct / 20)))
    color = "green" if pct < 50 else "yellow" if pct < 80 else "red"
    return paint("▰" * filled, color) + paint("▱" * (5 - filled), "dim") + paint(f" {pct:.0f}%", color)


def main() -> None:
    try:
        d = json.load(sys.stdin)
    except ValueError:
        d = {}
    ws = d.get("workspace") or {}
    cwd = ws.get("current_dir") or d.get("cwd") or os.getcwd()
    parts = []
    name = d.get("session_name")
    if name:
        parts.append(paint(" " + name, "lav", bold=True))
    parts.append(paint(" " + os.path.basename(ws.get("project_dir") or cwd), "blue"))
    branch = git(cwd, "symbolic-ref", "--short", "-q", "HEAD") or git(cwd, "rev-parse", "--short", "HEAD")
    if branch:
        dirty = len([l for l in git(cwd, "status", "--porcelain").splitlines() if l.strip()])
        tree = f" ({ws['git_worktree']})" if ws.get("git_worktree") else ""
        parts.append(paint(" " + branch + tree, "mauve") + (paint(f" ✚{dirty}", "peach") if dirty else ""))
    pr = d.get("pr") or {}
    if pr.get("number"):
        state = pr.get("review_state") or ""
        color = {"approved": "green", "changes_requested": "red", "draft": "dim"}.get(state, "yellow")
        parts.append(paint(f" #{pr['number']}" + (f" {state.replace('_', ' ')}" if state else ""), color))
    model = (d.get("model") or {}).get("display_name")
    if model:
        parts.append(paint(" " + model, "sub"))
    pct = (d.get("context_window") or {}).get("used_percentage")
    if isinstance(pct, (int, float)):
        parts.append(context_bar(float(pct)))
    print(paint("  ", "dim").join(parts))


if __name__ == "__main__":
    main()
