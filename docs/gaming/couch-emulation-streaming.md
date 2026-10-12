# Couch Emulation Streaming

Stream ES-DE and the RetroArch / Dolphin / PCSX2 emulators from the
Hyprland host to the Shield TV over Moonlight without touching the
desktop session: a 4K dummy plug presents a dedicated DRM connector that
Hyprland pins at 3840x2160@60, a persistent `couch` workspace bound
to that output receives every streamed window via the `couch-route`
watcher while a stream is active, and Sunshine KMS-captures only that
connector. ROMs automount over CIFS
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
Hyprland "couch" workspace (persistent, dongle-bound)
    │  couch-route watcher (Sunshine prep start/stop), ROUTES classes:
    │  steam_app_*, Steam Big Picture Mode, ^es-de$, ^retroarch$,
    │  ^dolphin-emu, ^pcsx2
    ▼
ES-DE ── launches ──► RetroArch / Dolphin / PCSX2
   ▼
/mnt/nimbus/roms (CIFS automount from Nimbus, TimeoutIdleSec=600)
```

Daily flow: pick **Emulation** in Moonlight → Sunshine starts the
`couch-route` watcher and runs `es-session start` → ES-DE launches
(or is reused) and the watcher routes it to the couch workspace →
play. Select(hold)+Start exits an emulator back to the ES-DE
grid; L3+R3 opens the RetroArch menu. Since 2026-10-11 any session
end — quitting from Moonlight or a disconnect — runs the undo chain
(`es-session stop`, then watcher stop) and tears the session down;
Sunshine's undo cannot distinguish a quit from a drop, so a network
hiccup mid-game also ends the session. **Emulation (Stop)** remains
as an explicit manual stop.

## One-time setup

### Already in place on this machine

- chezmoi templates + `personal` profile gating; `.chezmoiignore.tmpl`
  runtime-state ignores
- `[data.nimbus] romsShare = "//Nimbus/roms"` in
  `~/.config/chezmoi/chezmoi.toml` (verify with
  `chezmoi execute-template '{{ dig "nimbus" "romsShare" "" . }}'` —
  expect `//Nimbus/roms`)
- `run_once_install-nimbus-roms-mount.sh.tmpl` committed (not yet
  executed — see step 2)
- ES-DE 3.5.0 AppImage at `~/AppImages/es-de.AppImage`, verified
  runnable
- `es-session` deployed at `~/.local/bin/es-session` (start/stop/status
  verified)
- Sunshine `apps.json` managed with Desktop / Steam Big Picture /
  Emulation / Emulation (Stop)
- `~/.config/retroarch/retroarch.cfg` deployed (8 keys; runtime saves
  disabled)

### 1. ROM share access (no dongle needed)

The `roms` share on Nimbus is public — it is accessed as guest over
the LAN, so no credentials file is needed and there is nothing to set
up here.

If auth is ever enabled on the share: create
`/etc/cifs-creds-nimbus` (mode 600; contents never enter the repo),
re-add `credentials=/etc/cifs-creds-nimbus` to the mount unit's
`Options=` line in `run_once_install-nimbus-roms-mount.sh.tmpl`, and
re-run the activation command in step 2.

### 2. Activate the ROM automount (no dongle needed)

**Do not rely on `chezmoi apply` here.** The `run_once` installer
already executed once earlier (graceful skip), so chezmoi has recorded
its hash — a plain re-apply will NOT re-run it. Render and install the
units directly:

```bash
chezmoi execute-template < "$(chezmoi source-path)/run_once_install-nimbus-roms-mount.sh.tmpl" | bash
```

Pipe to plain `bash`, not `sudo bash` — under `sudo` the script's
`MY_UID`/`MY_GID` resolve to root (0) and the CIFS mount would land
root-owned; the script already uses `sudo` internally where needed, so
`id -u` must see the invoking user.

Then verify. Chezmoi swallows successful `run_once` output, so never
rely on seeing (or not seeing) a skip message — always check the unit
state directly:

```bash
systemctl status mnt-nimbus-roms.automount   # expect: active (waiting)
ls /mnt/nimbus/roms                          # triggers the mount after a ~1s pause
findmnt /mnt/nimbus/roms                     # expect: a cifs entry
```

### 3. Install emulators and cores (no dongle needed)

As installed on this machine:

- **RetroArch** — **use the Flathub flatpak (`org.libretro.RetroArch`,
  `--user` install) for best compatibility.** 2026-10-11 finding: the
  libretro `.7z`/AppImage distribution bundles an old SDL with
  incomplete DualSense mappings (Start dead, L3+R3 menu dead) and its
  input layer misbehaves when launched by ES-DE; the flatpak's modern
  SDL maps Sunshine's emulated DualSense completely. ES-DE resolves
  RetroArch to the wrapper `~/.local/bin/retroarch-es`
  (`~/ES-DE/custom_systems/es_find_rules.xml`), which launches the
  flatpak with `-c ~/.config/retroarch/retroarch.cfg`; the sandbox gets
  read-only `~/.config/retroarch` (config + cores) and
  `/mnt/nimbus/roms` via `flatpak override --user`. Window class
  `com.libretro.RetroArch` (unchanged); process comm is now plain
  `retroarch` (still covered by es-session's EMULATORS). Cores install
  from inside the app: **Main Menu → Online Updater → Core
  Downloader** (recommended set: Gambatte, mGBA, Nestopia UE, Snes9x,
  Genesis Plus GX, Mupen64Plus-Next); the shared
  `~/.config/retroarch/cores` keeps working through the override. The
  dnf `retroarch` package ships no core downloader; the old
  `~/AppImages/retroarch.appimage` is retired (kept only as a
  find-rules fallback entry).
- **Dolphin** — Flatpak `org.DolphinEmu.dolphin-emu` (class is plain
  `dolphin-emu`), granted read-only ROM access (already applied; takes
  effect on next app launch):

  ```bash
  flatpak override --user --filesystem=/mnt/nimbus/roms:ro org.DolphinEmu.dolphin-emu
  ```

- **PCSX2** — AppImage at `~/AppImages/pcsx2.appimage` (window class
  `pcsx2-qt`, process comm `pcsx2.appimage` — both verified live).

`es-session`'s `EMULATORS` list matches the installed launchers:
`retroarch retroarch.appim dolphin-emu pcsx2.appimage` (AppImage comms;
the kernel truncates comm at 15 chars — hence `retroarch.appim`).

### 4. When the dongle arrives

#### 4.1 Hyprland: dongle monitor + couch routing (DONE — as-built)

The dongle (description `LLV WOIEYEK 4K120 0x03F92F10`, connector
`card1-HDMI-A-1`, Hyprland name `HDMI-A-1`) is configured in
`dot_config/hypr/hyprland.lua.tmpl`, personal-profile-gated:

- Monitor entry `3840x2160@60` at logical `6144x0`, scale **1.25**. The
  position is in LOGICAL coordinates — the 57" at scale 1.25 occupies
  0–6143 (7680/1.25) — not the physical `7680x0` the plan draft had.
  The dongle scale MUST match the Samsung: a mixed-scale session
  (dongle at 1) triggers black overlay panels in wx/GTK apps —
  OrcaSlicer/OrcaSlicer#12330, verified 2026-10-04 (clean at uniform
  scale on both runtimes 50.4/50.5; broken mixed on both). Logical
  resolution is 3072x1728; Sunshine still captures the full
  3840x2160 framebuffer.
- `couch` workspace bound to the dongle (`persistent` + `default`) as a
  single-tile output: `layout = monocle` with zero gaps and no
  decorations (2026-10-11: a lone BPM window after game exit tiled as a
  centered master tile — tiling makes no sense on a TV). The noctalia
  bar is disabled for the dongle (`bar.default.monitor.dongle` in
  `dot_config/noctalia/config.toml`) — it reserved a 34px strip atop
  the stream; the 57" keeps its bars.
  Routing is NOT static: couch is used only while streaming, and
  runtime window rules lose to config rules (verified 2026-10-11), so
  the `couch-route` watcher (`dot_local/bin/executable_couch-route`,
  its ROUTES table is the registry) moves streamed windows to couch
  during a session. Local launches land on the current workspace —
  for local play, pull couch to the 57" with SUPER+SHIFT+E first.
- The `gaming` workspace is pinned to the Samsung
  (`desc:Samsung Electric Company Odyssey G95NC`): a newly appeared
  output claims the last unpinned workspace, so without the pin the
  dongle steals `gaming` (bit us once — fixed in commit `7fc39f5`).
- `DONGLE_DESC` in `es-session` defaults to `WOIEYEK`.

Verify (already deployed; re-check after template edits):

```bash
chezmoi apply
hyprctl monitors        # dongle at 3840x2160@60, 57" unchanged at 0x0
hyprctl workspaces      # gaming on DP-5, couch on HDMI-A-1
couch-route start && es-session start && sleep 3
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
```

(Routing needs the watcher — with no Sunshine stream active, start it
manually as shown; `couch-route stop` when done.) Expect an `es-de` row
on workspace `couch`. Since 2026-10-11 the watcher also focuses the
session's first streamed window (BPM drops controller input when
unfocused); with no stream active this moves keyboard focus to the
launched window — desktop focus otherwise stays put. Classes verified this way
for es-de, RetroArch (AppImage), Dolphin (Flatpak) and PCSX2 (AppImage).
NOTE: the ROUTES regexes in `couch-route` are fullmatch — enumerate
concrete per-packaging classes (a bare `pcsx2` alternative does NOT
catch `pcsx2-qt`).

#### 4.2 Sunshine: KMS capture + autostart (DONE — as-built)

Two manual keys in `~/.config/sunshine/sunshine.conf` (hand-managed by
design):

```ini
capture = kms
output_name = HDMI-A-1
```

**`output_name` is the BARE connector name — no `card1-` prefix.** The
name→connector mapping needs Sunshine ≥ 2026.906; this machine runs
`2026.914.233613` from the lizardbyte stable copr
(`copr:copr.fedorainfracloud.org:lizardbyte:stable`). Older builds (the
May 2026 `@commandline` 2026.516-style install was one) parse
`output_name` as a NUMERIC monitor index only — any name string becomes
garbage and every encoder probe dies with
`Couldn't find monitor [<huge number>]`.

**Hardware encoding needs RPM Fusion's `mesa-va-drivers-freeworld`.**
Fedora's stock Mesa VA driver exposes AV1-only encode on the 7900 XTX,
so without it Sunshine silently falls back to software x264:

```bash
sudo dnf install mesa-va-drivers-freeworld libva-utils
vainfo --display drm --device /dev/dri/renderD128 | grep -E "H264|HEVC"
```

Both codecs must show `VAEntrypointEncSlice`.

Capture privileges (package updates can reset them — see Maintenance):

```bash
getcap "$(readlink -f "$(command -v sunshine)")"   # expect cap_sys_admin,cap_sys_nice=p
```

The user service is **`app-dev.lizardbyte.app.Sunshine.service`** —
NOT `sunshine.service`. Despite the name it is NOT a Flatpak: a native
RPM from the copr owns `/usr/bin/sunshine` and ships the unit
(`ExecStart=/usr/bin/sunshine`); config lives at `~/.config/sunshine/`.
Discover the actual unit name before acting on it, and re-verify these
facts if Sunshine is ever reinstalled as a Flatpak (which would change
all of them):

```bash
systemctl --user list-units | grep -i sunshine
```

Autostart is ENABLED (`systemctl --user enable --now
app-dev.lizardbyte.app.Sunshine.service`). After conf changes, restart
with the same name, then verify the log:

```bash
systemctl --user restart app-dev.lizardbyte.app.Sunshine.service
grep -E "Mapped|Found .* encoder" ~/.config/sunshine/sunshine.log
```

Expected lines:

```text
Mapped 'HDMI-A-1' to kmsgrab monitor index N
Found H.264 encoder: h264_vaapi [vaapi]
```

Sanity-check the Web UI (`https://localhost:47990` → Applications):
Emulation entries listed, no parse errors. On the Shield, Moonlight →
this host should show the Emulation entries in the grid.

#### 4.3 ES-DE first run

Launch locally with `es-session start`. The first-run wizard asks for
the ROM directory — point it at `/mnt/nimbus/roms`. `es_settings.xml`
is runtime-mutated by ES-DE (scraper, UI settings) and deliberately
NOT chezmoi-managed.

#### 4.4 RetroArch runtime verification

RetroArch runs as the Flathub flatpak via the `retroarch-es` wrapper
(setup 3), fullscreen (`video_fullscreen = "true"` since 2026-10-11).
The config MUST keep `input_driver = "sdl2"` and
`input_joypad_driver = "sdl2"`: in the ES-DE/Sunshine launch
environment RA otherwise auto-picks input driver "x" + joypad "udev",
which binds Sunshine's emulated DualSense but leaves every button
unmapped — pad dead in-game while ES-DE chimes along behind it
(verified 2026-10-11 via `~/retroarch.log`: `Found input driver: "x"`,
`[Autoconf] Wireless Controller (1356/3302) not configured`).

First launch must use the Wayland context, not SDL — Vulkan ICD issues
on the dongle GPU would surface here:

```bash
flatpak run org.libretro.RetroArch --menu & sleep 4; pkill -x retroarch
```

Check the context driver in the verbose output (wayland expected). Then
confirm routing and that the run did not touch the managed config:

```bash
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
chezmoi diff ~/.config/retroarch/retroarch.cfg
```

Expect a `com.libretro.RetroArch` row on workspace `couch` and a
clean `chezmoi diff`.

With a paired controller (USB locally, or through a Moonlight test
stream), verify the combos: L3+R3 toggles the RetroArch menu;
Select(hold)+Start quits the process. If the combo values differ on
this build, correct the `input_*` keys in
`dot_config/retroarch/retroarch.cfg` and note the working values here.

#### 4.5 Dolphin and PCSX2 hotkeys

Their ini hotkey tokens encode device-specific button IDs, so hotkeys
are mapped through each UI once:

- **Dolphin** — launch `flatpak run org.DolphinEmu.dolphin-emu`. Bind
  the exit hotkey: **Options → Hotkey Settings → Exit → (click the
  binding field) → hold Select, press Start**. For start-in-fullscreen:
  if a fullscreen-on-start toggle exists in **Options → Configure…**,
  enable it; otherwise enable **View → Fullscreen** once, quit, then
  locate the persisted key — NOTE the Flatpak keeps its config under
  `~/.var/app/org.DolphinEmu.dolphin-emu/config/dolphin-emu/`:

  ```bash
  grep -ri fullscreen ~/.var/app/org.DolphinEmu.dolphin-emu/config/dolphin-emu/*.ini
  ```

  and set that key to `True` in the ini.

- **PCSX2** — launch `~/AppImages/pcsx2.appimage` (class `pcsx2-qt`).
  In **Settings → Hotkeys**: bind
  **Toggle Fullscreen**, and the shutdown/close entry (search the list
  for "Shutdown"/"Close"), each to Select(hold)+Start or the same
  convention. Set start-in-fullscreen under **Settings → Graphics or
  Interface** if present.

- **Exit check per emulator** — launch one GameCube game and one PS2
  game from the ES-DE grid (streamed or local): each opens fullscreen
  on the dongle; Select+Start returns to the ES-DE grid with the
  emulator process gone (`pgrep -x dolphin-emu`, `pgrep -x pcsx2.appimage`
  empty). Window placement is verified via the `hyprctl -j clients`
  one-liner above, plus a visual check through a Moonlight test stream.

### 5. End-to-end verification (needs Shield + controller)

Each step must pass before the next:

1. **Automount** — after `sudo systemctl stop mnt-nimbus-roms.mount`
   (idle timeout or manual), `ls /mnt/nimbus/roms` re-mounts on access;
   reboot once with Nimbus powered off → boot completes normally.
2. **Routing** — `es-session start`; `hyprctl -j clients` shows es-de
   on workspace `couch`; the watcher focuses the first streamed window
   (desktop keeps focus for any window that follows while a desktop
   window is focused).
3. **Script** — `start` twice → one PID; `status` accurate; `stop`
   clears everything.
4. **Stream** — Shield Moonlight → "Emulation": set the host's streaming
   resolution to 3840x2160@60 in Moonlight settings (Shield on Ethernet
   for the HEVC bitrate); stats overlay shows 4K + HEVC; Sunshine log
   confirms the KMS backend; controller + audio work. **Sharpness A/B
   (decision: dynamic scale flip)** — mid-stream, flip the dongle to
   scale 1 and compare detail (ES-DE menu text, in-game edges):
   `hyprctl eval 'hl.monitor({ output = "desc:LLV WOIEYEK 4K120 0x03F92F10", mode = "3840x2160@60", position = "6144x0", scale = 1 })'`,
   then restore the same call with `scale = 1.25`. Visibly sharper at 1
   → build the Sunshine prep-cmd scale flip (deferred feature, needs its
   own spec — trade-off: wx/GTK desktop apps break while a stream is
   live); identical → keep 1.25 and drop the idea.
5. **Input** — Select+Start exits each emulator back to ES-DE; L3+R3
   opens the RetroArch menu.
6. **Couch toggle + Steam (Couch)** — on the host, SUPER+Shift+E moves
   the couch ws to the 57" and back (gaming stays on DP-5 both ways);
   from the Shield grid, "Steam (Couch)" opens Big Picture in the
   stream and a game launched from it stays in the stream; after the
   session, a locally-launched Steam window lands on gaming again.
7. **Teardown on session end** — quit the stream from Moonlight (Back →
   quit): emulators + ES-DE exit (`es-session status` shows not running)
   and the watcher stops; reconnecting "Emulation" starts a fresh
   session. (Changed 2026-10-11: the original as-built kept ES-DE
   persistent across session ends; teardown-on-quit was requested
   later and applies to drops too — verify both paths.)
8. **Teardown** — run "Emulation (Stop)" from Moonlight: emulator +
   ES-DE processes gone (`es-session status` shows not running), host
   desktop untouched throughout.

### 6. Moonlight / Shield client settings (2026-10-11)

Per-host (Moonlight → gear next to the host):

- **Resolution 3840x2160 @ 60 FPS, codec HEVC, bitrate ~100 Mbps**
  (wired Ethernet; host processing rises to ~7.5 ms avg at 4K vs ~2 ms
  at 1080p — that is 4× the encode pixels, normal, budget is 16.7 ms).
  No host downscaling at this setting: capture (dongle) and stream are
  both 4K, so the scaler is a pass-through; the overlay's
  "Video stream: 3840x2160" line confirms what is actually sent.
- **Frame pacing: Prefer lowest latency** (global Moonlight setting).

Shield / TV:

- **Video Upscaling mode: Basic or Enhanced.** AI-Enhanced queues
  ~10 frames (~163 ms decode in the overlay) — but only when it
  actually engages, i.e. sub-4K streams; at a native 4K stream there
  is nothing to upscale and the mode is bypassed (safe to leave on for
  media apps if you never stream below 4K). The GeForce NOW "apply
  upscaling while streaming" toggle does NOT govern Moonlight — the
  global mode does.
- Shield Display & Sound: HDMI output 4K60.
- TV: **Game mode on the Shield's HDMI input** (removes TV processing;
  fixed stutter and part of the latency, 2026-10-11).

Monitoring: enable the stats overlay in Moonlight settings. Healthy
reference at 4K60 HEVC — network ~1 ms, host processing ~2–8 ms,
decode ~0, drops 0%. Low FPS (~10) on the ES-DE grid is Sunshine's
variable-frame-rate encoding on static content, not a fault.

## Daily operation

Everything referenced here is configured in "One-time setup" above.

From the couch (Shield):

- **Moonlight → this host → "Emulation"** — starts the ES-DE session
   (fresh unless one is still up from a manual host-side start).
- **Moonlight → "Emulation (Stop)"** — belt-and-braces manual stop;
   since 2026-10-11 the session already tears itself down on any
   stream end (quit or disconnect — undos cannot tell them apart).
- **Moonlight → "Steam (Couch)"** — opens Big Picture routed to the
   couch output; any game launched from it stays there for the duration
   of the stream (the `couch-route` watcher enforces this — expect up
   to ~1s before a new window hops to couch). Ends cleanly via
   Sunshine's undo (stops the watcher, closes Big Picture, moves Steam
   windows back to gaming).

From the host:

```bash
es-session status   # dongle / ROM mount / process report (rc=1 if dongle or mount down)
es-session start    # idempotent ensure-running
es-session stop     # SIGTERM emulators, then ES-DE (SIGKILL after timeout)
```

- **SUPER+Shift+E — couch toggle** — moves the couch workspace between
  the dongle and the 57" for local play. Sunshine keeps capturing the
  dongle connector, so while local the stream shows the dongle's empty
  default.

Exit codes: `2` usage, `4` ES-DE binary missing. Dongle or mount
absence is a warning (desktop notification from `start`), never fatal —
ES-DE still launches locally. The process comm is exactly `es-de` (the
inner AppImage binary; the `es-de.AppImage` launcher self-exits), so
`pgrep -x es-de` is the reliable check. ES-DE logs live at
`~/ES-DE/logs/es_log.txt`.

## Troubleshooting

| Symptom | Diagnose | Fix |
|---|---|---|
| Stream fails / black screen | `es-session status` (dongle row); `~/.config/sunshine/sunshine.log` | Dongle must be present; `output_name` in `~/.config/sunshine/sunshine.conf` must be the BARE connector name (`HDMI-A-1`, no `card1-` prefix) on Sunshine ≥ 2026.906 — a `Couldn't find monitor [<huge number>]` loop means the value isn't a valid name/index; check `getcap` on the sunshine binary; restart `app-dev.lizardbyte.app.Sunshine.service` |
| Stream works but CPU-bound / software encode in log (`Found H.264 encoder: libx264 [software]`) | `vainfo --display drm --device /dev/dri/renderD128 \| grep -E "H264\|HEVC"` | Both codecs must show `VAEntrypointEncSlice`; if missing, install `mesa-va-drivers-freeworld` (RPM Fusion) and restart Sunshine |
| Input lag in streamed games (~0.25–0.35 s); Moonlight overlay shows decode time ~165 ms while network/encode are clean (1–2 ms, 0% drops), same on H.264 and HEVC, audio slightly ahead of video | Moonlight stats overlay (enable in client settings) — the decode row is the tell; game feels fine locally via SUPER+Shift+E | Shield: Settings → Device Preferences → Display & Sound → **Video Upscaling mode → Basic or Enhanced** — **AI-Enhanced queues ~10 frames** post-decode when it engages (sub-4K streams only; at a native 4K stream the upscaler is bypassed and the mode is inert — see setup §6. The separate "GeForce NOW: apply upscaling while streaming" toggle does NOT govern Moonlight; the global mode does). Also enable Game mode on the TV input (kills stutter/TV processing). Verified 2026-10-11: AI-Enhanced decode 163 ms → 0 ms on Basic/Enhanced, lag gone |
| Stream connects but workspace is empty / ES-DE not running | Sunshine's user-service environment is snapshotted at service start and may lack `WAYLAND_DISPLAY` when enabled for autostart before the Hyprland session imports its env; check `systemctl --user show-environment \| grep WAYLAND_DISPLAY` | `systemctl --user restart app-dev.lizardbyte.app.Sunshine.service` |
| ES-DE lists no systems | `findmnt /mnt/nimbus/roms`; `systemctl status mnt-nimbus-roms.automount` | Automount must be `active (waiting)`; trigger with `ls /mnt/nimbus/roms`; check Nimbus is powered on and the share still permits guest access (if auth was enabled, see setup step 1) |
| Emulator window shows on the desktop, not in the stream | `couch-route status` (watcher must be `running`); `hyprctl -j clients` — compare the class against the ROUTES table | `couch-route start` if the watcher died; correct/add the class in `dot_local/bin/executable_couch-route` ROUTES and `chezmoi apply`. No stream active = no couch routing (by design — local launches stay local) |
| Steam BPM or a game stays on gaming during a stream | `couch-route status` — watcher must be `running`; `pgrep -x sunshine` | Watcher or Sunshine died without undo: `couch-route start`. New/shortcut app class not matched: add it to ROUTES. (History: the pre-2026-10-11 runtime-rule prep never worked — eval-added rules lose to config rules; the watcher replaced it) |
| wx/GTK app shows black overlay panels (e.g. OrcaSlicer print-time/filament info boxes) | `hyprctl monitors` — a mixed-scale session (any output whose scale differs from the others) triggers it; upstream OrcaSlicer #12330 | Keep all outputs at one scale — the dongle runs 1.25 to match the 57". No per-app GDK env fix exists (`GDK_SCALE` is integer-only/X11-only, `GDK_DPI_SCALE` is fonts-only/X11-only) |
| No controller input in Steam BPM but ES-DE responds | `hyprctl -j activewindow` — BPM/Steam Input ignore gamepads unless the streamed window holds keyboard focus; `couch-route status` | The watcher focuses streamed windows since 2026-10-11 (session's first window unconditionally, later ones only when focus is free/on couch). If it recurs: watcher dead → `couch-route start`; manual focus: `hyprctl eval 'hl.dispatch(hl.dsp.focus({ window = "address:<WINDOW-ADDR>" }))'` |
| No controller input in a Steam game (BPM fine, game dead) | Game's Player.log (compatdata `<appid>/pfx/.../LocalLow/...`) shows no joystick after launch; `/dev/input/event*` mtimes vs game start — Steam Input's virtual Xbox pad gets recreated mid-session (churn visible in Steam `controller.txt`); verify chain live: capture events on the Sunshine pad + Steam pad nodes while pressing buttons | Known failure mode (verified 2026-10-11, PEAK): Unity/Proton binds pads at launch and never re-enumerates — when the pad identity churns mid-game (Moonlight re-announce, Steam re-activation), the game holds a dead handle. Workaround: relaunch the game. Sunshine-side injection and Steam Input forwarding can both be healthy — check before blaming either |
| No controller input anywhere (BPM and ES-DE) | Moonlight per-host input setting on the Shield; then `/proc/bus/input/devices` — a `Wireless Controller` node (Sunshine's uhid DualSense via hid-playstation) must exist while a stream is live | Client input must be enabled for this host in Moonlight. `Warning: ControllerNumber already allocated` in sunshine.log is benign dedup. The gamepad device is destroyed at session end and recreated at the next controller announce with recycled node names — long-lived apps can hold stale bindings (dual-announce at connect still under investigation; workaround: turn the pad on after the stream connects) |
| `es-session start` exits 4 | `ls ~/AppImages/es-de.AppImage` | Restore the AppImage (see ES-DE updates in Maintenance) |
| RetroArch game ignores the controller (no input or "Wireless Controller (1356/3302) not configured" toast; ES-DE still beeps behind the game) | Temporarily re-add `log_to_file`/`log_dir`/`log_verbosity_level` keys to retroarch.cfg and read `~/retroarch.log` — look for `Found input driver: "x"` and joypad "udev" | Keep `input_driver = "sdl2"` + `input_joypad_driver = "sdl2"` in `dot_config/retroarch/retroarch.cfg` (the ES-DE/Sunshine env makes RA auto-pick x/udev, which binds the pad but maps no buttons) and launch via the `retroarch-es` wrapper with the Flathub build — the `.7z`/AppImage SDL also lacks full DualSense mappings (verified 2026-10-11) |
| First ROM browse after idle is slow | Expected behavior | Automount penalty: `TimeoutIdleSec=600` unmounts when idle; the next access pays a seconds-long remount |

## Maintenance

- **Sunshine updates reset capabilities.** Package updates can drop
  `cap_sys_admin`, breaking KMS capture. Upgrade only from the
  lizardbyte stable copr (name-based `output_name` needs ≥ 2026.906 —
  don't fall back to an old `@commandline` RPM). Re-check and re-apply:

  ```bash
  command -v sunshine >/dev/null || echo "sunshine not on PATH — check the Sunshine install before continuing"
  getcap "$(readlink -f "$(command -v sunshine)")"
  sudo setcap cap_sys_admin+p "$(readlink -f "$(command -v sunshine)")"
  ```

- **Hardware encode depends on `mesa-va-drivers-freeworld`** (RPM
  Fusion). Mesa upgrades keep it, but if streams ever fall back to
  software x264, re-check with `vainfo` (troubleshooting table).

- **Monitor description changes** (new dongle, GPU swap, firmware
  quirk): re-run `hyprctl monitors all`, then update the desc local in
  `dot_config/hypr/hyprland.lua.tmpl` — `samsungDesc` above the
  primary monitor entry, `dongleDesc` at the top of the dongle block;
  the monitor entries, workspace rules/pins, and the couch toggle all
  reference the locals — and, if the new dongle description no longer
  contains the match word, `DONGLE_DESC` in
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
  sudo systemctl stop mnt-nimbus-roms.automount mnt-nimbus-roms.mount && sudo systemctl start mnt-nimbus-roms.automount
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
| `dot_config/hypr/hyprland.lua.tmpl` → `~/.config/hypr/hyprland.lua` | chezmoi | Dongle monitor + couch workspace binding (no routing rules), `personal`-gated |
| `dot_local/bin/executable_couch-route` → `~/.local/bin/couch-route` | chezmoi | Stream-scoped couch routing; ROUTES = registry of streamed-app classes |
| `dot_local/bin/executable_es-session` → `~/.local/bin/es-session` | chezmoi | `EMULATORS` must match installed binary names |
| `dot_config/sunshine/apps.json` → `~/.config/sunshine/apps.json` | chezmoi | App grid; Steam (Couch) + Emulation preps start/stop couch-route; Emulation undo stops es-session (session teardown on stream end) |
| `dot_config/retroarch/retroarch.cfg` → `~/.config/retroarch/retroarch.cfg` | chezmoi | Runtime saves disabled; MUST force `input_driver`/`input_joypad_driver` = sdl2 (setup 4.4); shared read-only into the flatpak via the wrapper's `-c`; see recovery in Maintenance |
| `dot_local/bin/executable_retroarch-es` → `~/.local/bin/retroarch-es` | chezmoi | ES-DE → Flathub RetroArch launcher (`-c` shared config) |
| `ES-DE/custom_systems/es_find_rules.xml` → `~/ES-DE/custom_systems/es_find_rules.xml` | chezmo | RetroArch find-rule override resolving `%EMULATOR_RETROARCH%` to the wrapper (runtime copy is ES-DE-read-only, deployed by hand) |
| Flathub `org.libretro.RetroArch` (`--user`) + `flatpak override --user --filesystem=~/.config/retroarch:ro --filesystem=/mnt/nimbus/roms:ro` | Hand (flatpak) | Canonical RetroArch install (setup 3) |
| `run_once_install-nimbus-roms-mount.sh.tmpl` | chezmoi (`run_once`) | Installs the systemd units below; see the re-run trap in setup step 2 |
| `~/.config/chezmoi/chezmoi.toml` | Hand (never committed) | `[data.machine] profile`, `[data.nimbus] romsShare` |
| `~/.config/sunshine/sunshine.conf` | Hand | Two keys: `capture = kms`, `output_name` = bare connector name (`HDMI-A-1`) |
| `Sunshine` RPM (lizardbyte stable copr), `mesa-va-drivers-freeworld`, `libva-utils` | dnf (hand) | Version floor and freeworld rationale in setup 4.2 / Maintenance |
| `/etc/cifs-creds-nimbus` | Hand — only if auth is ever enabled | Mode 600; not needed while the share is public/guest |
| `/etc/systemd/system/mnt-nimbus-roms.{mount,automount}` | Generated by the `run_once` installer | Idempotent — rewritten only on content change |
| `~/AppImages/es-de.AppImage` | Hand / GearLever | ES-DE 3.5.0 |
| `~/AppImages/retroarch.appimage` | Hand | RETIRED 2026-10-11 (old SDL, incomplete DualSense mappings) — kept only as a find-rules fallback |
| `~/ES-DE/**` (`es_settings.xml`, logs, scraped media) | ES-DE runtime | Logs at `~/ES-DE/logs/es_log.txt`; settings live at `~/ES-DE/settings/es_settings.xml` |
| `~/.var/app/org.libretro.RetroArch/config/retroarch/{saves,states,playlists,thumbnails,autoconfig}` | RetroArch runtime (flatpak sandbox) | Saves/states are local on host by design; moved here from `~/.config/retroarch/` with the flatpak switch |
| `~/.var/app/org.DolphinEmu.dolphin-emu/config/dolphin-emu/*.ini`, `~/.config/PCSX2/**` | Emulator runtime | Flatpak / AppImage paths; hotkeys set via each UI (setup 4.5) |
| `~/.config/sunshine/{sunshine_state.json,sunshine.log,credentials}` | Sunshine runtime | Ignored via `.chezmoiignore.tmpl` |
