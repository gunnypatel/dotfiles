# Couch Emulation Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stream ES-DE + RetroArch/Dolphin/PCSX2 from the Hyprland host to the Shield TV via Sunshine, with a 4K dummy-plug output isolated from the desktop, ROMs automounted from Nimbus, and controller-only exit paths.

**Architecture:** A dummy plug presents a real 4K DRM connector that Hyprland pins to 3840x2160@60; a `couch` workspace bound to that output receives ES-DE and all emulators via silent window rules; Sunshine KMS-captures only that connector. An idempotent `es-session` script manages the persistent ES-DE process; a systemd automount serves the CIFS ROM share. Everything lands in chezmoi gated on the `personal` machine profile.

**Tech Stack:** Hyprland 0.56.x (Lua config), Sunshine (KMS capture), Moonlight (Shield), systemd mount units, CIFS, POSIX sh, chezmoi templating.

**Spec:** `docs/superpowers/specs/2026-10-03-couch-emulation-streaming-design.md`

**Hardware dependency:** Tasks 1–5, the apps.json half of 7, 8, and 10 are executable before the dongle arrives. Tasks 6, the sunshine.conf half of 7, 9's verification, and 11 need the dongle plugged in (and a controller paired for input tests).


> **Progress (2026-10-03, pre-dongle session):** Tasks 1, 2, 5, and 10 complete; Task 3 script committed (system steps pending creds file); Task 4 AppImage installed, dnf installs pending; Task 7 apps.json done and capture privileges verified (`cap_sys_admin` present) — KMS keys and client checks pending dongle; Task 8 config deployed, runtime checks pending RetroArch install. All deferred steps are in `docs/gaming/couch-emulation-streaming.md`. Work lives on branch `feature/couch-emulation-streaming`.
---

## File Structure

| File | Responsibility |
|---|---|
| `dot_config/hypr/hyprland.lua.tmpl` (rename of `hyprland.lua`) | Hyprland config; gains personal-gated dongle monitor entry + emulation workspace/window routing |
| `.chezmoiignore.tmpl` (rename of `.chezmoiignore`) | Ignore rules; gains Sunshine/RetroArch runtime-state guards and personal-only emulation files |
| `run_once_install-nimbus-roms-mount.sh.tmpl` | Installs `/etc/systemd/system/mnt-nimbus-roms.{mount,automount}` via sudo |
| `dot_local/bin/executable_es-session` | Session manager: `start\|stop\|status` |
| `dot_config/sunshine/apps.json` | Sunshine app grid; gains Emulation entries |
| `dot_config/retroarch/retroarch.cfg` | RetroArch streaming/hotkey config (runtime saves disabled) |
| `docs/gaming/couch-emulation-streaming.md` | Runbook: one-time setup, daily operation, troubleshooting |
| `~/.config/chezmoi/chezmoi.toml` (machine-local, never committed) | Gains `[data.nimbus] romsShare` |

---

### Task 1: Template gating infrastructure

Convert `hyprland.lua` and `.chezmoiignore` to templates so later tasks can gate emulation content on the personal profile. This task changes **no behavior** — rendered output must stay byte-identical on this machine.

**Files:**
- Rename: `dot_config/hypr/hyprland.lua` → `dot_config/hypr/hyprland.lua.tmpl`
- Rename: `.chezmoiignore` → `.chezmoiignore.tmpl`

- [x] **Step 1: Capture current rendered output**

```bash
mkdir -p /tmp/opencode && chezmoi cat ~/.config/hypr/hyprland.lua > /tmp/opencode/hyprland-before.lua
```

- [x] **Step 2: Rename both files**

```bash
git mv dot_config/hypr/hyprland.lua dot_config/hypr/hyprland.lua.tmpl
git mv .chezmoiignore .chezmoiignore.tmpl
```

- [x] **Step 3: Add the template header to hyprland.lua.tmpl**

Prepend exactly this above the existing first line:

```
{{- /* Emulation streaming additions (couch stack) are emitted only on
   personal machines — set [data.machine] profile = "personal" in
   chezmoi.toml (opencode.json.tmpl precedent). */ -}}
```

- [x] **Step 4: Extend .chezmoiignore.tmpl**

Prepend the profile header at the very top:

```
{{- /* Personal-machine gating: the emulation streaming stack (see
   docs/superpowers/specs/2026-10-03-couch-emulation-streaming-design.md)
   is excluded on machines whose [data.machine] profile is not
   "personal", mirroring the opencode.json.tmpl freecad gate. */ -}}
{{- $profile := dig "machine" "profile" "" . -}}
```

Append at the very end:

```

# sunshine: apps.json is managed; state/log/credentials are Sunshine's own
.config/sunshine/sunshine_state.json
.config/sunshine/sunshine.log
.config/sunshine/credentials

# retroarch: retroarch.cfg is managed; runtime state is not
.config/retroarch/saves
.config/retroarch/states
.config/retroarch/playlists
.config/retroarch/thumbnails
.config/retroarch/autoconfig

{{- if ne $profile "personal" }}
# Personal-only emulation stack (never applied to work machines)
.local/bin/es-session
.config/retroarch/retroarch.cfg
.config/sunshine/apps.json
{{- end }}
```

- [x] **Step 5: Verify nothing changed**

```bash
chezmoi cat ~/.config/hypr/hyprland.lua | diff - /tmp/opencode/hyprland-before.lua
chezmoi execute-template < .chezmoiignore.tmpl | grep -c es-session
```

Expected: diff exits 0 (no output); grep count is `0` (this machine is personal, so the exclusion block renders away).

- [x] **Step 6: Commit**

```bash
git add -A && git commit -m "Convert hyprland config and chezmoiignore to templates"
```

---

### Task 2: chezmoi data for the ROM share (machine-local, no commit)

**Files:**
- Modify: `~/.config/chezmoi/chezmoi.toml` (not in the repo — never committed)

- [x] **Step 1: Add the nimbus table**

Append to `~/.config/chezmoi/chezmoi.toml` (replace `roms` with the actual Unraid share name if different):

```toml
[data.nimbus]
  romsShare = "//Nimbus/roms"
```

- [x] **Step 2: Verify the variable resolves**

```bash
chezmoi execute-template '{{ dig "nimbus" "romsShare" "" . }}'
```

Expected output: `//Nimbus/roms`

---

### Task 3: Nimbus ROM automount installer

**Files:**
- Create: `run_once_install-nimbus-roms-mount.sh.tmpl`

- [ ] **Step 1: Create the credentials file (one-time, manual — secrets never enter the repo)**

```bash
sudo sh -c 'printf "username=YOUR_UNRAID_USER\npassword=YOUR_UNRAID_PASSWORD\n" > /etc/cifs-creds-nimbus && chmod 600 /etc/cifs-creds-nimbus'
```

Expected: no output. (Add a `domain=WORKGROUP` line only if the Unraid share requires one.)

- [x] **Step 2: Write `run_once_install-nimbus-roms-mount.sh.tmpl`**

```
{{- if and (eq .chezmoi.os "linux") (eq (dig "machine" "profile" "" .) "personal") -}}
#!/usr/bin/env bash
# Install the systemd automount for the Nimbus ROM share (CIFS) at
# /mnt/nimbus/roms. Renders to nothing (not executed) on non-personal or
# non-Linux machines. Idempotent: units are only rewritten when content
# changes; editing this script changes its hash, so chezmoi re-runs it.
#
# Prerequisites (see docs/gaming/couch-emulation-streaming.md):
#   - /etc/cifs-creds-nimbus (chmod 600, created manually)
#   - [data.nimbus] romsShare = "//Nimbus/roms" in chezmoi.toml
set -euo pipefail

SHARE='{{ dig "nimbus" "romsShare" "" . }}'
CREDS=/etc/cifs-creds-nimbus
MP=/mnt/nimbus/roms
MY_UID=$(id -u)
MY_GID=$(id -g)

if [[ -z "$SHARE" ]]; then
    echo "chezmoi: nimbus.romsShare not set — skipping ROM mount install"
    exit 0
fi
if [[ ! -f "$CREDS" ]]; then
    echo "chezmoi: missing $CREDS — create it, then re-run: chezmoi apply"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/mnt-nimbus-roms.mount" <<EOF
[Unit]
Description=Nimbus ROM library (CIFS)

[Mount]
What=$SHARE
Where=$MP
Type=cifs
Options=credentials=$CREDS,uid=$MY_UID,gid=$MY_GID,file_mode=0644,dir_mode=0755,soft,nofail,_netdev
TimeoutSec=30

[Install]
WantedBy=multi-user.target
EOF

cat > "$TMP/mnt-nimbus-roms.automount" <<EOF
[Unit]
Description=Automount Nimbus ROM library on access

[Automount]
Where=$MP
TimeoutIdleSec=600

[Install]
WantedBy=multi-user.target
EOF

TOUCHED=0
for unit in mnt-nimbus-roms.mount mnt-nimbus-roms.automount; do
    if cmp -s "/etc/systemd/system/$unit" "$TMP/$unit" 2>/dev/null; then
        continue
    fi
    sudo install -m 0644 -o root -g root "$TMP/$unit" "/etc/systemd/system/$unit"
    echo "chezmoi: installed $unit"
    TOUCHED=1
done

if [[ "$TOUCHED" == 1 ]]; then
    sudo systemctl daemon-reload
fi
sudo systemctl enable --now mnt-nimbus-roms.automount
echo "chezmoi: ROM automount ready at $MP"
{{- end -}}
```

- [ ] **Step 3: Apply and verify the units installed**

```bash
chezmoi apply
systemctl status mnt-nimbus-roms.automount
```

Expected: apply prints both "installed" lines and "automount ready"; status shows `active (waiting)`.

- [ ] **Step 4: Verify mount-on-access and content**

```bash
ls /mnt/nimbus/roms
findmnt /mnt/nimbus/roms
```

Expected: `ls` triggers the mount after a ~1s pause and lists the ES-DE per-system folders (snes, gba, …); findmnt shows a `cifs` FSType entry.

- [ ] **Step 5: Verify idempotency**

```bash
chezmoi apply
```

Expected: no "installed" lines (units unchanged), still "automount ready".

- [x] **Step 6: Commit**

```bash
git add run_once_install-nimbus-roms-mount.sh.tmpl && git commit -m "Add Nimbus ROM automount installer"
```

---

### Task 4: Install emulators and ES-DE (system state, no commit)

- [x] **Step 1: Verify package availability**

```bash
dnf info retroarch dolphin-emu pcsx2 2>&1 | grep -E '^(Name|Error)' 
```

Expected: three `Name:` lines. If any package is missing, enable RPM Fusion free (`sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm`) and re-check; Flatpak is the documented fallback in the runbook.

- [ ] **Step 2: Install**

```bash
sudo dnf install retroarch dolphin-emu pcsx2
```

- [ ] **Step 3: Record the exact binary names (es-session EMULATORS must match)**

```bash
rpm -ql retroarch dolphin-emu pcsx2 | grep -E 'bin/' 
retroarch --version
```

Expected: binaries such as `/usr/bin/retroarch`, `/usr/bin/dolphin-emu`, `/usr/bin/pcsx2-qt` (or `pcsx2`). Write down the emulator names — Task 5's `EMULATORS` list uses them.

- [ ] **Step 4: Install RetroArch cores for the systems in the library**

```bash
dnf search libretro | head -40
```

From the results, `sudo dnf install` the core packages whose names match the system folders in `/mnt/nimbus/roms` (e.g. `libretro-snes9u` for `snes/`, a Game Boy core for `gb/`/`gba/`). Record the installed package list for the runbook (Task 10).

- [x] **Step 5: Install ES-DE AppImage**

Download the latest `ES-DE_x64.AppImage` from `https://gitlab.com/es-de/emulationstation-de/-/releases` (Steam Deck/package-agnostic asset) into `~/AppImages`:

```bash
mkdir -p ~/AppImages && mv ~/Downloads/ES-DE*AppImage ~/AppImages/es-de.AppImage
chmod +x ~/AppImages/es-de.AppImage
~/AppImages/es-de.AppImage --version
```

Expected: version banner, clean exit. GearLever can manage updates afterwards (existing `~/AppImages` pattern); `es-session` invokes `~/AppImages/es-de.AppImage` directly so it works either way.

---

### Task 5: es-session session manager

**Files:**
- Create: `dot_local/bin/executable_es-session`

- [x] **Step 1: Write `dot_local/bin/executable_es-session`**

Adjust `EMULATORS` to the binary names recorded in Task 4 Step 3 if they differ.

```sh
#!/bin/sh
# Couch-emulation session manager (Sunshine "Emulation" apps):
#   start    idempotently ensure ES-DE is running (persistent between
#            streams — reconnect resumes where you left off)
#   stop     terminate any running emulators, then ES-DE (on demand)
#   status   report dongle connector / ROM mount / processes
# Exit codes: 2 usage; 4 ES-DE binary missing. Dongle/mount absence is a
# warning (notification), never fatal — ES-DE still launches locally.
# See docs/superpowers/specs/2026-10-03-couch-emulation-streaming-design.md
set -eu

ESDE_BIN="${ESDE_BIN:-$HOME/AppImages/es-de.AppImage}"
MOUNT_POINT=/mnt/nimbus/roms
DONGLE_DESC="${DONGLE_DESC:-dummy}"
EMULATORS="retroarch dolphin-emu pcsx2-qt"

notify() {
    noctalia msg notification-show "$1" "$2" 2>/dev/null || true
}

dongle_present() {
    hyprctl -j monitors | python3 -c '
import json, sys
needle = sys.argv[1].lower()
found = any(needle in m.get("description", "").lower() for m in json.load(sys.stdin))
sys.exit(0 if found else 1)' "$DONGLE_DESC"
}

mount_present() {
    findmnt -rn "$MOUNT_POINT" >/dev/null
}

emus_running() {
    for p in $EMULATORS; do
        pgrep -x "$p" >/dev/null && return 0
    done
    return 1
}

cmd_start() {
    dongle_present || notify "Emulation" "Dongle output not found (desc ~ '$DONGLE_DESC')"
    mount_present || notify "Emulation" "ROM mount $MOUNT_POINT not mounted"
    if pgrep -x es-de >/dev/null; then
        exit 0
    fi
    if [ ! -x "$ESDE_BIN" ]; then
        notify "Emulation" "ES-DE not found: $ESDE_BIN"
        echo "es-session: ES-DE binary missing: $ESDE_BIN" >&2
        exit 4
    fi
    setsid -f "$ESDE_BIN" >/dev/null 2>&1
}

wait_gone() {  # wait_gone PATTERN — up to 5s for all matches to exit
    i=0
    while pgrep -x "$1" >/dev/null && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
}

cmd_stop() {
    for p in $EMULATORS; do
        pkill -x -TERM "$p" 2>/dev/null || true
    done
    for p in $EMULATORS; do
        wait_gone "$p"
        pkill -x -KILL "$p" 2>/dev/null || true
    done
    pkill -x -TERM es-de 2>/dev/null || true
    wait_gone es-de
    pkill -x -KILL es-de 2>/dev/null || true
    notify "Emulation" "Session stopped"
}

cmd_status() {
    rc=0
    if dongle_present; then
        echo "dongle:    present"
    else
        echo "dongle:    ABSENT (description must contain: $DONGLE_DESC)"
        rc=1
    fi
    if mount_present; then
        echo "rom mount: mounted ($MOUNT_POINT)"
    else
        echo "rom mount: not mounted"
        rc=1
    fi
    if pgrep -x es-de >/dev/null; then
        echo "es-de:     running ($(pgrep -x es-de | tr '\n' ' '))"
    else
        echo "es-de:     not running"
    fi
    for p in $EMULATORS; do
        pgrep -x "$p" >/dev/null && echo "$p: running ($(pgrep -x "$p" | tr '\n' ' '))"
    done
    exit "$rc"
}

case "${1:-}" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    *) echo "usage: es-session start|stop|status" >&2; exit 2 ;;
esac
```

- [x] **Step 2: Apply and verify status paths**

```bash
chezmoi apply
es-session status; echo "rc=$?"
```

Expected (pre-dongle): `dongle: ABSENT`, `rom mount: mounted`, `es-de: not running`, `rc=1`. A desktop notification about the dongle may appear only from `start`, not `status`.

- [x] **Step 3: Verify the missing-binary guard**

```bash
ESDE_BIN=/nonexistent es-session start; echo "rc=$?"
```

Expected: `rc=4`, notification shown.

- [x] **Step 4: Verify launch idempotency and stop (post Task 4)**

```bash
es-session start && sleep 2 && pgrep -x es-de
es-session start && sleep 2 && pgrep -x es-de
es-session stop && sleep 1; pgrep -x es-de || echo "es-de gone"
```

Expected: first `start` produces one PID; second `start` keeps the same PID (no relaunch); `stop` clears it ("es-de gone"). Note the ES-DE window will appear on the current workspace until Task 6's routing exists — close it with the pointer for now.

- [x] **Step 5: Commit**

```bash
git add dot_local/bin/executable_es-session && git commit -m "Add es-session session manager"
```

---

### Task 6: Hyprland emulation routing (needs dongle)

**Files:**
- Modify: `dot_config/hypr/hyprland.lua.tmpl`

- [ ] **Step 1: Plug the dongle in and record its description**

```bash
hyprctl monitors all
```

Expected: a second monitor entry with a 4K mode. Record its full `description:` string (e.g. `LSB Dummy Plug HD`). If the string doesn't contain a stable word like "dummy", set `DONGLE_DESC` in Task 5's script to a substring that uniquely matches it.

- [ ] **Step 2: Confirm the workspace-rule monitor syntax on the installed Hyprland**

Use the `hyprland-docs` skill: confirm that workspace rules accept a `monitor` field on Hyprland 0.56.x and the exact form `hl.workspace_rule` expects (this config's Lua API). Also confirm `output create`/headless is NOT involved (not used in this design).

- [ ] **Step 3: Add the gated monitor entry (MONITORS section, below the existing hl.monitor)**

Inside `dot_config/hypr/hyprland.lua.tmpl`, replace the template header comment's trailing line so the profile variable is defined, then append inside the MONITORS section:

```
{{- $profile := dig "machine" "profile" "" . -}}
```

(going directly under the existing header comment), and after the existing `hl.monitor({...})` call:

```lua
{{- if eq $profile "personal" }}
-- Couch-emulation dongle: 4K dummy plug on a spare GPU port. Sunshine
-- KMS-captures only this output; windows/focus reach it solely via the
-- emulation workspace rules further down. The pointer CAN edge-cross
-- onto it like any second monitor — harmless by design.
hl.monitor({
    output   = "desc:REPLACE_WITH_OBSERVED_DESCRIPTION",
    mode     = "3840x2160@60",
    position = "7680x0",
    scale    = 1,
})
{{- end }}
```

Substitute `REPLACE_WITH_OBSERVED_DESCRIPTION` with the description string recorded in Step 1.

- [ ] **Step 4: Add the gated emulation workspace + routing (after the gaming block, ~line 217)**

```lua
{{- if eq $profile "personal" }}
-- Emulation workspace: lives on the dongle output; Sunshine streams it to
-- the Shield. Same pattern as gamingWs above: apps arrive silently, so
-- desktop focus never moves. Classes verified via `hyprctl clients` on
-- first launch of each app (Step 6).
local emulationWs = "emulation"

local emulationWindows = {
    { class = "^es-de$" },
    { class = "^retroarch$" },
    { class = "^dolphin-emu" },
    { class = "^pcsx2" },
}

hl.workspace_rule({
    workspace = "name:" .. emulationWs,
    persistent = true,
    monitor    = "desc:REPLACE_WITH_OBSERVED_DESCRIPTION",
})

for i, entry in ipairs(emulationWindows) do
    hl.window_rule({
        name      = "emulation-ws-" .. i,
        match     = { class = entry.class, title = entry.title },
        workspace = emulationWs .. " silent",
    })
end
{{- end }}
```

Use the same dongle description in the `monitor` field.

- [ ] **Step 5: Apply and verify the monitor**

```bash
chezmoi apply
hyprctl monitors
```

Expected: dongle output listed at `3840x2160@60`, the 57" unchanged at 7680x2160@120 scale 1.25.

- [ ] **Step 6: Verify each app's window class, fix regexes if needed**

```bash
es-session start && sleep 3
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
```

Expected: an `es-de` row on workspace `emulation`. Repeat for one emulator of each type (`retroarch` from a terminal, launch `dolphin-emu` and `pcsx2-qt` from the app grid, then close them). If a class differs from the regex table, correct `emulationWindows` and re-apply. Desktop focus must stay on your current workspace throughout.

- [ ] **Step 7: Commit**

```bash
git add dot_config/hypr/hyprland.lua.tmpl && git commit -m "Add Hyprland emulation routing to dongle output"
```

---

### Task 7: Sunshine integration

**Files:**
- Create: `dot_config/sunshine/apps.json`

- [x] **Step 1: Bring the live file under chezmoi management**

```bash
chezmoi add ~/.config/sunshine/apps.json
```

- [x] **Step 2: Edit `dot_config/sunshine/apps.json` to the final content**

Drops the stock `xrandr` "Low Res Desktop" entry (dead on Wayland); preserves Desktop + Steam Big Picture; adds the emulation apps:

```json
{
    "env": {
        "PATH": "$(PATH):$(HOME)/.local/bin"
    },
    "apps": [
        {
            "name": "Desktop",
            "image-path": "desktop.png"
        },
        {
            "name": "Steam Big Picture",
            "detached": [
                "setsid steam steam://open/bigpicture"
            ],
            "prep-cmd": [
                {
                    "do": "",
                    "undo": "setsid steam steam://close/bigpicture"
                }
            ],
            "image-path": "steam.png"
        },
        {
            "name": "Emulation",
            "detached": [
                "setsid -f es-session start"
            ]
        },
        {
            "name": "Emulation (Stop)",
            "detached": [
                "setsid -f es-session stop"
            ]
        }
    ]
}
```

- [x] **Step 3: Apply and verify Sunshine parsed it**

```bash
chezmoi apply
systemctl --user list-units | grep -i sunshine
systemctl --user restart sunshine
```

Check the Sunshine Web UI (`https://localhost:47990` → Applications): "Emulation" and "Emulation (Stop)" listed alongside Desktop/Steam; no parse errors in `~/.config/sunshine/sunshine.log`.

- [ ] **Step 4: Configure KMS capture (needs dongle) — sunshine.conf stays hand-managed**

Discover the DRM connector name:

```bash
for c in /sys/class/drm/card*-HDMI-* /sys/class/drm/card*-DP-*; do
  echo "$(basename "$c"): $(cat "$c/status")"
done
```

Expected: the dongle's connector (e.g. `card1-HDMI-A-1`) shows `connected`. Add to `~/.config/sunshine/sunshine.conf`:

```ini
capture = kms
output_name = card1-HDMI-A-1
```

(substituting the observed connector).

- [x] **Step 5: Verify capture privileges survive**

```bash
getcap "$(readlink -f "$(command -v sunshine)")"
```

Expected: includes `cap_sys_admin`. If empty, run `sudo setcap cap_sys_admin+p <that path>` and note it in the runbook's maintenance section (package updates can reset it).

- [ ] **Step 6: Verify from the client**

On the Shield, open Moonlight → this host: the app grid shows Emulation entries. (Streaming quality is Task 11.)

- [x] **Step 7: Commit**

```bash
git add dot_config/sunshine/apps.json && git commit -m "Manage Sunshine apps with emulation entries"
```

---

### Task 8: RetroArch streaming config

**Files:**
- Create: `dot_config/retroarch/retroarch.cfg`

- [x] **Step 1: Write `dot_config/retroarch/retroarch.cfg`**

```ini
# Managed by chezmoi. Runtime saves are disabled so this file stays as
# deployed — change settings here, not in the RetroArch UI (which would
# otherwise rewrite the file on exit). RetroArch fills every unset
# option from compiled defaults.
# Stack: docs/superpowers/specs/2026-10-03-couch-emulation-streaming-design.md

config_save_on_exit = "false"

# Video: window opens on the dongle output (Hyprland routing); SDL
# fullscreen follows the window's output.
video_driver = "vulkan"
video_fullscreen = "true"
video_vsync = "true"
# Stream latency is encoder-side; hard sync only adds local GPU stalls.
video_hard_sync = "false"

# Controller exit convention (RetroPad indices: 2 = Select, 3 = Start):
#   Select (hold) + Start   quit emulator -> back to ES-DE
#   L3 + R3                 RetroArch menu (gamepad combo 2)
input_enable_hotkey_btn = "2"
input_exit_emulator_btn = "3"
input_menu_toggle_gamepad_combo = "2"
```

- [ ] **Step 2: Apply and verify config integrity**

```bash
chezmoi apply
retroarch --verbose --menu & sleep 4; kill %1
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
chezmoi diff ~/.config/retroarch/retroarch.cfg
```

Expected: RetroArch appears as a client on workspace `emulation` (the dongle output has no physical screen — position/visibility is verified here by JSON, and visually only through a Moonlight test stream); `chezmoi diff` reports nothing for the managed file (runtime saves disabled, file untouched by the run).

- [ ] **Step 3: Verify input combos with a controller**

With a paired controller (USB locally, or through a Moonlight test stream), in the RetroArch menu: L3+R3 toggles the menu; Select(hold)+Start quits the process. If the combo values differ on this build, correct them here and note the working values in the runbook.

- [x] **Step 4: Commit**

```bash
git add dot_config/retroarch/retroarch.cfg && git commit -m "Add RetroArch streaming config"
```

---

### Task 9: Dolphin and PCSX2 UI configuration (manual, needs dongle + controller)

Their ini hotkey tokens encode device-specific button IDs, so hotkeys are mapped through each UI once — click-paths land in the runbook (Task 10). No repo changes in this task.

- [ ] **Step 1: Dolphin fullscreen + exit hotkey**

Launch `dolphin-emu`. Bind the exit hotkey: **Options → Hotkey Settings → Exit → (click the binding field) → hold Select, press Start**. For start-in-fullscreen: if a fullscreen-on-start toggle exists in **Options → Configure…**, enable it; otherwise enable **View → Fullscreen** once, quit, then locate the persisted key:

```bash
grep -ri fullscreen ~/.config/dolphin-emu/*.ini
```

and set that key to `True` in the ini. Verify via `hyprctl -j clients` (Dolphin lands on workspace `emulation`) and, visually, through a Moonlight test stream: fullscreen on the dongle output, Select+Start exits.

- [ ] **Step 2: PCSX2 fullscreen + shutdown hotkey**

Launch `pcsx2-qt`. **Settings → Hotkeys**: bind **Toggle Fullscreen**, and the shutdown/close entry (search the list for "Shutdown"/"Close"), each to Select(hold)+Start or the same convention. Set start-in-fullscreen under **Settings → Graphics or Interface** if present. Verify as with Dolphin (hyprctl JSON + a streamed check).

- [ ] **Step 3: End-to-end exit check per emulator**

Launch one GameCube game and one PS2 game from the ES-DE grid (streamed or local): each opens fullscreen on the dongle; Select+Start returns to the ES-DE grid with the emulator process gone (`pgrep -x dolphin-emu`, `pgrep -x pcsx2-qt` empty).

---

### Task 10: Runbook

**Files:**
- Create: `docs/gaming/couch-emulation-streaming.md`

- [x] **Step 1: Write the runbook**

Cover, in this order: overview diagram (Shield → Moonlight → Sunshine → dongle output → emulation ws); one-time setup in dependency order (creds file, chezmoi.toml `[data.nimbus]`, dnf packages, ES-DE AppImage, `chezmoi apply`, dongle + sunshine.conf keys with the exact discovery commands from Tasks 6–7, `setcap` note, ES-DE first-run wizard pointing at `/mnt/nimbus/roms`, the Task 9 click-paths); daily operation (Moonlight "Emulation" / "Emulation (Stop)"); troubleshooting matrix (stream fails → `es-session status` + `output_name`; no systems in ES-DE → mount; window on wrong screen → class regex; no input → Moonlight input settings); maintenance (Sunshine updates reset capabilities, dongle desc changes, 4K↔1080p = hyprland mode value + Moonlight host resolution); which files are managed vs runtime.

- [x] **Step 2: Commit**

```bash
git add docs/gaming/couch-emulation-streaming.md && git commit -m "Add couch emulation runbook"
```

---

### Task 11: End-to-end verification (needs dongle + Shield + controller)

Mirrors the spec's Testing section. Each step must pass before the next.

- [ ] **Step 1: Automount** — after `sudo systemctl stop mnt-nimbus-roms.mount` (idle timeout or manual), `ls /mnt/nimbus/roms` re-mounts on access; reboot once with Nimbus powered off → boot completes normally.
- [ ] **Step 2: Routing** — `es-session start`; `hyprctl -j clients` shows es-de on workspace `couch`; desktop focus never moved.
- [ ] **Step 3: Script** — `start` twice → one PID; `status` accurate; `stop` clears everything.
- [ ] **Step 4: Stream** — Shield Moonlight → "Emulation": set the host's streaming resolution to 3840x2160@60 in Moonlight settings; stats overlay shows 4K + HEVC; Sunshine log confirms KMS backend; controller + audio work.
- [ ] **Step 5: Input** — Select+Start exits each emulator back to ES-DE; L3+R3 opens the RetroArch menu.
- [ ] **Step 6: Persistence** — drop the stream (Shield home), reconnect "Emulation": ES-DE state identical (same system view), no host-side cleanup ran.
- [ ] **Step 7: Teardown** — run "Emulation (Stop)" from Moonlight: emulator + ES-DE processes gone (`es-session status` shows not running), host desktop untouched throughout.

### Task 12: Couch workspace — local toggle + Steam (Couch)

Renames the `emulation` workspace to `couch`, adds a SUPER+SHIFT+E toggle
for local play on the 57", and adds a "Steam (Couch)" Moonlight entry that
routes Big Picture — and any game it launches — to the dongle for the
duration of the stream, via a runtime window rule installed by the launch
script. Static config never changes, so the local Steam/gaming workflow is
untouched.

**Files:**
- Modify: `dot_config/hypr/hyprland.lua.tmpl` (rename + toggle bind, personal-gated)
- Modify: `dot_config/sunshine/apps.json` (new entry)

- [x] **Step 1: Rename** — `emulationWs` value "emulation" → "couch" (rule, binds, comments; table name `emulationWindows` may stay). Grep repo docs for stale `emulation`-ws references.
- [x] **Step 2: Confirm mechanisms via `hyprland-docs`** — (a) toggle bind form on 0.56.x: `hl.bind` accepts a Lua function (`hl.get_workspace(...).monitor.description` + `hl.dispatch(hl.dsp.workspace.move({...}))`); (b) runtime rule via `hyprctl eval 'hl.window_rule({ name = ..., match = { class = "^(steam|steam_app_[0-9]+)$" }, workspace = "couch silent" })'` — 0.56.2 REJECTS `hyprctl keyword windowrule` on Lua-first configs ("keyword can't work with non-legacy parsers. Use eval.") — and `hyprctl reload` drops eval-added rules.
- [x] **Step 3: Implement toggle** — SUPER+SHIFT+E moves `name:couch` Samsung desc ↔ dongle desc; personal-gated.
- [x] **Step 4: Implement Steam (Couch)** — apps.json entry: `prep-cmd` `do` = runtime rule (`hyprctl eval` as above) + detached `flatpak run com.valvesoftware.Steam steam://open/bigpicture` (no host `steam` binary — Steam is the Flatpak); `prep-cmd` `undo` = `flatpak run com.valvesoftware.Steam steam://close/bigpicture` + `hyprctl reload`.
- [x] **Step 5: Verify rename + toggle live** — `chezmoi apply --exclude scripts ~/.config/hypr/hyprland.lua`; `hyprctl configerrors` empty; press the bind twice (dongle → Samsung → dongle); `hyprctl workspaces` confirms each move; gaming stays on DP-5.
- [x] **Step 6: Verify Steam (Couch) host-side** — run the prep-cmd `do` by hand, launch Big Picture detached: `hyprctl -j clients` shows the steam window on `couch`; run `undo`: rule gone after reload, a fresh steam window would route to gaming. Full grid test rides Task 11 with the Shield.
- [x] **Step 7: Commit** — single-purpose, no trailers.
