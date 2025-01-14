#!/usr/bin/env bash

TMUX_WS_HOME="$(dirname ${BASH_SOURCE[0]})"

tmux bind-key C-J display-popup -h 90% -w 95% -E "$TMUX_WS_HOME/tmux-ws.sh -s"

