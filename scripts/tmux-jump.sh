#!/usr/bin/env bash

tmp_file="$(mktemp)"
tmux command-prompt -1 -p 'char:' "run-shell \"printf '%1' >> $tmp_file\""

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ruby "$current_dir/tmux-jump.rb" "$tmp_file"
