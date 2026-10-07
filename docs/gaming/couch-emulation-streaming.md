# Couch Emulation Streaming

Stream ES-DE and the RetroArch / Dolphin / PCSX2 emulators from the
Hyprland host to the Shield TV over Moonlight without touching the
desktop session: a 4K dummy plug presents a dedicated DRM connector that
Hyprland pins at 3840x2160@60, a persistent `couch` workspace bound
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
Hyprland "couch" workspace (persistent, dongle-bound)
   │  silent window rules: ^es-de$, ^retroarch$, ^dolphin-emu, ^pcsx2
   ▼
ES-DE ── launches ──► RetroArch / Dolphin / PCSX2
   ▼
/mnt/nimbus/roms (CIFS automount from Nimbus, TimeoutIdleSec=600)
```

Daily flow: pick **Emulation** in Moonlight → Sunshine runs
`es-session start` → ES-DE launches (or is reused) on the couch
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

- **RetroArch** — AppImage at `~/AppImages/retroarch.appimage` (window
  class `com.libretro.RetroArch`; process comm truncates to
  `retroarch.appim`). Cores install from inside the app: **Main Menu →
  Online Updater → Core Downloader** (recommended set: Gambatte, mGBA,
  Nestopia UE, Snes9x, Genesis Plus GX, Mupen64Plus-Next). The dnf
  `retroarch` package also exists at `/usr/bin/retroarch` but ships no
  core downloader — the AppImage is the canonical install.
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
- `couch` workspace bound to the dongle (`persistent` +
  `default`), window rules sending the es-de / RetroArch / Dolphin /
  PCSX2 classes there silently. The dolphin/pcsx2 regexes are
  deliberately unanchored on the right (packaging suffixes such as
  `pcsx2-qt`).
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
es-session start && sleep 3
hyprctl -j clients | python3 -c 'import json,sys; [print(c["class"], c["workspace"]["name"]) for c in json.load(sys.stdin)]'
```

Expect an `es-de` row on workspace `couch`, desktop focus unmoved.
Classes verified this way for es-de, RetroArch (AppImage), Dolphin
(Flatpak) and PCSX2 (AppImage). NOTE: Hyprland 0.56 `match.class` is
FULLMATCH — a bare `pcsx2` alternative does NOT catch `pcsx2-qt`, so
the table enumerates concrete per-packaging classes.

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

RetroArch runs as the AppImage (`~/AppImages/retroarch.appimage`). It
is currently WINDOWED at 3072x1728 for local testing — once streaming
is verified, flip `video_fullscreen = "true"` (and drop the window
geometry) in `dot_config/retroarch/retroarch.cfg` (a note in the file
marks the spot).

First launch must use the Wayland context, not SDL — Vulkan ICD issues
on the dongle GPU would surface here:

```bash
~/AppImages/retroarch.appimage --verbose --menu & sleep 4; pkill -x retroarch.appim
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
   on workspace `couch`; desktop focus never moved.
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
7. **Persistence** — drop the stream (Shield home), reconnect
   "Emulation": ES-DE state identical, no host-side cleanup ran.
8. **Teardown** — run "Emulation (Stop)" from Moonlight: emulator +
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
- **Moonlight → "Steam (Couch)"** — opens Big Picture routed to the
  couch output; any game launched from it stays there for the duration
  of the stream. Ends cleanly via Sunshine's undo (closes Big Picture,
  drops the runtime routing rule).

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
| Stream connects but workspace is empty / ES-DE not running | Sunshine's user-service environment is snapshotted at service start and may lack `WAYLAND_DISPLAY` when enabled for autostart before the Hyprland session imports its env; check `systemctl --user show-environment \| grep WAYLAND_DISPLAY` | `systemctl --user restart app-dev.lizardbyte.app.Sunshine.service` |
| ES-DE lists no systems | `findmnt /mnt/nimbus/roms`; `systemctl status mnt-nimbus-roms.automount` | Automount must be `active (waiting)`; trigger with `ls /mnt/nimbus/roms`; check Nimbus is powered on and the share still permits guest access (if auth was enabled, see setup step 1) |
| Emulator window shows on the desktop, not in the stream | `hyprctl -j clients` — compare the reported class against the `emulationWindows` regexes | Correct the class regex in `dot_config/hypr/hyprland.lua.tmpl` and `chezmoi apply` |
| Steam game/BPM opens on the gaming workspace instead of the couch (mid-session) | The runtime rule was dropped — a config reload or compositor restart mid-session clears eval-added rules | Re-launch via the "Steam (Couch)" Moonlight entry (its prep `do` re-installs the rule), or end the session and start it again |
| wx/GTK app shows black overlay panels (e.g. OrcaSlicer print-time/filament info boxes) | `hyprctl monitors` — a mixed-scale session (any output whose scale differs from the others) triggers it; upstream OrcaSlicer #12330 | Keep all outputs at one scale — the dongle runs 1.25 to match the 57". No per-app GDK env fix exists (`GDK_SCALE` is integer-only/X11-only, `GDK_DPI_SCALE` is fonts-only/X11-only) |
| No controller input in the stream | Moonlight's per-host settings on the Shield | Input must be enabled for this host in Moonlight settings; verify the combos work locally over USB first to isolate host vs client |
| `es-session start` exits 4 | `ls ~/AppImages/es-de.AppImage` | Restore the AppImage (see ES-DE updates in Maintenance) |
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
| `dot_config/hypr/hyprland.lua.tmpl` → `~/.config/hypr/hyprland.lua` | chezmoi | Dongle monitor + couch routing, `personal`-gated |
| `dot_local/bin/executable_es-session` → `~/.local/bin/es-session` | chezmoi | `EMULATORS` must match installed binary names |
| `dot_config/sunshine/apps.json` → `~/.config/sunshine/apps.json` | chezmoi | App grid incl. Emulation / Emulation (Stop) |
| `dot_config/retroarch/retroarch.cfg` → `~/.config/retroarch/retroarch.cfg` | chezmoi | Runtime saves disabled; see recovery in Maintenance |
| `run_once_install-nimbus-roms-mount.sh.tmpl` | chezmoi (`run_once`) | Installs the systemd units below; see the re-run trap in setup step 2 |
| `~/.config/chezmoi/chezmoi.toml` | Hand (never committed) | `[data.machine] profile`, `[data.nimbus] romsShare` |
| `~/.config/sunshine/sunshine.conf` | Hand | Two keys: `capture = kms`, `output_name` = bare connector name (`HDMI-A-1`) |
| `Sunshine` RPM (lizardbyte stable copr), `mesa-va-drivers-freeworld`, `libva-utils` | dnf (hand) | Version floor and freeworld rationale in setup 4.2 / Maintenance |
| `/etc/cifs-creds-nimbus` | Hand — only if auth is ever enabled | Mode 600; not needed while the share is public/guest |
| `/etc/systemd/system/mnt-nimbus-roms.{mount,automount}` | Generated by the `run_once` installer | Idempotent — rewritten only on content change |
| `~/AppImages/es-de.AppImage` | Hand / GearLever | ES-DE 3.5.0 |
| `~/AppImages/retroarch.appimage` | Hand | Cores via in-app Core Downloader (setup 3) |
| `~/ES-DE/**` (`es_settings.xml`, logs, scraped media) | ES-DE runtime | Logs at `~/ES-DE/logs/es_log.txt` |
| `~/.var/app/org.DolphinEmu.dolphin-emu/config/dolphin-emu/*.ini`, `~/.config/PCSX2/**` | Emulator runtime | Flatpak / AppImage paths; hotkeys set via each UI (setup 4.5) |
| `~/.config/sunshine/{sunshine_state.json,sunshine.log,credentials}` | Sunshine runtime | Ignored via `.chezmoiignore.tmpl` |
| `~/.config/retroarch/{saves,states,playlists,thumbnails,autoconfig}` | RetroArch runtime | Saves/states are local on host by design |
