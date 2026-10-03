# Couch Emulation Streaming

Stream ES-DE and the RetroArch / Dolphin / PCSX2 emulators from the
Hyprland host to the Shield TV over Moonlight without touching the
desktop session: a 4K dummy plug presents a dedicated DRM connector that
Hyprland pins at 3840x2160@60, a persistent `emulation` workspace bound
to that output collects every emulator window via silent window rules,
and Sunshine KMS-captures only that connector. ROMs automount over CIFS
from Nimbus, and `es-session` gives idempotent start/stop/status from
the Sunshine app grid.

Rationale and rejected alternatives:
`docs/superpowers/specs/2026-10-03-couch-emulation-streaming-design.md`.
Task-by-task implementation (source of the commands below):
`docs/superpowers/plans/2026-10-03-couch-emulation-streaming.md`.

## Architecture

```
Shield TV (Moonlight, wired Ethernet recommended)
   │  HEVC over LAN (~100+ Mbps at 4K60)
   ▼
Sunshine (host user service, KMS capture)
   │  captures the dongle connector only
   ▼
4K dummy plug (spare GPU port, pinned 3840x2160@60)
   ▼
Hyprland "emulation" workspace (persistent, dongle-bound)
   │  silent window rules: ^es-de$, ^retroarch$, ^dolphin-emu, ^pcsx2
   ▼
ES-DE ── launches ──► RetroArch / Dolphin / PCSX2
   ▼
/mnt/nimbus/roms (CIFS automount from Nimbus, TimeoutIdleSec=600)
```

Daily flow: pick **Emulation** in Moonlight → Sunshine runs
`es-session start` → ES-DE launches (or is reused) on the emulation
workspace → play. Select(hold)+Start exits an emulator back to the ES-DE
grid; L3+R3 opens the RetroArch menu. Dropping the stream changes
nothing on the host (ES-DE persists between streams); **Emulation
(Stop)** tears the session down on demand.

## One-time setup

### Already in place on this machine

- chezmoi templates + `personal` profile gating; `.chezmoiignore.tmpl`
  runtime-state ignores
- `[data.nimbus] romsShare = "//Nimbus/roms"` in
  `~/.config/chezmoi/chezmoi.toml` (verify with
  `chezmoi execute-template '{{ dig "nimbus" "romsShare" "" . }}'` —
  expect `//Nimbus/roms`)
- `run_once_install-nimbus-roms-mount.sh.tmpl` committed (NOT yet
  executed with creds present — see step 2)
- ES-DE 3.5.0 AppImage at `~/AppImages/es-de.AppImage`, verified
  runnable
- `es-session` deployed at `~/.local/bin/es-session` (start/stop/status
  verified)
- Sunshine `apps.json` managed with Desktop / Steam Big Picture /
  Emulation / Emulation (Stop)
- `~/.config/retroarch/retroarch.cfg` deployed (8 keys; runtime saves
  disabled)

### 1. ROM share credentials (no dongle needed)

Secrets never enter the repo. Create the credentials file:

```bash
sudo sh -c 'printf "username=YOUR_UNRAID_USER\npassword=YOUR_UNRAID_PASSWORD\n" > /etc/cifs-creds-nimbus && chmod 600 /etc/cifs-creds-nimbus'
```

Expected: no output. Add a `domain=WORKGROUP` line only if the Unraid
share requires one.

### 2. Activate the ROM automount (no dongle needed)

**Do not rely on `chezmoi apply` here.** The `run_once` installer
already executed once WITHOUT creds present (graceful skip), so chezmoi
has recorded its hash — creating the creds file later and re-applying
will NOT re-run it. Render and install the units directly:

```bash
chezmoi execute-template < "$(chezmoi source-path)/run_once_install-nimbus-roms-mount.sh.tmpl" | sudo bash
```

Then verify. Chezmoi swallows successful `run_once` output, so never
rely on seeing (or not seeing) a skip message — always check the unit
state directly:

```bash
systemctl status mnt-nimbus-roms.automount   # expect: active (waiting)
ls /mnt/nimbus/roms                          # triggers the mount after a ~1s pause
findmnt /mnt/nimbus/roms                     # expect: a cifs entry
```

### 3. Install emulators and cores (no dongle needed)

All three packages are confirmed available in the repos:

```bash
sudo dnf install retroarch dolphin-emu pcsx2
```

Record the exact binary names — `es-session`'s `EMULATORS` list must
match them:

```bash
rpm -ql retroarch dolphin-emu pcsx2 | grep -E 'bin/'
retroarch --version
```

If the PCSX2 binary is `pcsx2` rather than `pcsx2-qt`, edit
`EMULATORS` in `dot_local/bin/executable_es-session` and run
`chezmoi apply`.

Install libretro cores matching the per-system folders now visible
under `/mnt/nimbus/roms`:

```bash
dnf search libretro | head -40
sudo dnf install libretro-<core> ...   # e.g. a snes core for snes/, a gb/gba core
```

### 4. When the dongle arrives

#### 4.1 Hyprland: dongle monitor + emulation routing

Plug the dongle in and record its description:

```bash
hyprctl monitors all
```

Expect a second monitor entry with a 4K mode. Record the full
`description:` string (e.g. `LSB Dummy Plug HD`). If it doesn't contain
a stable word like "dummy", set `DONGLE_DESC` in
`dot_local/bin/executable_es-session` to a substring that uniquely
matches it.

**Syntax caveat:** the workspace-rule `monitor` field used by this
config's `hl.workspace_rule` Lua API must be confirmed on the installed
Hyprland 0.56.x before relying on it (plan Task 6 Step 2 used the
`hyprland-docs` skill for this). `output create` / headless outputs are
NOT part of this design.

Edit `dot_config/hypr/hyprland.lua.tmpl`. First put the profile
variable directly under the existing template header comment:

```
{{- $profile := dig "machine" "profile" "" . -}}
```

Then add the monitor entry in the MONITORS section, below the existing
`hl.monitor` call:

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

And the workspace + window routing after the existing gaming block
(~line 217), using the same dongle description in `monitor`:

```lua
{{- if eq $profile "personal" }}
-- Emulation workspace: lives on the dongle output; Sunshine streams it
-- to the Shield. Same pattern as gamingWs above: apps arrive silently,
-- so desktop focus never moves. Classes verified via `hyprctl clients`
-- on first launch of each app (below).
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

Apply and verify the monitor:

```bash
chezmoi apply
hyprctl monitors
```

Expect the dongle at `3840x2160@60` and the 57" unchanged at
7680x2160@120 scale 1.25. Then verify each app's window class (expected
class for ES-DE is exactly `es-de`) and that it lands on the emulation
workspace:

```bash
es-session start && sleep 3
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
```

Expect an `es-de` row on workspace `emulation`, desktop focus unmoved.
Repeat for one emulator of each type (`retroarch` from a terminal,
launch `dolphin-emu` and `pcsx2-qt` from the app grid, then close
them). If a class differs from the regex table, correct
`emulationWindows` and re-apply.

#### 4.2 Sunshine: KMS capture + autostart

Discover the dongle's DRM connector name:

```bash
for c in /sys/class/drm/card*-HDMI-* /sys/class/drm/card*-DP-*; do
  echo "$(basename "$c"): $(cat "$c/status")"
done
```

Expect the dongle's connector (e.g. `card1-HDMI-A-1`) to show
`connected`. Add the two manual keys to `~/.config/sunshine/sunshine.conf`
(that file stays hand-managed by design):

```ini
capture = kms
output_name = card1-HDMI-A-1
```

(substituting the observed connector).

Verify capture privileges:

```bash
getcap "$(readlink -f "$(command -v sunshine)")"
```

Expect `cap_sys_admin`. If empty, run
`sudo setcap cap_sys_admin+p <that path>` — and see maintenance below,
because package updates can reset it.

The user service is **`app-dev.lizardbyte.app.Sunshine.service`** —
NOT `sunshine.service`; use the real name for every restart/enable. It
is currently DISABLED for autostart, so enable it once:

```bash
systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service
```

After conf changes, restart with the same name:

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
```

Sanity-check the Web UI (`https://localhost:47990` → Applications):
Emulation entries listed, no parse errors in
`~/.config/sunshine/sunshine.log`. On the Shield, Moonlight → this host
should show the Emulation entries in the grid.

#### 4.3 ES-DE first run

Launch locally with `es-session start`. The first-run wizard asks for
the ROM directory — point it at `/mnt/nimbus/roms`. `es_settings.xml`
is runtime-mutated by ES-DE (scraper, UI settings) and deliberately
NOT chezmoi-managed.

#### 4.4 RetroArch runtime verification

First launch must use the Wayland context, not SDL — Vulkan ICD issues
on the dongle GPU would surface here:

```bash
retroarch --verbose --menu & sleep 4; kill %1
```

Check the context driver in the verbose output (wayland expected). Then
confirm routing and that the run did not touch the managed config:

```bash
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
chezmoi diff ~/.config/retroarch/retroarch.cfg
```

Expect `retroarch` on workspace `emulation` and a clean `chezmoi diff`.

With a paired controller (USB locally, or through a Moonlight test
stream), verify the combos: L3+R3 toggles the RetroArch menu;
Select(hold)+Start quits the process. If the combo values differ on
this build, correct the `input_*` keys in
`dot_config/retroarch/retroarch.cfg` and note the working values here.

#### 4.5 Dolphin and PCSX2 hotkeys

Their ini hotkey tokens encode device-specific button IDs, so hotkeys
are mapped through each UI once:

- **Dolphin** — launch `dolphin-emu`. Bind the exit hotkey:
  **Options → Hotkey Settings → Exit → (click the binding field) →
  hold Select, press Start**. For start-in-fullscreen: if a
  fullscreen-on-start toggle exists in **Options → Configure…**,
  enable it; otherwise enable **View → Fullscreen** once, quit, then
  locate the persisted key:

  ```bash
  grep -ri fullscreen ~/.config/dolphin-emu/*.ini
  ```

  and set that key to `True` in the ini.

- **PCSX2** — launch `pcsx2-qt`. **Settings → Hotkeys**: bind
  **Toggle Fullscreen**, and the shutdown/close entry (search the list
  for "Shutdown"/"Close"), each to Select(hold)+Start or the same
  convention. Set start-in-fullscreen under **Settings → Graphics or
  Interface** if present.

- **Exit check per emulator** — launch one GameCube game and one PS2
  game from the ES-DE grid (streamed or local): each opens fullscreen
  on the dongle; Select+Start returns to the ES-DE grid with the
  emulator process gone (`pgrep -x dolphin-emu`, `pgrep -x pcsx2-qt`
  empty). Window placement is verified via the `hyprctl -j clients`
  one-liner above, plus a visual check through a Moonlight test stream.

### 5. End-to-end verification (needs Shield + controller)

Each step must pass before the next:

1. **Automount** — after `sudo systemctl stop mnt-nimbus-roms.mount`
   (idle timeout or manual), `ls /mnt/nimbus/roms` re-mounts on access;
   reboot once with Nimbus powered off → boot completes normally.
2. **Routing** — `es-session start`; `hyprctl -j clients` shows es-de
   on workspace `emulation`; desktop focus never moved.
3. **Script** — `start` twice → one PID; `status` accurate; `stop`
   clears everything.
4. **Stream** — Shield Moonlight → "Emulation": set the host's
   streaming resolution to 3840x2160@60 in Moonlight settings (Shield
   on Ethernet for the HEVC bitrate); stats overlay shows 4K + HEVC;
   Sunshine log confirms the KMS backend; controller + audio work.
5. **Input** — Select+Start exits each emulator back to ES-DE; L3+R3
   opens the RetroArch menu.
6. **Persistence** — drop the stream (Shield home), reconnect
   "Emulation": ES-DE state identical, no host-side cleanup ran.
7. **Teardown** — run "Emulation (Stop)" from Moonlight: emulator +
   ES-DE processes gone (`es-session status` shows not running), host
   desktop untouched throughout.

## Daily operation

Everything referenced here is configured in "One-time setup" above.

From the couch (Shield):

- **Moonlight → this host → "Emulation"** — starts or resumes the
  ES-DE session. Reconnecting after dropping the stream resumes exactly
  where you left off.
- **Moonlight → "Emulation (Stop)"** — terminates any running emulators,
  then ES-DE. Leaving the session running is also fine (persistent by
  design).

From the host:

```bash
es-session status   # dongle / ROM mount / process report (rc=1 if dongle or mount down)
es-session start    # idempotent ensure-running
es-session stop     # SIGTERM emulators, then ES-DE (SIGKILL after timeout)
```

Exit codes: `2` usage, `4` ES-DE binary missing. Dongle or mount
absence is a warning (desktop notification from `start`), never fatal —
ES-DE still launches locally. The process comm is exactly `es-de` (the
inner AppImage binary; the `es-de.AppImage` launcher self-exits), so
`pgrep -x es-de` is the reliable check. ES-DE logs live at
`~/ES-DE/logs/es_log.txt`.

## Troubleshooting

| Symptom | Diagnose | Fix |
|---|---|---|
| Stream fails / black screen | `es-session status` (dongle row); `~/.config/sunshine/sunshine.log` | Dongle must be present; `output_name` in `~/.config/sunshine/sunshine.conf` must match a `connected` connector — re-run the `/sys/class/drm` discovery loop in 4.2; check `getcap` on the sunshine binary; restart `app-dev.lizardbyte.app.Sunshine.service` |
| ES-DE lists no systems | `findmnt /mnt/nimbus/roms`; `systemctl status mnt-nimbus-roms.automount` | Automount must be `active (waiting)`; trigger with `ls /mnt/nimbus/roms`; check `/etc/cifs-creds-nimbus` exists (mode 600); check Nimbus is powered on |
| Emulator window shows on the desktop, not in the stream | `hyprctl -j clients` — compare the reported class against the `emulationWindows` regexes | Correct the class regex in `dot_config/hypr/hyprland.lua.tmpl` and `chezmoi apply` |
| No controller input in the stream | Moonlight's per-host settings on the Shield | Input must be enabled for this host in Moonlight settings; verify the combos work locally over USB first to isolate host vs client |
| `es-session start` exits 4 | `ls ~/AppImages/es-de.AppImage` | Restore the AppImage (see ES-DE updates in Maintenance) |
| First ROM browse after idle is slow | Expected behavior | Automount penalty: `TimeoutIdleSec=600` unmounts when idle; the next access pays a seconds-long remount |

## Maintenance

- **Sunshine updates reset capabilities.** Package updates can drop
  `cap_sys_admin`, breaking KMS capture. Re-check and re-apply:

  ```bash
  getcap "$(readlink -f "$(command -v sunshine)")"
  sudo setcap cap_sys_admin+p "$(readlink -f "$(command -v sunshine)")"
  ```

- **Dongle description changes** (new dongle, GPU swap, firmware
  quirk): re-run `hyprctl monitors all`, then update the `desc:` value
  in BOTH the `hl.monitor` entry and the `hl.workspace_rule` in
  `dot_config/hypr/hyprland.lua.tmpl`, and — if the new description no
  longer contains the match word — `DONGLE_DESC` in
  `dot_local/bin/executable_es-session`. `chezmoi apply`.
- **4K ↔ 1080p fallback** is exactly two values, nothing else changes:
  the `mode` in the hyprland monitor entry (`3840x2160@60` ↔
  `1920x1080@60`) and the Shield's per-host streaming resolution in
  Moonlight settings.
- **Mount option changes while mounted:** if the installer re-runs and
  rewrites the units while the share is mounted, the old mount options
  persist until the idle unmount (`TimeoutIdleSec=600`). Apply changes
  immediately with:

  ```bash
  sudo systemctl restart mnt-nimbus-roms.automount
  ```

- **RetroArch config recovery:** RetroArch's Main Menu → Save Config
  writes a full-dump cfg even though `config_save_on_exit="false"`. If
  the managed config got clobbered, restore it:

  ```bash
  chezmoi diff ~/.config/retroarch/retroarch.cfg   # see the damage
  chezmoi apply ~/.config/retroarch/retroarch.cfg   # restore
  ```

- **Emulation grid icons:** the Emulation entries have no `image-path`
  (placeholder icons in Moonlight). Optional: drop PNGs in Sunshine's
  config dir and add `image-path` fields to
  `dot_config/sunshine/apps.json`.
- **ES-DE updates:** GearLever manages `~/AppImages/es-de.AppImage`
  (existing AppImages pattern), or replace the file manually —
  `es-session` invokes that path directly either way.

## Managed vs runtime files

| Path | Managed by | Notes |
|---|---|---|
| `dot_config/hypr/hyprland.lua.tmpl` → `~/.config/hypr/hyprland.lua` | chezmoi | Dongle monitor + emulation routing, `personal`-gated |
| `dot_local/bin/executable_es-session` → `~/.local/bin/es-session` | chezmoi | `EMULATORS` must match installed binary names |
| `dot_config/sunshine/apps.json` → `~/.config/sunshine/apps.json` | chezmoi | App grid incl. Emulation / Emulation (Stop) |
| `dot_config/retroarch/retroarch.cfg` → `~/.config/retroarch/retroarch.cfg` | chezmoi | Runtime saves disabled; see recovery in Maintenance |
| `run_once_install-nimbus-roms-mount.sh.tmpl` | chezmoi (`run_once`) | Installs the systemd units below; see the re-run trap in setup step 2 |
| `~/.config/chezmoi/chezmoi.toml` | Hand (never committed) | `[data.machine] profile`, `[data.nimbus] romsShare` |
| `~/.config/sunshine/sunshine.conf` | Hand | Two keys: `capture = kms`, `output_name` |
| `/etc/cifs-creds-nimbus` | Hand (secret, never committed) | Mode 600 |
| `/etc/systemd/system/mnt-nimbus-roms.{mount,automount}` | Generated by the `run_once` installer | Idempotent — rewritten only on content change |
| `~/AppImages/es-de.AppImage` | Hand / GearLever | ES-DE 3.5.0 |
| `~/ES-DE/**` (`es_settings.xml`, logs, scraped media) | ES-DE runtime | Logs at `~/ES-DE/logs/es_log.txt` |
| `~/.config/dolphin-emu/*.ini`, PCSX2 inis | Emulator runtime | Hotkeys set via each UI (setup 4.5) |
| `~/.config/sunshine/{sunshine_state.json,sunshine.log,credentials}` | Sunshine runtime | Ignored via `.chezmoiignore.tmpl` |
| `~/.config/retroarch/{saves,states,playlists,thumbnails,autoconfig}` | RetroArch runtime | Saves/states are local on host by design |
