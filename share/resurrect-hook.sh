#!/usr/bin/env bash
# czw sets this as zellij's post_command_discovery_hook. Zellij runs it when it resurrects a session after a restart, with the command
# it found in each pane in $RESURRECT_COMMAND; what this prints is what the pane runs.
# A Claude session must come back as the same conversation, never as a new one:
#   claude -n NAME / --name NAME / --resume NAME / -r NAME  ->  claude --resume NAME
#   claude with no session named (its args are hidden)     ->  claude --resume (the picker)
cmd="${RESURRECT_COMMAND:-}"
read -r -a argv <<<"$cmd"
case "$(basename "${argv[0]:-}")" in
  claude)
    # A headless run (-p) is a one-off: leave it as it was.
    for a in "${argv[@]}"; do [[ "$a" == -p || "$a" == --print ]] && { echo "$cmd"; exit 0; }; done
    for ((i = 1; i < ${#argv[@]}; i++)); do
      case "${argv[i]}" in
        -n|--name|-r|--resume) if [[ -n "${argv[i+1]:-}" ]]; then echo "claude --resume ${argv[i+1]}"; exit 0; fi ;;
        --name=*|--resume=*) echo "claude --resume ${argv[i]#*=}"; exit 0 ;;
      esac
    done
    echo "claude --resume"
    ;;
  *) echo "$cmd" ;;
esac
