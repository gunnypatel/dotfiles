#!/usr/bin/env bash
# Bootstrap Fisher (the Fish plugin manager) and install the plugins listed
# in ~/.config/fish/fish_plugins. Idempotent and safe to re-run.
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

# 2. Install Fisher if missing, then reconcile plugins against fish_plugins.
#    `fisher install jorgebucaran/fisher` persists the just-sourced function so
#    it survives future shells; `fisher update` (no args) reads fish_plugins and
#    installs tide / nvm.fish, updates existing, removes unlisted. Safe to re-run.
if fish <<'EOF'
if not type -q fisher
    echo "chezmoi: installing Fisher"
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
end
echo "chezmoi: reconciling fish plugins from fish_plugins"
fisher update
EOF
then
  echo "chezmoi: Fisher bootstrap completed"
else
  echo "chezmoi: Fisher bootstrap reported errors." >&2
  echo "         Open fish and run \`fisher update\` to retry." >&2
fi
