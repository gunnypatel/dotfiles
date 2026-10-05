# Couch Emulation Streaming Stack — Design

Date: 2026-10-03
Status: approved (pre-implementation)

## Problem

Stream an emulation frontend from the Fedora/Hyprland host (57" 32:9 main
monitor) to the Shield TV (16:9, Moonlight) with controller-only operation.
Steam streaming over Sunshine already works; everything emulation-side is
greenfield: no ES-DE, no emulators, no ROM access, no window routing, no
exit hotkeys. ROMs live on Unraid (Nimbus) already in ES-DE's per-system
layout, BIOS included. Requirements: the main monitor and desktop session
stay untouched while streaming; ES-DE persists between streams (reconnect
resumes where you left off); everything reproducible from dotfiles, gated
to the personal machine profile so work machines are unaffected.

## Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| 16:9 isolation | Dummy HDMI/DP plug in a spare GPU port; Sunshine KMS capture targets its connector | Real DRM connector → fastest (DMABUF) capture path, zero protocol risk, works on any GPU driver. User chose hardware after survey (see below). |
| Rejected alternatives | Hyprland headless output; `video=DP-x:...e` + firmware EDID; krfb-virtual-monitor; gamescope; monitor mode switch; 32:9 letterbox | Headless: no DRM connector, capture fragile. Forced connector: always-on, driver-dependent, boot param. krfb: KWin/Plasma-only. Gamescope nested-on-Hyprland: flakiest pairing. Mode switch: touches main monitor. 32:9: 2x wasted encode. |
| Stream resolution | Virtual output pinned to 3840x2160@60 | 4K dongle + 4K TV + Shield's 4K/HEVC decode (the reason the Shield was chosen over the Pi 4). Needs a wired Shield connection for the ~100+ Mbps HEVC bitrate; 1080p remains a one-value fallback if latency disappoints. Emulator internal upscaling is independent of output mode. |
| Session lifecycle | Persistent ES-DE; teardown on demand | Reconnect drops back into place. Prep is idempotent ensure, not create/teardown. A second Sunshine app "Emulation (Stop)" gives couch-side teardown. |
| ROM access | systemd automount, CIFS from Nimbus at `/mnt/nimbus/roms` | `x-systemd.automount,nofail,soft` — down server never hangs boot or Sunshine; ES-DE just shows no systems. Chosen over NFS (share already speaks SMB). |
| Saves/states | Local on host | Avoids CIFS locking/latency issues on write-heavy state. |
| Emulator install | RetroArch/Dolphin/PCSX2 from Fedora repos; ES-DE AppImage via GearLever | GearLever is the established AppImage pattern in this repo. Exact package names verified during implementation; Flatpak is the fallback. |
| Exit convention | Select+Start = quit emulator → ES-DE, everywhere; L3+R3 = RetroArch menu | One muscle memory across all emulators. |
| Chezmoi gating | `[data.machine] profile = "personal"` (opencode.json.tmpl precedent) | hyprland.lua becomes `.tmpl` with the emulation block conditional; new files excluded on other machines via templated `.chezmoiignore`. |
| Sunshine config ownership | `apps.json` chezmoi-managed whole (existing entries preserved); `sunshine.conf` stays hand-managed | Working Steam capture config is too valuable to clobber; runbook documents the two manual keys (`capture = kms`, `output_name`). |
| Hyprland routing | New persistent `emulation` workspace bound to the dongle monitor; new `emulationWindows` table | Mirrors the existing `gamingWs`/`gamingWindows` pattern; Steam workflow untouched; apps arrive silently so desktop focus never moves. |
| Couch revision (2026-10-04) | `emulation` ws renamed `couch`; SUPER+SHIFT+E toggles it dongle ↔ 57"; new "Steam (Couch)" app installs a session-scoped runtime rule (`hyprctl eval 'hl.window_rule({ ... workspace = "couch silent" })'` routing `steam`/`steam_app_*` → couch — `hyprctl keyword` is rejected by Lua-first 0.56.2) and drops it via `hyprctl reload` on exit | Static rules can't distinguish couch-launched Steam games from locally-launched ones (identical window classes), so origin-based routing must be dynamic and session-scoped. Rename reflects that the dongle workspace hosts more than emulation. |

## Components

### 1. `dot_config/hypr/hyprland.lua.tmpl` (rename + edit)

Wrap current content unchanged; add a personal-profile-gated emulation block:

- Monitor entry for the dongle connector at `3840x2160@60`. The output
  participates in Hyprland like any second monitor (pointer can
  edge-cross onto it — harmless given silent routing), but no window or
  focus ever lands there except via the rules below.
- `hl.workspace_rule({ workspace = "name:couch", persistent = true })`
  bound to the dongle monitor.
- `emulationWindows` table (same shape as `gamingWindows`): `^es-de$`,
  `^retroarch$`, Dolphin, PCSX2 classes — verified via `hyprctl`
  `initialClass` at implementation; all routed `couch silent`.
- SUPER+SHIFT+E toggle: moves `name:couch` between the dongle and the
  Samsung for local play (dongle keeps its empty default while local).

### 2. `dot_local/bin/executable_es-session` (new)

`start|stop|status`, idempotent:

- `start`: verify dongle connector present (`hyprctl monitors`), warn (via
  `noctalia msg notification-show`) if the ROM mount is down, then launch
  ES-DE on the couch workspace only if not already running (`pgrep`).
- `stop`: SIGTERM any running emulator, then ES-DE; no display/monitor
  changes (dongle is always-on).
- `status`: report connector, mount, ES-DE/emulator PIDs. Exit codes
  distinguish states for scripting.

### 3. `run_once_install-nimbus-roms-mount.sh.tmpl` (new)

Sudo `run_once` (resolved.conf precedent), personal-profile gated:
installs a systemd `.automount`/`.mount` pair for `//Nimbus/<share>` at
`/mnt/nimbus/roms` and a chmod-600 credentials file (prompted, never
committed). Share name is a chezmoi data variable.

### 4. `dot_config/sunshine/apps.json` (new, managed whole)

Existing working entries preserved (the stock X11 `xrandr` "Low Res
Desktop" relic is dead on Wayland and gets dropped); adds:

- "Emulation": `detached = es-session start` (no cover-art file
  dependency; Sunshine's default icon).
- "Emulation (Stop)": `detached = es-session stop`.
- "Steam (Couch)": `prep-cmd` `do` installs the runtime window rule
  (`hyprctl eval 'hl.window_rule({ ... workspace = "couch silent" })'`;
  `steam`/`steam_app_*` classes) then detaches
  `flatpak run com.valvesoftware.Steam steam://open/bigpicture`;
  `prep-cmd` `undo` closes Big Picture and runs `hyprctl reload` to drop
  the eval-added rule. The pre-existing "Steam Big Picture" entry is
  preserved for local/desktop use (now launched via the Flatpak — no
  host `steam` binary exists).

### 5. Emulator configs (new, chezmoi-managed)

- `retroarch.cfg`: hotkey enable (Select) + quit (Start), L3+R3 menu
  toggle, fullscreen on the dongle output, latency settings
  (`video_hard_sync` et al., exact set tuned during implementation),
  Vulkan driver.
- Dolphin/PCSX2: fullscreen + exit hotkeys are configured through each
  emulator's settings UI, with exact click-paths in the runbook — their
  ini hotkey tokens encode device-specific controller button IDs, which
  makes seeded config files unreliable. Runtime-mutated inis stay out of
  git per `.chezmoiignore` conventions.

### 6. ES-DE config + runbook (new)

- `es_settings.xml` is runtime-mutated by ES-DE (scraper, UI settings),
  so it is not chezmoi-managed; the ROM directory is pointed at
  `/mnt/nimbus/roms` via ES-DE's first-run wizard.
- `docs/` runbook: package install commands, GearLever AppImage import,
  the two manual `sunshine.conf` keys with the connector name discovered
  from `hyprctl monitors`, pairing notes.

## Data flow

```
Moonlight "Emulation" (Shield)
  → Sunshine session → detached es-session.sh start
  → connector check / mount warn / pgrep-or-launch ES-DE
  → window rule routes ES-DE to couch ws on dongle (silent)
  → Sunshine KMS capture of dongle connector only → HEVC stream
  → play: ES-DE launches RetroArch/Dolphin/PCSX2 → same routing
  → exit: Select+Start → emulator quits → ES-DE regains focus
  → disconnect stream: nothing changes on host (persistent)
  → reconnect: same ES-DE state, resume
  → "Emulation (Stop)" app: es-session.sh stop → clean teardown

Moonlight "Steam (Couch)" (Shield)
  → Sunshine session → prep-cmd installs runtime rule (hyprctl eval) → Big Picture opens
  → rule routes steam + steam_app_* windows to couch ws (silent)
  → games launched from Big Picture land on the dongle too
  → session end: undo closes Big Picture + hyprctl reload drops the rule
```

## Error handling

- Nimbus down: automount mount attempt times out (`soft`, timeout tuned);
  `start` warns, ES-DE shows no systems; boot unaffected (`nofail`).
- Dongle missing/unplugged: `start`/`status` report it; Sunshine stream
  with an invalid `output_name` fails visibly at the client — runbook
  tells you to check `status` first.
- Emulator hung: `stop` escalates SIGTERM → SIGKILL after timeout.
- ES-DE crashed mid-session: next `start` relaunches (idempotent).

## Testing

1. Automount: `ls /mnt/nimbus/roms` after idle boot mounts on access;
   boot with Nimbus off completes normally.
2. Routing: launch ES-DE locally, `hyprctl -j clients` shows it on
   `couch` ws on the dongle monitor; desktop focus unmoved.
3. Script: `es-session.sh start` twice → one ES-DE PID; `status` output
   accurate; `stop` clears PIDs.
4. Stream: Moonlight from Shield — 16:9 frame at 3840x2160 (Moonlight
   stats overlay), KMS capture confirmed in
   Sunshine logs, audio/video/controller input working.
5. Input: Select+Start exits each emulator back to ES-DE; L3+R3 opens
   the RetroArch menu.
6. Persistence: drop stream, reconnect → same ES-DE state.
7. Couch toggle: bind moves `couch` ws to the Samsung and back; gaming
   ws stays on DP-5. Steam (Couch): with the runtime rule installed,
   steam/steam_app windows open on couch; after undo + reload they open
   on gaming again.

## Risks / assumptions

- Sunshine KMS capture requires elevated DRM access (Fedora package
  ships capabilities, else `setcap cap_sys_admin+ep`); verified first
  during implementation.
- Connector name (`card0-HDMI-A-1` style) must be pinned after the dongle
  is physically installed; documented in the runbook.
- Window classes for Dolphin/PCSX2 under Wayland/XWayland verified at
  implementation (`hyprctl clients`), rules adjusted before commit.
- Exact Fedora package names for emulators verified at implementation;
  Flatpak fallback documented if a package is missing/stale.
- First ROM access after idle pays the automount penalty (seconds);
  acceptable, noted in runbook.
- 4K60 HEVC encode assumes a host GPU encoder (NVENC/VAAPI) comfortable
  at that rate; Shield must be on Ethernet. If either fails, the monitor
  entry + Moonlight resolution drop to 1080p60 with no other changes.
- Steam (Couch) relies on Sunshine running `undo` on session end; a hard
  client drop leaves a stale runtime rule that the next `hyprctl reload`
  (or any config apply) clears. A mid-session manual reload drops the
  rule early — subsequently launched couch games land on gaming until
  the session restarts.

## Out of scope

- HDR streaming (HEVC main10 / TV tone mapping — separate can of worms;
  revisit later).
- 1080p fallback profile (documented one-liner, not built out).
- Additional emulators beyond RetroArch/Dolphin/PCSX2 day one (the
  routing tables and configs are one-line extensions).
- Changes to the existing Steam streaming workflow (the "Steam (Couch)"
  entry is purely additive).
- Shield-side configuration beyond stock Moonlight.
- ES-DE scraping/themes, netplay, achievements.
