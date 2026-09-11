# Master Width Utility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A launcher utility that sets the current workspace's master-layout width from presets, a custom percent, or `--apply`, replacing the broken gaming auto-apply in hyprland.lua.

**Architecture:** One new shell script (`fuzzel` menu + `zenity` custom entry + `hyprctl dispatch` apply, with a `python3` state query for current width and workspace name), one `.desktop` launcher entry, and a pure-deletion edit to `hyprland.lua`. No test framework exists, so each task verifies through the script's own modes (`--print`, `--normalize`, `--apply`) and live `hyprctl -j` queries.

**Tech Stack:** POSIX sh, python3 (JSON), fuzzel 1.14 (`--dmenu`), zenity (GTK4), noctalia CLI, hyprctl on Hyprland 0.56.2 (Lua config).

**Spec:** `docs/superpowers/specs/2026-09-10-master-width-utility-design.md`

**Conventions:**
- Repo is chezmoi-managed: source paths are `dot_local/bin/executable_<name>` (chezmoi strips the `executable_` prefix and sets +x on apply). Installed path: `/home/gunny/.local/bin/<name>`.
- During development, run the repo copy directly with `sh dot_local/bin/executable_hyprland-master-width …` (the source file is not executable).
- Live session is the user's desktop: **never switch workspaces, focus windows, or apply widths without asking the user first.** State-changing test steps below include the ask.
- Commit style: short imperative subject, no attribution trailers.

---

### Task 1: Spike — verify the dispatch mechanism

The whole design rides on `hyprctl dispatch "hl.dsp.layout('mfact exact 0.65')"` working on a Lua config (proven shape for `hl.dsp.workspace.rename` in `ws-rename`, unproven for `layout`). Confirm before building.

**Files:** none (verification only)

- [ ] **Step 1: Ask the user to focus the gaming workspace**

Ask the user to press SUPER+G and click the Steam window (dispatch targets the workspace of the focused window; Steam must be the focused window so the target is `gaming`). Wait for confirmation.

- [ ] **Step 2: Run the dispatch and capture output**

```bash
hyprctl dispatch "hl.dsp.layout('mfact exact 0.65')"
```

Expected: output contains `ok` (not `invalid`, not `unknown`, not `no window`). If this fails, STOP — re-read the dispatch error, compare with `ws-rename`'s form, and resolve before continuing (nothing else in this plan works without it).

- [ ] **Step 3: Verify the width actually changed**

```bash
hyprctl -j clients | python3 -c '
import json,sys
for c in json.load(sys.stdin):
    if c["class"] == "steam":
        print("steam width:", c["size"][0])
'
```

Expected: width ≈ 3940–4020 px (was 3784; 0.65 × ~(6144 − gaps) ≈ 3970). If unchanged, the dispatch silently failed — investigate before proceeding.

---

### Task 2: Delete the broken auto-apply from hyprland.lua

**Files:**
- Modify: `dot_config/hypr/hyprland.lua`

- [ ] **Step 1: Delete `gamingMfact` constant**

Remove this line (line 189; `gamingWs` above it stays):

```lua
local gamingMfact = 0.65
```

- [ ] **Step 2: Delete `gamingMfactApply`**

Remove (lines 208–213):

```lua
local function gamingMfactApply()
    -- "exact" must precede the value: as the first token it flags absolute
    -- mode, otherwise the value is treated as a delta (0.7 delta => clamped 0.95)
    hl.dispatch(hl.dsp.layout("mfact exact " .. gamingMfact))
end
```

- [ ] **Step 3: Delete the one-shot handler and its comment**

Remove (lines 225–234):

```lua
-- Apply the wider gaming mfact once per session: re-applying on every
-- activation would silently revert manual SUPER+[ / SUPER+] tweaks each
-- time the workspace is re-entered.
local gamingMfactSet = false
hl.on("workspace.active", function(ws)
    if ws.name == gamingWs and not gamingMfactSet then
        gamingMfactApply()
        gamingMfactSet = true
    end
end)
```

- [ ] **Step 4: Verify no references remain and config reloads clean**

```bash
grep -n "gamingMfact\|gaming_mfact" dot_config/hypr/hyprland.lua; echo "grep exit: $?"
```

Expected: no matches (grep exit 1). Then ask the user to press SUPER+SHIFT+R (reload) and confirm no error notification/overlay appears.

- [ ] **Step 5: Commit**

```bash
git add dot_config/hypr/hyprland.lua
git commit -m "Drop broken gaming mfact auto-apply from hyprland.lua"
```

---

### Task 3: Script skeleton — presets, `--print`, `--normalize`

**Files:**
- Create: `dot_local/bin/executable_hyprland-master-width`

- [ ] **Step 1: Write the skeleton**

Create `dot_local/bin/executable_hyprland-master-width` with exactly the content below. **Caution: the `PRESETS` block contains literal TAB characters between the percent and the label — they must be real tabs, not spaces, or the awk field split breaks.**

```sh
#!/bin/sh
# Set the master layout width (mfact) of the current workspace: fuzzel menu
# with presets, a custom percent (zenity), or a direct --apply N. The prompt
# shows the current RENDERED share of the widest tiled window (gaps included,
# so 42 mfact shows ~40 rendered). mfact itself is per-workspace state in
# Hyprland; SUPER+[ / SUPER+] still work for nudges. There is no auto-apply
# by design — the old one-shot workspace.active handler could not survive
# empty-workspace transitions (see
# docs/superpowers/specs/2026-09-10-master-width-utility-design.md).
#
# Usage:
#   hyprland-master-width            # menu (presets + Custom…)
#   hyprland-master-width --apply N  # apply N percent directly
#   hyprland-master-width --print    # dump menu rows, no UI
set -eu

# Presets: percent TAB label. One line per preset.
PRESETS='
42	Default (27"-comfort window)
50	Half
65	Gaming (wide sides for references)
75	Wide (12.5% sides)
'

CUSTOM_ROW="Custom…"

# normalize_percent P: validate (digits, optional single decimal point) and
# clamp to 5..95 (Hyprland's own mfact clamp). Echo the normalized percent,
# or return 1 on invalid input.
normalize_percent() {
    pct=$1
    case "$pct" in
        '' | *[!0-9.]*) return 1 ;;
        *.*.*) return 1 ;;
    esac
    awk -v p="$pct" 'BEGIN { if (p < 5) p = 5; if (p > 95) p = 95; printf "%.4g\n", p }'
}

# Menu rows: "42%  Default (27"-comfort window)" … + Custom… row.
print_rows() {
    printf '%s\n' "$PRESETS" | awk -F'\t' 'NF == 2 { printf "%s%%  %s\n", $1, $2 }'
    printf '%s\n' "$CUSTOM_ROW"
}

main() {
    case "${1:-}" in
        --print)
            print_rows
            ;;
        --normalize)
            [ $# -eq 2 ] || { echo "usage: $0 --normalize N" >&2; exit 1; }
            normalize_percent "$2"
            ;;
        --apply)
            echo "not yet implemented" >&2; exit 1
            ;;
        '')
            echo "not yet implemented" >&2; exit 1
            ;;
        *)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2
            exit 1
            ;;
    esac
}

main "$@"
```

The two `case` patterns in `normalize_percent` work as: `'' | *[!0-9.]*` rejects empty strings and anything containing a character other than digit or dot; `*.*.*` rejects values with two or more dots (e.g. `1.2.3`, which the first pattern can't catch).

- [ ] **Step 2: Verify `--print`**

```bash
sh dot_local/bin/executable_hyprland-master-width --print
```

Expected output (5 lines):

```
42%  Default (27"-comfort window)
50%  Half
65%  Gaming (wide sides for references)
75%  Wide (12.5% sides)
Custom…
```

- [ ] **Step 3: Verify `--normalize` validation and clamping**

```bash
sh dot_local/bin/executable_hyprland-master-width --normalize 42;    echo "exit: $?"
sh dot_local/bin/executable_hyprland-master-width --normalize 62.5;  echo "exit: $?"
sh dot_local/bin/executable_hyprland-master-width --normalize 3;     echo "exit: $?"
sh dot_local/bin/executable_hyprland-master-width --normalize 140;   echo "exit: $?"
sh dot_local/bin/executable_hyprland-master-width --normalize abc;   echo "exit: $?"
```

Expected: `42` exit 0; `62.5` exit 0; `5` exit 0 (clamped); `95` exit 0 (clamped); no output, `exit: 1` for `abc`.

- [ ] **Step 4: Commit**

```bash
git add dot_local/bin/executable_hyprland-master-width
git commit -m "Add hyprland-master-width skeleton: presets, --print, --normalize"
```

---

### Task 4: State query and `--apply`

**Files:**
- Modify: `dot_local/bin/executable_hyprland-master-width`

- [ ] **Step 1: Add `notify`, `state`, and `apply_percent` above `main`**

Insert after the `print_rows` function:

```sh
# notify TITLE BODY: best-effort Noctalia notification (never fails the script)
notify() {
    noctalia msg notification-show "$1" "$2" 2>/dev/null || true
}

# state: one line "share TAB ws_name TAB tiled" for the ACTIVE workspace.
# share  = rendered percent of the widest tiled non-fullscreen window
#          (empty when unknown, e.g. fullscreen-only workspace)
# tiled  = count of tiled non-fullscreen windows; -1 means the query failed
state() {
    python3 - <<'PY'
import json, subprocess

def get(cmd):
    return json.loads(subprocess.run(cmd, capture_output=True, text=True).stdout)

try:
    ws      = get(["hyprctl", "-j", "activeworkspace"])
    clients = get(["hyprctl", "-j", "clients"])
    mons    = {m["id"]: m for m in get(["hyprctl", "-j", "monitors"])}
    ws_id   = ws["id"]
    tiled   = [c for c in clients
               if c["workspace"]["id"] == ws_id
               and not c["floating"]
               and not c["fullscreen"]]
    share = ""
    if tiled:
        mon       = mons[tiled[0]["monitor"]]
        logical_w = mon["width"] / mon["scale"]
        widest    = max(c["size"][0] for c in tiled)
        share     = str(round(widest / logical_w * 100))
    print(f"{share}\t{ws['name']}\t{len(tiled)}")
except Exception:
    print(f"\t?\t-1")
PY
}

# apply_percent P: normalize, pre-check for a tiled window (the layout
# dispatcher fails with no window/master node), dispatch, notify.
apply_percent() {
    pct=$(normalize_percent "$1") || { notify 'Master width' 'Invalid percent'; return 0; }
    st=$(state)
    ws_name=$(printf '%s\n' "$st" | cut -f2)
    tiled=$(printf '%s\n' "$st" | cut -f3)

    if [ "$tiled" = "0" ]; then
        notify 'Master width' 'No tiled window on this workspace'
        return 0
    fi
    if [ "$tiled" = "-1" ]; then
        notify 'Master width' 'Could not query workspace state'
        return 0
    fi

    mfact=$(awk -v p="$pct" 'BEGIN { printf "%.4g", p / 100 }')
    if ! hyprctl dispatch "hl.dsp.layout('mfact exact $mfact')" >/dev/null 2>&1; then
        notify 'Master width' 'Dispatch failed'
        return 0
    fi
    notify 'Master width' "$pct% on $ws_name"
}
```

- [ ] **Step 2: Wire `--apply` in `main`**

Replace the `--apply` case:

```sh
        --apply)
            [ $# -eq 2 ] || { echo "usage: $0 --apply N" >&2; exit 1; }
            apply_percent "$2"
            ;;
```

- [ ] **Step 3: Verify success path on the gaming workspace**

Ask the user to focus the gaming workspace and the Steam window again. Then:

```bash
sh dot_local/bin/executable_hyprland-master-width --apply 65
hyprctl -j clients | python3 -c '
import json,sys
for c in json.load(sys.stdin):
    if c["class"] == "steam":
        print("steam width:", c["size"][0])
'
```

Expected: `65% on gaming` notification; steam width ≈ 3940–4020 px.

- [ ] **Step 4: Verify failure path on an empty workspace**

Tell the user their view will flip to an empty scratch workspace for ~3 seconds and back. Then:

```bash
hyprctl dispatch togglespecialworkspace mw-spike
sh dot_local/bin/executable_hyprland-master-width --apply 50
hyprctl dispatch togglespecialworkspace mw-spike
```

Expected: `No tiled window on this workspace` notification; no crash; view restored.

- [ ] **Step 5: Verify invalid input path**

```bash
sh dot_local/bin/executable_hyprland-master-width --apply abc; echo "exit: $?"
```

Expected: `Invalid percent` notification, `exit: 0`.

- [ ] **Step 6: Commit**

```bash
git add dot_local/bin/executable_hyprland-master-width
git commit -m "Add state query and --apply to hyprland-master-width"
```

---

### Task 5: Menu and custom entry

**Files:**
- Modify: `dot_local/bin/executable_hyprland-master-width`

- [ ] **Step 1: Add `menu` above `main`**

```sh
# menu: fuzzel preset picker with the current rendered share in the prompt;
# Custom… routes to zenity --entry (ws-rename pattern).
menu() {
    st=$(state)
    share=$(printf '%s\n' "$st" | cut -f1)

    prompt='master '
    [ -n "$share" ] && prompt="master $share% "
    row=$(print_rows | fuzzel --dmenu --prompt "$prompt") || exit 0
    [ -n "$row" ] || exit 0

    if [ "$row" = "$CUSTOM_ROW" ]; then
        pct=$(zenity --entry --title 'Master width' \
            --text 'Master width in percent (5-95):' \
            --entry-text "${share:-50}" 2>/dev/null) || exit 0
        [ -n "$pct" ] || exit 0
    else
        pct=$(printf '%s\n' "$row" | cut -d% -f1)
    fi
    apply_percent "$pct"
}
```

- [ ] **Step 2: Wire the default case in `main`**

Replace the empty-arg case:

```sh
        '')
            menu
            ;;
```

- [ ] **Step 3: Manual verification (user-driven)**

Ask the user to run each of these and report:

1. `sh dot_local/bin/executable_hyprland-master-width` → menu opens with `master 62% `-style prompt; pick `65%  Gaming…` → notification `65% on gaming`, width visibly wider.
2. Run again → pick `Custom…` → enter `55` → notification `55% on gaming`.
3. Run again → pick `Custom…` → enter `abc` → `Invalid percent` notification.
4. Run again → press Esc → nothing happens (clean exit).
5. Run again → pick `Custom…` → press Esc/cancel → nothing happens.

- [ ] **Step 4: Verify SUPER+[ / SUPER+] still nudge the width**

Ask the user to press SUPER+] once on gaming and confirm the width steps wider (per-workspace mfact untouched by this script's mere existence; this guards against accidental future regressions in how the script dispatches).

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_hyprland-master-width
git commit -m "Add fuzzel menu and zenity custom entry to hyprland-master-width"
```

---

### Task 6: Launcher entry and final checks

**Files:**
- Create: `dot_local/share/applications/hyprland-master-width.desktop`

- [ ] **Step 1: Write the desktop entry**

```ini
[Desktop Entry]
Type=Application
Name=Hyprland Master Width
Comment=Set the master layout width of the current workspace
Exec=/home/gunny/.local/bin/hyprland-master-width
Icon=preferences-system
Categories=Utility;
NoDisplay=false
```

- [ ] **Step 2: Apply with chezmoi and smoke-test the installed path**

```bash
chezmoi apply
ls -l /home/gunny/.local/bin/hyprland-master-width
head -1 /home/gunny/.local/bin/hyprland-master-width
```

Expected: file exists, mode `-rwxr-xr-x`, first line `#!/bin/sh`. Then ask the user to open the Noctalia launcher, type "Master", run "Hyprland Master Width", and pick a preset — notification appears.

- [ ] **Step 3: Final checklist from the spec (Testing section)**

1. `sh dot_local/bin/executable_hyprland-master-width --print` — 5 rows. (Done in Task 3; re-confirm.)
2. `--apply 65` on gaming — ratio verified in Task 4 Step 3; re-confirm with the clients one-liner.
3. `--apply 65` on empty ws — failure notification. (Task 4 Step 4; re-confirm.)
4. Custom input: `abc` rejected, `62.5` accepted, `3`/`140` clamp to 5/95. (Task 3 Step 3 + Task 5 Step 3.)
5. Launcher finds "Master Width"; SUPER+[/] still work. (Task 5 Step 4 + Task 6 Step 2.)

- [ ] **Step 4: Commit**

```bash
git add dot_local/share/applications/hyprland-master-width.desktop
git commit -m "Add launcher entry for hyprland-master-width"
```

---

## Self-review notes

- Spec coverage: hyprland.lua deletion (Task 2), script with presets/custom/current-share/flags/errors (Tasks 3–5), .desktop (Task 6), all five spec test items mapped in Task 6 Step 3. Spike (spec Risks) is Task 1.
- The `case` cleanup note in Task 3 Step 1 is deliberate: the intermediate shape is shown for context, the "final shape" block is authoritative.
- No placeholders; every code step shows complete content; every verify step has an exact command and expected result.
