#!/usr/bin/env bash
##{window_id}:#{session_id}.#{pane_id}

TMUX_WS_HOME="$(dirname ${BASH_SOURCE[0]})"
#CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#tmux bind-key C-J display-popup "$(printf '%s/tmux-ws.sh -s' ${TMUX_WS_HOME}")"
tmux bind-key C-J display-popup -h 90% -w 95% -E "$TMUX_WS_HOME/tmux-ws.sh -s"
#exit 0
