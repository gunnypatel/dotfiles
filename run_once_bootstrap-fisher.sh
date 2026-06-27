#!/usr/bin/env bash
# Bootstrap Fisher (the Fish plugin manager), install the plugins listed in
# ~/.config/fish/fish_plugins, and apply the tide prompt theme. Idempotent and
# safe to re-run.
#
# Run once by chezmoi after the fish config is in place. Failures are
# non-fatal: every problem path falls back to "run `fisher update` by hand".
set -euo pipefail

# 1. Guard: nothing to do if fish itself isn't installed yet.
if ! command -v fish >/dev/null 2>&1; then
  echo "chezmoi: fish not on PATH - skipping Fisher bootstrap." >&2
  echo "         Install fish and re-run \`chezmoi apply\` (or \`fisher update\`)." >&2
  exit 0
fi

# 2. Install Fisher if missing, reconcile plugins against fish_plugins, then
#    apply the tide prompt theme. `fisher install jorgebucaran/fisher` persists
#    the just-sourced function so it survives future shells; `fisher update`
#    (no args) reads fish_plugins and installs tide / nvm.fish, updates existing,
#    removes unlisted. `tide configure --auto` reproduces the exact prompt recipe
#    (idempotent). The theme step is non-fatal: a failure leaves the plugins
#    working with tide's defaults - run `tide configure` to retry. Safe to re-run.
if fish <<'EOF'
if not type -q fisher
    echo "chezmoi: installing Fisher"
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
end
echo "chezmoi: reconciling fish plugins from fish_plugins"
fisher update
set -l plugins_ok $status

if test $plugins_ok -eq 0; and type -q tide
    echo "chezmoi: applying tide theme"
    tide configure --auto --style=Rainbow --prompt_colors='True color' \
        --show_time='24-hour format' --rainbow_prompt_separators=Angled \
        --powerline_prompt_heads=Sharp --powerline_prompt_tails=Flat \
        --powerline_prompt_style='Two lines, character' \
        --prompt_connection=Disconnected --powerline_right_prompt_frame=No \
        --prompt_spacing=Compact --icons='Many icons' --transient=Yes >/dev/null
    or echo "chezmoi: tide configure reported an error (continuing)" >&2
end

exit $plugins_ok
EOF
then
  echo "chezmoi: Fisher bootstrap completed"
else
  echo "chezmoi: Fisher bootstrap reported errors." >&2
  echo "         Open fish and run \`fisher update\` to retry." >&2
fi
