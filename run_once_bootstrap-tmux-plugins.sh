#!/usr/bin/env bash
# Bootstrap TPM (Tmux Plugin Manager) into the XDG plugin directory and
# attempt an initial plugin install. Idempotent and safe to re-run.
#
# Run once by chezmoi after the tmux config is in place. Failures are
# non-fatal: every problem path falls back to "press prefix + I inside tmux".
set -euo pipefail

PLUGIN_DIR="$HOME/.config/tmux/plugins"
TPM_DIR="$PLUGIN_DIR/tpm"
TPM_REPO="https://github.com/tmux-plugins/tpm.git"

# 1. Clone TPM if missing.
if [ ! -d "$TPM_DIR" ]; then
  echo "chezmoi: cloning TPM -> $TPM_DIR"
  mkdir -p "$PLUGIN_DIR"
  git clone --depth 1 "$TPM_REPO" "$TPM_DIR"
else
  echo "chezmoi: TPM already present"
fi

# 2. Attempt initial plugin install via a temporary detached tmux server.
#    The config's `run '#{@plugin_dir}/tpm/tpm'` line (executed on session
#    creation) registers the @plugin list; install_plugins.sh reads both that
#    list and TMUX_PLUGIN_MANAGER_PATH.
if ! command -v tmux >/dev/null 2>&1; then
  echo "chezmoi: tmux not on PATH - skipping plugin install." >&2
  echo "         Install tmux, then press prefix + I to load plugins." >&2
  exit 0
fi

SESSION="_chezmoi_tpm_bootstrap"
tmux kill-session -t "$SESSION" 2>/dev/null || true

if ! tmux new-session -d -s "$SESSION" 2>/dev/null; then
  echo "chezmoi: could not start tmux server - skipping plugin install." >&2
  echo "         Press prefix + I inside tmux to load plugins." >&2
  exit 0
fi

# Explicitly pin the plugin install target. On first-ever bootstrap the base
# config's TPM init line cannot have run yet (TPM was just cloned above), so
# TPM's own XDG auto-detection has not set TMUX_PLUGIN_MANAGER_PATH. Setting
# it ourselves makes the install target deterministic and is harmless on
# re-runs (TPM respects an already-set value).
tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$PLUGIN_DIR/"

# Let the config + TPM finish sourcing before we invoke the installer.
sleep 1

if "$TPM_DIR/scripts/install_plugins.sh"; then
  echo "chezmoi: TPM plugins install completed"
else
  echo "chezmoi: automatic plugin install reported errors." >&2
  echo "         Press prefix + I inside tmux to retry." >&2
fi

tmux kill-session -t "$SESSION" 2>/dev/null || true
