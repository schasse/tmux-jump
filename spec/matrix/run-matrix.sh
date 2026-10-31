#!/bin/bash
set -u
cd "$(dirname "$0")/../.." || exit 1
builds=${TMUX_BUILDS:-${TMPDIR:-/tmp}/tmux-builds}
rspec=${RSPEC:-rspec}
status=0
for bin in "$builds"/*/bin/tmux; do
  output=$(TMUX_BIN=$bin $rspec spec/jump_positioning_spec.rb 2>&1) || status=1
  summary=$(grep -E '^[0-9]+ examples, ' <<<"$output")
  echo "$("$bin" -V): spec: ${summary:-error}"
  for mode_keys in vi emacs; do
    ruby spec/matrix/e2e.rb "$bin" "$mode_keys" | sed 's/^/  e2e: /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
  done
done
exit $status
