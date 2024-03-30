#!/usr/bin/env bash

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $current_dir/utils.sh
export JUMP_BACKGROUND_COLOR=$(get_tmux_option "@jump-bg-color" "\e[0m\e[32m")
export JUMP_FOREGROUND_COLOR=$(get_tmux_option "@jump-fg-color" "\e[1m\e[31m")
export JUMP_KEYS_POSITION=$(get_tmux_option "@jump-keys-position" "left")
ruby "$current_dir/tmux-jump.rb"
