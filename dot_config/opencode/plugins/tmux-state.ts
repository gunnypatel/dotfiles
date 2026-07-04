// opencode plugin — mirrors Claude Code's tmux-claude-pane-picker integration.
// Listens for session lifecycle events and forwards them as state values
// (working|waiting|idle) to the picker's pane state script, so opencode panes
// show live status in the tmux picker exactly like Claude Code panes do.
//
// The picker's state.sh sets tmux pane options @claude_state / @claude_state_at
// on $TMUX_PANE. opencode loads plugins in-process, so the plugin inherits the
// shell's TMUX_PANE — the same variable state.sh keys off of. Outside tmux,
// state.sh is a no-op.

import type { Plugin } from "@opencode-ai/plugin"

const STATE_SCRIPT =
  (process.env.HOME || "") +
  "/.config/tmux/plugins/tmux-claude-pane-picker/scripts/state.sh"

export const TmuxStatePlugin: Plugin = async ({ $ }) => {
  // best-effort: never let a tmux state write block or crash opencode
  const setState = (state: string) =>
    $`bash ${STATE_SCRIPT} ${state}`.quiet().catch(() => {})

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.idle":
          await setState("idle")
          break
        case "permission.asked":
          await setState("waiting")
          break
        case "session.status":
          // session.status payload: { sessionID, status: { type: "busy"|"idle"|"retry" } }
          // (idle transitions are also emitted as a separate session.idle event,
          // so we only need to map busy -> working here.)
          if (
            (event.properties as { status?: { type?: string } } | undefined)
              ?.status?.type === "busy"
          ) {
            await setState("working")
          }
          break
      }
    },
  }
}
