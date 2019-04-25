#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmux bind-key q run-shell -b "ruby $CURRENT_DIR/scripts/easymotion.rb"
