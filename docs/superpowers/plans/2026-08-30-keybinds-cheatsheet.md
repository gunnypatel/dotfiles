# Keybinds Cheatsheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fuzzy-searchable cheatsheet of keybindings (Hyprland, tmux, Ghostty, Neovim) shown in a fuzzel popup, launchable from the Noctalia launcher and SUPER+SLASH; picking a Hyprland row dispatches that bind.

**Architecture:** One bash script (`keybinds-cheatsheet`) with per-tool collectors that emit TSV records, cached on disk and invalidated by config-file hashes plus live `hyprctl binds` output. Hyprland records come from a Lua source scan of `hyprland.lua` run via `nvim -l` (stubbed `hl.*` API — same trick as Omarchy's `omarchy-menu-keybindings`, which lives at `~/repos/omarchy/bin/omarchy-menu-keybindings` and is the reference for several code blocks below). UI is `fuzzel --dmenu`; dispatch is `hyprctl dispatch exec` / `hyprctl eval`.

**Tech Stack:** bash, awk, perl, nvim (`-l` and `--headless`), tmux (isolated server), `ghostty +list-keybinds`, `hyprctl`, fuzzel, chezmoi.

**Repo facts the implementer must know:**

- This is a **chezmoi** source repo at `/home/gunny/projects/dotfiles` (`chezmoi source-path` confirms). `chezmoi apply` deploys. Naming: `dot_config/X` → `~/.config/X`, `dot_local/bin/executable_foo` → `~/.local/bin/foo` (mode 755), `dot_local/share/X` → `~/.local/share/X`.
- Live configs are currently IN SYNC with the repo (verified).
- The executing machine IS the target machine: `chezmoi apply`, `hyprctl reload`, and popup tests all act on the user's running session. Popup-visibility checks (fuzzel appearing, terminal opening) require the user's eyes — note them in task output; exit codes still verify programmatically.
- Do NOT add "Co-Authored-By" lines to commits (user preference).
- Fedora, `dnf` package manager. `lua` binary is NOT installed; `nvim -l` does not load user config (verified) — that's why it's the scanner interpreter.

---

### Task 1: Spike — do bind descriptions surface in `hyprctl binds`?

This decides how much the hypr collector can trust `hyprctl binds` for labels (the Lua source scan provides labels either way, so the feature works regardless — this spike only documents which fallbacks are live).

**Files:**
- Modify: `dot_config/hypr/hyprland.lua:115`

- [ ] **Step 1: Add a description to the SUPER+RETURN bind**

In `dot_config/hypr/hyprland.lua`, change line 115 from:

```lua
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
```

to:

```lua
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
```

- [ ] **Step 2: Deploy and reload**

Run: `chezmoi apply && hyprctl reload`
Expected: no errors from either command.

- [ ] **Step 3: Check the live binds output**

Run: `hyprctl binds | grep -B4 'description: Terminal'`
Expected (spike outcome A): the SUPER+RETURN record shows `description: Terminal`.
If instead every `description:` field is still empty (spike outcome B), that's fine — record the outcome; the scan-based labels carry the feature.

- [ ] **Step 4: Confirm the dispatch mechanism (already proven, keep as regression check)**

Run: `hyprctl eval "hl.config({})" && echo EVAL-OK`
Expected: `ok` then `EVAL-OK` (same mechanism as the user's `hyprland-toggle-layout` script).

- [ ] **Step 5: Commit**

```bash
git add dot_config/hypr/hyprland.lua
git commit -m "Describe the terminal bind; verify hyprctl bind descriptions"
```

---

### Task 2: Install fuzzel and add its config

**Files:**
- Create: `dot_config/fuzzel/fuzzel.ini`

- [ ] **Step 1: Install fuzzel**

Run: `sudo dnf install -y fuzzel`
Expected: installs `fuzzel` plus small deps `fcft`, `nanosvg`, `utf8proc`.

- [ ] **Step 2: Create the config**

Create `dot_config/fuzzel/fuzzel.ini` with exactly:

```ini
# Fuzzy picker for the keybinds cheatsheet (any future --dmenu callers too).
# Theme matches the Noctalia community palette: Catppuccin Mocha Green.
# Font matches the Noctalia bar (see ~/.config/noctalia/config.toml).
[main]
font=JetBrainsMono Nerd Font:size=11
anchor=center
lines=15
width=900
horizontal-pad=25
vertical-pad=20
inner-pad=10

[dmenu]
exit-on-keyboard-focus-loss=yes

[colors]
background=1e1e2edd
text=cdd4f4ff
match=a6e3a1ff
selection=313244ff
selection-text=cdd4f4ff
selection-match=a6e3a1ff
border=a6e3a1ff
```

- [ ] **Step 3: Verify option names against the local man page (ini keys vary across fuzzel versions)**

Run: `man fuzzel.ini | col -b | grep -E '^( *)width|^( *)exit-on-keyboard|^( *)selection-match'`
Expected: all three documented. If any key is named differently in this version, rename it in the ini to the man page's spelling (this is the only sanctioned deviation from the block above).

- [ ] **Step 4: Deploy and sanity-check fuzzel runs**

Run: `chezmoi apply && printf 'alpha\nbeta\n' | fuzzel --dmenu --prompt test; echo "exit=$?"`
Expected: a centered popup appears listing alpha/beta on the user's screen; press Esc. Terminal prints `exit=1` (fuzzel exits nonzero on cancel — that's the contract the script relies on).

- [ ] **Step 5: Commit**

```bash
git add dot_config/fuzzel/fuzzel.ini
git commit -m "Add fuzzel config themed for Noctalia Mocha Green"
```

---

### Task 3: Describe every Hyprland bind and add the SUPER+SLASH bind

**Files:**
- Modify: `dot_config/hypr/hyprland.lua:108-233` (the whole KEYBINDINGS section)

- [ ] **Step 1: Replace the KEYBINDINGS section**

Replace everything from the `------------------` / `-- KEYBINDINGS` banner (line 108) through the last media-key bind (line 233, the `XF86AudioPause` line) — i.e. up to but NOT including the `------------------` / `-- RULES` banner — with:

```lua
------------------
-- KEYBINDINGS
------------------

local mainMod = "SUPER"

-- Launch
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager), { description = "File manager" })
hl.bind(mainMod .. " + SPACE",  hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"), { description = "Noctalia launcher" })

-- Cheatsheet: this very keybind list (SUPER+/ reads as "where are my keys?")
hl.bind(mainMod .. " + SLASH",  hl.dsp.exec_cmd("keybinds-cheatsheet"), { description = "Keyboard cheatsheet" })

-- Window ops (SUPER+W mirrors Ctrl+W: apps close a tab, or the window)
hl.bind(mainMod .. " + W", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mainMod .. " + C", hl.dsp.window.center(), { description = "Center floating window" })  -- center a floating window
hl.bind(mainMod .. " + M", hl.dsp.layout("swapwithmaster"), { description = "Promote window to center" })  -- promote focused window to center

-- Master splits: SUPER+SHIFT+M pulls the focused window into the center
-- column (extra masters stack above/below; SUPER+RMB resizes their shares),
-- SUPER+CTRL+M drops it back to the sides.
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.layout("addmaster"), { description = "Add master (pull to center)" })
hl.bind(mainMod .. " + CTRL + M",  hl.dsp.layout("removemaster"), { description = "Remove master (push to sides)" })

-- Master width: SUPER+[ / SUPER+] adjusts the master's share by 5%.
-- Per-workspace: each workspace keeps its own ratio for its lifetime.
hl.bind(mainMod .. " + bracketleft",  hl.dsp.layout("mfact -0.05"), { description = "Master narrower" })
hl.bind(mainMod .. " + bracketright", hl.dsp.layout("mfact 0.05"), { description = "Master wider" })

-- Focus / move, vim-style (matches Ctrl+hjkl window nav in nvim)
for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    hl.bind(mainMod .. " + " .. key:upper(),         hl.dsp.focus({ direction = dir }), { description = "Focus window " .. dir })
    hl.bind(mainMod .. " + SHIFT + " .. key:upper(), hl.dsp.window.move({ direction = dir }), { description = "Move window " .. dir })
end

-- Workspaces 1-9; SUPER+SHIFT+N moves the window there (focus follows),
-- SUPER+CTRL+N parks it there silently (stays on the current workspace)
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }), { description = "Workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
    hl.bind(mainMod .. " + CTRL + " .. i,  hl.dsp.window.move({ workspace = i, follow = false }), { description = "Park window on workspace " .. i })
end

-- Gaming workspace: a named workspace outside the 1-9 strip, summoned with
-- SUPER+G. Windows listed in gamingWindows always open here: related apps
-- arrive silently, games (master = true) take the view with them. Promote
-- the game to the center tile with SUPER+M. (An automatic master claim needs
-- window.open/title events, which Hyprland 0.56.2 never emits for XWayland
-- windows — revisit on a newer Hyprland.)
local gamingWs    = "gaming"
local gamingMfact = 0.65

-- One line per window; no logic changes needed to extend. class/title are
-- regexes matched against the window's initialClass/initialTitle (RE2)
local gamingWindows = {
    { class = "^steam$" },                            -- storefront
    { class = "^steam_app_[0-9]+$" },                 -- shortcut launchers (Battle.net)
    { class = "^steam_app_[0-9]+$", title = "^World of Warcraft", master = true },
}

-- "name:" is required: a bare name only matches an existing workspace and
-- errors otherwise; the prefix lets the first SUPER+G / SUPER+SHIFT+G create it.
hl.bind(mainMod .. " + G",         hl.dsp.focus({ workspace = "name:" .. gamingWs }), { description = "Gaming workspace" })
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.window.move({ workspace = "name:" .. gamingWs, follow = false }), { description = "Park window on gaming workspace" })

-- Keep the gaming workspace alive even when empty and unfocused: without
-- this, Hyprland destroys it when its last window closes (e.g. Steam
-- restart), and the routing rules above then silently miss their target.
hl.workspace_rule({ workspace = "name:" .. gamingWs, persistent = true })

local function gamingMfactApply()
    -- "exact" must precede the value: as the first token it flags absolute
    -- mode, otherwise the value is treated as a delta (0.7 delta => clamped 0.95)
    hl.dispatch(hl.dsp.layout("mfact exact " .. gamingMfact))
end

for i, entry in ipairs(gamingWindows) do
    hl.window_rule({
        name  = "gaming-ws-" .. i,
        match = { class = entry.class, title = entry.title },
        -- same-effect rules: last match wins, so a game's non-silent
        -- workspace (listed after the launcher catch-all) takes precedence
        workspace = entry.master and gamingWs or (gamingWs .. " silent"),
    })
end

hl.on("workspace.active", function(ws)
    if ws.name == gamingWs then
        gamingMfactApply()
    end
end)

-- Scratchpad: drop-down layer over the current workspace. Stashing is
-- silent: focus stays here, so you can send several windows in a row.
hl.bind(mainMod .. " + D",         hl.dsp.workspace.toggle_special("scratchpad"), { description = "Toggle scratchpad" })
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }), { description = "Stash window to scratchpad" })

-- Mouse: SUPER+LMB move, SUPER+RMB resize, SUPER+scroll cycle workspaces
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Noctalia shell surfaces and session
hl.bind("ALT + TAB",               hl.dsp.exec_cmd(ipc .. "window-switcher"), { description = "Window switcher" })
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"), { description = "Control center" })
-- COMMA renames the workspace (tmux prefix+, parity); settings moved to PERIOD
hl.bind(mainMod .. " + PERIOD",    hl.dsp.exec_cmd(ipc .. "settings-toggle"), { description = "Noctalia settings" })
hl.bind(mainMod .. " + COMMA",     hl.dsp.exec_cmd("ws-rename"), { description = "Rename workspace" })
hl.bind(mainMod .. " + ESCAPE",    hl.dsp.exec_cmd(ipc .. "session lock"), { description = "Lock session" })
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(ipc .. "panel-toggle session"), { description = "Session menu" })
hl.bind("PRINT",                   hl.dsp.exec_cmd(ipc .. "screenshot-region"), { description = "Screenshot region" })

-- Reload (no Lua reload dispatcher yet; hyprctl works from any bind)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { description = "Reload Hyprland config" })

-- Hardware/media keys -> Noctalia OSDs
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(ipc .. "volume-up"),     { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(ipc .. "volume-down"),   { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(ipc .. "volume-mute"),   { locked = true, description = "Mute volume" })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(ipc .. "brightness-up"),   { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"), { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd(ipc .. "media next"),    { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd(ipc .. "media previous"), { locked = true, description = "Previous track" })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd(ipc .. "media toggle"),  { locked = true, description = "Play/pause" })
hl.bind("XF86AudioPause",        hl.dsp.exec_cmd(ipc .. "media toggle"),  { locked = true, description = "Play/pause" })
```

Everything below (the RULES banner onward) stays untouched.

- [ ] **Step 2: Deploy and reload**

Run: `chezmoi apply && hyprctl reload`
Expected: no errors.

- [ ] **Step 3: Verify bind count and the new bind**

Run: `hyprctl binds | grep -c '^bind'`
Expected: `73` (was 72; +1 for SLASH).

Run: `hyprctl binds | grep -c 'SLASH'`
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add dot_config/hypr/hyprland.lua
git commit -m "Describe all Hyprland binds and add SUPER+SLASH cheatsheet bind"
```

---

### Task 4: Script skeleton, cache, scanner, and Hyprland collector

**Files:**
- Create: `dot_local/bin/executable_keybinds-cheatsheet`

- [ ] **Step 1: Verify the test fails (script does not exist yet)**

Run: `~/.local/bin/keybinds-cheatsheet --print hypr`
Expected: `no such file or directory`.

- [ ] **Step 2: Create the script**

Create `dot_local/bin/executable_keybinds-cheatsheet` with exactly:

```bash
#!/usr/bin/env bash
# keybinds-cheatsheet: fuzzy-searchable cheatsheet of keybindings across
# Hyprland, tmux, Ghostty and Neovim, shown in a fuzzel --dmenu popup.
# Picking a Hyprland row dispatches that bind. Records are collected live
# and cached; the cache invalidates when any tracked config (or the live
# hyprctl binds table, or this script itself) changes.
#
# Usage:
#   keybinds-cheatsheet               # open the fuzzel menu
#   keybinds-cheatsheet --print       # dump all formatted rows (debug/tests)
#   keybinds-cheatsheet --print tmux  # dump one tool: hypr|tmux|ghostty|nvim
#   keybinds-cheatsheet --refresh     # ignore the cache for this run
#   keybinds-cheatsheet --select ROW  # pretend ROW was picked (test hook)
set -euo pipefail

HYPR_CONFIG="$HOME/.config/hypr/hyprland.lua"
TMUX_CONFIG="$HOME/.config/tmux/tmux.conf"
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
NVIM_CONFIG="$HOME/.config/nvim/init.lua"
NVIM_LOCK="$HOME/.config/nvim/nvim-pack-lock.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/keybinds-cheatsheet"
TOOL_ORDER="hypr tmux ghostty nvim"

print_only=""
refresh=false
selection=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
  case "$1" in
    --print|-p)
      print_only=all
      if [[ ${2:-} != "" && ${2:-} != -* ]]; then print_only="$2"; shift; fi
      ;;
    --refresh|-r) refresh=true ;;
    --select|-s)  selection="${2:?--select requires a row argument}"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Hyprland: display helpers
# ---------------------------------------------------------------------------

modmask_to_text() {
  case "$1" in
    0)  printf '' ;;
    1)  printf 'SHIFT' ;;
    4)  printf 'CTRL' ;;
    5)  printf 'SHIFT CTRL' ;;
    8)  printf 'ALT' ;;
    9)  printf 'SHIFT ALT' ;;
    12) printf 'CTRL ALT' ;;
    13) printf 'SHIFT CTRL ALT' ;;
    64) printf 'SUPER' ;;
    65) printf 'SUPER SHIFT' ;;
    68) printf 'SUPER CTRL' ;;
    69) printf 'SUPER SHIFT CTRL' ;;
    72) printf 'SUPER ALT' ;;
    73) printf 'SUPER SHIFT ALT' ;;
    76) printf 'SUPER CTRL ALT' ;;
    77) printf 'SUPER SHIFT CTRL ALT' ;;
    *)  printf '%s' "$1" ;;
  esac
}

display_key() {
  local k="${1,,}"
  case "$k" in
    mouse:272)   echo "MOUSE LEFT" ;;
    mouse:273)   echo "MOUSE RIGHT" ;;
    mouse_down)  echo "SCROLL DOWN" ;;
    mouse_up)    echo "SCROLL UP" ;;
    comma)       echo "COMMA" ;;
    period)      echo "PERIOD" ;;
    slash)       echo "SLASH" ;;
    minus)       echo "MINUS" ;;
    equal)       echo "EQUAL" ;;
    grave)       echo "~" ;;
    bracketleft) echo "[" ;;
    bracketright) echo "]" ;;
    escape)      echo "ESC" ;;
    space)       echo "SPACE" ;;
    *)           echo "${1^^}" ;;
  esac
}

# ---------------------------------------------------------------------------
# Hyprland: source scan via nvim -l (nvim embeds Lua and -l skips user
# config, so the stubbed hl.* API below is the ONLY thing the config sees).
# Same approach as omarchy-menu-keybindings. Emits TSV per described bind:
#   modmask <TAB> description <TAB> key <TAB> kind <TAB> arg
# kind is "exec" (arg = shell command) or "lua" (arg = dispatch expression).
# ---------------------------------------------------------------------------

scan_hypr() {
  local scanner
  scanner=$(mktemp /tmp/keybinds-scan.XXXXXX.lua)

  cat >"$scanner" <<'LUA'
local modifiers = { SHIFT = 1, CTRL = 4, CONTROL = 4, ALT = 8, SUPER = 64 }

local function split_keys(keys)
  local modmask, key = 0, ""
  for part in string.gmatch(tostring(keys or ""), "[^+]+") do
    part = part:gsub("^%s+", ""):gsub("%s+$", "")
    local m = modifiers[string.upper(part)]
    if m then modmask = modmask + m else key = part end
  end
  return modmask, key
end

local function lua_literal(value)
  local t = type(value)
  if t == "string" then return string.format("%q", value) end
  if t == "number" or t == "boolean" then return tostring(value) end
  if t == "table" then
    local parts = {}
    for i = 1, #value do parts[#parts + 1] = lua_literal(value[i]) end
    local keys = {}
    for k in pairs(value) do
      if not (type(k) == "number" and k >= 1 and k <= #value and math.floor(k) == k) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = "[" .. lua_literal(k) .. "] = " .. lua_literal(value[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return "nil"
end

local function call_expression(path, ...)
  local args = {}
  for i = 1, select("#", ...) do args[i] = lua_literal(select(i, ...)) end
  return path .. "(" .. table.concat(args, ", ") .. ")"
end

local function dispatcher(kind, arg, expr)
  return { __omarchy_dispatcher = true, kind = kind or "", arg = arg or "", expr = expr or "" }
end

local function dsp_proxy(path)
  return setmetatable({ path = path }, {
    __index = function(self, key) return dsp_proxy(self.path .. "." .. tostring(key)) end,
    __call = function(self, ...)
      local first = ...
      local expr = call_expression(self.path, ...)
      if self.path == "hl.dsp.exec_cmd" and type(first) == "string" then
        return dispatcher("exec", first, expr)
      end
      return dispatcher("lua", expr, expr)
    end,
  })
end

local noop
noop = setmetatable({}, { __index = function() return noop end, __call = function() return noop end })

hl = setmetatable({
  dsp = dsp_proxy("hl.dsp"),
  bind = function(keys, d, opts)
    opts = opts or {}
    if opts.description and opts.description ~= "" then
      local modmask, key = split_keys(keys)
      local kind, arg = "", ""
      if type(d) == "table" and d.__omarchy_dispatcher then
        kind, arg = d.kind, (d.arg or "")
      elseif type(d) == "string" and d ~= "" then
        kind, arg = "exec", d
      end
      print(table.concat({ tostring(modmask), opts.description, key, kind, arg }, "\t"))
    end
    return noop
  end,
}, { __index = function() return noop end })

local config = os.getenv("HOME") .. "/.config/hypr/hyprland.lua"
local file = io.open(config, "r")
if file then
  file:close()
  local ok, err = pcall(dofile, config)
  if not ok then
    io.stderr:write("[scan] " .. tostring(err) .. "\n")
    os.exit(1)
  end
end
LUA

  nvim -l "$scanner"
  local status=$?
  rm -f "$scanner"
  return $status
}

# ---------------------------------------------------------------------------
# Collectors emit unified TSV records:
#   tool <TAB> chord <TAB> action <TAB> kind <TAB> arg
# kind/arg are only meaningful for hypr rows (dispatch); empty otherwise.
# Each collector degrades to "emit nothing" on failure (collect() reports).
# ---------------------------------------------------------------------------

collect_hypr() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  [[ -f $HYPR_CONFIG ]] || return 0

  local scan="" modmask desc key kind arg k mods chord
  scan=$(scan_hypr 2>/dev/null) || scan=""

  declare -A seen=()

  # Source scan first: these rows have descriptions AND dispatch info.
  if [[ -n $scan ]]; then
    while IFS=$'\t' read -r modmask desc key kind arg; do
      [[ -z ${modmask:-} || -z ${desc:-} ]] && continue
      k="${modmask}|${key,,}"
      seen["$k"]=1
      mods=$(modmask_to_text "$modmask")
      if [[ -n $mods ]]; then
        chord="$mods + $(display_key "$key")"
      else
        chord="$(display_key "$key")"
      fi
      printf 'hypr\t%s\t%s\t%s\t%s\n' "$chord" "$desc" "$kind" "$arg"
    done <<<"$scan"
  fi

  # Live binds the scan doesn't know about (added at runtime, or scan
  # failure): emit info-poor rows using whatever description Hyprland has.
  local live parsed
  live=$(hyprctl binds 2>/dev/null) || live=""
  [[ -n $live ]] || return 0

  parsed=$(awk '
    function emit() {
      if (!seen) return
      seen = 0
      printf "%s\x1f%s\x1f%s\n", f["modmask"], f["key"], f["description"]
    }
    /^bind/ { emit(); seen = 1; delete f; next }
    seen && match($0, /^\t[a-z]+: /) { f[substr($0, 2, RLENGTH - 3)] = substr($0, RLENGTH + 1) }
    END { emit() }
  ' <<<"$live")

  while IFS=$'\x1f' read -r modmask key desc; do
    [[ -z ${key:-} ]] && continue
    k="${modmask}|${key,,}"
    [[ -n ${seen[$k]:-} ]] && continue
    [[ -z ${desc:-} ]] && desc="(runtime bind)"
    mods=$(modmask_to_text "$modmask")
    if [[ -n $mods ]]; then
      chord="$mods + $(display_key "$key")"
    else
      chord="$(display_key "$key")"
    fi
    printf 'hypr\t%s\t%s\t\t\n' "$chord" "$desc"
  done <<<"$parsed"
}

# --- COLLECTORS: (tmux, ghostty, nvim collectors are added above this line
# --- in later commits; collect() skips anything not yet defined) ---------

# ---------------------------------------------------------------------------
# Cache: keyed on tracked config contents + live binds + this script itself
# ---------------------------------------------------------------------------

cache_key() {
  {
    printf 'v1\n'
    sha256sum "$0" 2>/dev/null || printf 'script\n'
    local f
    for f in "$HYPR_CONFIG" "$NVIM_CONFIG" "$NVIM_LOCK" "$TMUX_CONFIG" "$GHOSTTY_CONFIG"; do
      if [[ -f $f ]]; then
        printf '%s ' "$(basename "$f")"
        sha256sum <"$f"
      fi
    done
    hyprctl binds 2>/dev/null || true
  } | sha256sum | cut -d' ' -f1
}

records() {
  local key file tmp
  key=$(cache_key)
  file="$CACHE_DIR/records-$key.tsv"

  if [[ -s $file && $refresh != true ]]; then
    cat "$file"
    return 0
  fi

  mkdir -p "$CACHE_DIR"
  tmp=$(mktemp "$CACHE_DIR/records.XXXXXX")
  if ! collect >"$tmp" || [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    echo "keybinds-cheatsheet: no records collected" >&2
    return 1
  fi
  mv "$tmp" "$file"
  find "$CACHE_DIR" -maxdepth 1 -name 'records-*.tsv' ! -name "records-$key.tsv" -delete 2>/dev/null || true
  cat "$file"
}

collect() {
  local c
  for c in $TOOL_ORDER; do
    if type "collect_$c" >/dev/null 2>&1; then
      "collect_$c" || echo "keybinds-cheatsheet: collector '$c' failed" >&2 || true
    fi
  done
}

# ---------------------------------------------------------------------------
# Formatting and (task: UI) main
# ---------------------------------------------------------------------------

format_rows() {
  awk -F'\t' -v order="$TOOL_ORDER" '
    BEGIN {
      n = split(order, o, " ")
      for (i = 1; i <= n; i++) prio[o[i]] = i
    }
    { printf "%03d\t[%s] %s → %s\n", prio[$1], $1, $2, $3 }
  ' | sort | cut -f2- | awk '!seen[$0]++'
}

main() {
  if [[ -n $print_only ]]; then
    local rows
    rows=$(records | format_rows) || return 1
    if [[ $print_only != all ]]; then
      rows=$(grep -F "[$print_only] " <<<"$rows" || true)
    fi
    [[ -n $rows ]] && printf '%s\n' "$rows"
    return 0
  fi

  echo "keybinds-cheatsheet: menu not wired yet (add in a later task)" >&2
  return 1
}

main "$@"
```

- [ ] **Step 3: Deploy and verify the Hyprland collector**

Run: `chezmoi apply && ~/.local/bin/keybinds-cheatsheet --refresh --print hypr | wc -l`
Expected: `73`.

Run: `~/.local/bin/keybinds-cheatsheet --print hypr | grep 'SUPER + RETURN'`
Expected: `[hypr] SUPER + RETURN → Terminal`

Run: `~/.local/bin/keybinds-cheatsheet --print hypr | grep -F '[hypr] SUPER + SLASH'`
Expected: `[hypr] SUPER + SLASH → Keyboard cheatsheet`

Run: `~/.local/bin/keybinds-cheatsheet --print hypr | grep 'ALT + TAB'`
Expected: `[hypr] ALT + TAB → Window switcher`

- [ ] **Step 4: Verify the cache hit path**

Run: `keybinds-cheatsheet --print hypr | wc -l && ls ~/.cache/keybinds-cheatsheet/`
Expected: `73` again, and exactly one `records-*.tsv` file.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_keybinds-cheatsheet
git commit -m "Add keybinds-cheatsheet: skeleton, cache, Hyprland collector"
```

---

### Task 5: tmux collector

**Files:**
- Modify: `dot_local/bin/executable_keybinds-cheatsheet` (insert before the `# --- COLLECTORS:` marker)

- [ ] **Step 1: Add the collector**

Insert immediately above the `# --- COLLECTORS:` comment block:

```bash
collect_tmux() {
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -f $TMUX_CONFIG ]] || return 0

  local socket_dir socket out
  socket_dir=$(mktemp -d) || return 1
  socket="$socket_dir/tmux"
  trap 'tmux -S "$socket" kill-server >/dev/null 2>&1 || true; rm -f "$socket"; rmdir "$socket_dir" 2>/dev/null || true' RETURN

  # Isolated throwaway server: unbind every table, load ONLY the user's
  # config, then list everything with tmux's own command notes (-N).
  if ! out=$(tmux -S "$socket" -f /dev/null start-server \; \
      unbind-key -a -T prefix \; \
      unbind-key -a -T root \; \
      unbind-key -a -T copy-mode \; \
      unbind-key -a -T copy-mode-vi \; \
      source-file "$TMUX_CONFIG" \; \
      show-options -g prefix \; \
      show-options -g prefix2 \; \
      list-keys -aN -T prefix -P "prefix" \; \
      list-keys -aN -T root -P "root" \; \
      list-keys -aN -T copy-mode-vi -P "copy-mode-vi" 2>/dev/null); then
    return 1
  fi
  [[ -n $out ]] || return 1

  printf '%s\n' "$out" | awk '
    function key_part(part, is_mod) {
      gsub(/^\\/, "", part)
      if (is_mod && part == "C") return "CTRL"
      if (is_mod && part == "M") return "ALT"
      if (is_mod && part == "S") return "SHIFT"
      if (part == "Space") return "SPACE"
      if (part == "BSpace") return "BACKSPACE"
      if (part == "BTab") return "SHIFT TAB"
      if (part == "PPage") return "PAGE UP"
      if (part == "NPage") return "PAGE DOWN"
      if (part == "DC") return "DELETE"
      if (part == "IC") return "INSERT"
      return toupper(part)
    }
    function key_text(key,  parts, n, i, text) {
      gsub(/\\/, "", key)
      n = split(key, parts, "-")
      text = ""
      for (i = 1; i <= n; i++)
        text = text (text == "" ? "" : " ") key_part(parts[i], i < n)
      return text
    }
    $1 == "prefix" && NF == 2  { prefix = $2; next }
    $1 == "prefix2" && NF == 2 { prefix2 = $2; next }
    {
      if (!hdr) {
        p = key_text(prefix)
        if (prefix2 != "" && prefix2 != "None") p = p " / " key_text(prefix2)
        printf "tmux\tPREFIX\t%s\n", p
        hdr = 1
      }
      table = $1
      key = $2
      note = $0
      sub(/^[^ ]+ +[^ ]+ +/, "", note)
      if (table == "root") combo = key_text(key)
      else if (table == "copy-mode-vi") combo = "COPY MODE + " key_text(key)
      else combo = "PREFIX + " key_text(key)
      if (length(note) > 70) note = substr(note, 1, 67) "..."
      printf "tmux\t%s\t%s\n", combo, note
    }
  ' | awk -F'\t' '!seen[$0]++'
}
```

- [ ] **Step 2: Deploy and verify**

Run: `chezmoi apply && keybinds-cheatsheet --refresh --print tmux | wc -l`
Expected: a number > 120 (measured live: 117 prefix binds + root + copy-mode + PREFIX header).

Run: `keybinds-cheatsheet --print tmux | head -1`
Expected: `[tmux] PREFIX → CTRL B / CTRL A`

Run: `keybinds-cheatsheet --print tmux | grep -F 'PREFIX + ?'`
Expected: a row whose action mentions listing keys (the `?` bind).

- [ ] **Step 3: Verify the real tmux server was untouched**

Run: `tmux list-sessions && tmux list-keys -T prefix | head -2`
Expected: your real sessions still listed; keys intact (the collector only ever used its own throwaway socket).

- [ ] **Step 4: Commit**

```bash
git add dot_local/bin/executable_keybinds-cheatsheet
git commit -m "Add tmux collector to keybinds-cheatsheet"
```

---

### Task 6: Ghostty collector

**Files:**
- Modify: `dot_local/bin/executable_keybinds-cheatsheet` (insert before the `# --- COLLECTORS:` marker)

- [ ] **Step 1: Add the collector**

Insert immediately above the `# --- COLLECTORS:` comment block:

```bash
ghostty_trigger_text() {
  local part out=()
  local IFS='+'
  read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    out+=("${part^^}")
  done
  local IFS=' '
  echo "${out[*]}"
}

ghostty_action_text() {
  local action="${1%%:*}"
  local params="${1#*:}"
  [[ $params == "$1" ]] && params=""

  case "$action" in
    copy_to_clipboard)      echo "Copy to clipboard" ;;
    paste_from_clipboard)   echo "Paste from clipboard" ;;
    paste_from_selection)   echo "Paste from selection" ;;
    increase_font_size)     echo "Increase font size" ;;
    decrease_font_size)     echo "Decrease font size" ;;
    reset_font_size)        echo "Reset font size" ;;
    goto_tab)               echo "Go to tab $params" ;;
    last_tab)               echo "Last tab" ;;
    next_tab)               echo "Next tab" ;;
    previous_tab)           echo "Previous tab" ;;
    new_tab)                echo "New tab" ;;
    close_tab)              echo "Close tab" ;;
    toggle_fullscreen)      echo "Toggle fullscreen" ;;
    toggle_split_zoom)      echo "Toggle split zoom" ;;
    toggle_command_palette) echo "Command palette" ;;
    reload_config)          echo "Reload config" ;;
    open_config)            echo "Open config" ;;
    write_screen_file)      echo "Save screen to file" ;;
    text)                   echo "Send text escape" ;;
    *)                      echo "$action" | sed -E 's/_/ /g; s/\b(.)/\U\1/g' ;;
  esac
}

collect_ghostty() {
  command -v ghostty >/dev/null 2>&1 || return 0

  local trigger action
  ghostty +list-keybinds 2>/dev/null | sed 's/^keybind = //' |
    while IFS='=' read -r trigger action; do
      # ghostty lists both alt+digit_N and alt+N aliases; keep one
      [[ $trigger == *digit_* ]] && continue
      printf 'ghostty\t%s\t%s\n' "$(ghostty_trigger_text "$trigger")" "$(ghostty_action_text "$action")"
    done
}
```

- [ ] **Step 2: Deploy and verify**

Run: `chezmoi apply && keybinds-cheatsheet --refresh --print ghostty | wc -l`
Expected: a number around 64 (73 total minus the `digit_` aliases).

Run: `keybinds-cheatsheet --print ghostty | grep -F 'CTRL SHIFT C'`
Expected: `[ghostty] CTRL SHIFT C → Copy to clipboard`

Run: `keybinds-cheatsheet --print ghostty | grep -F 'SHIFT ENTER'`
Expected: `[ghostty] SHIFT ENTER → Send text escape`

- [ ] **Step 3: Commit**

```bash
git add dot_local/bin/executable_keybinds-cheatsheet
git commit -m "Add ghostty collector to keybinds-cheatsheet"
```

---

### Task 7: nvim collector

**Files:**
- Modify: `dot_local/bin/executable_keybinds-cheatsheet` (insert before the `# --- COLLECTORS:` marker)

- [ ] **Step 1: Add the key translator and collector**

Insert immediately above the `# --- COLLECTORS:` comment block:

```bash
# Translate an nvim key-notation lhs (e.g. "<C-h>", "<leader>sf", "<Esc>")
# into cheatsheet style ("CTRL H", "LEADER SF", "ESC"). mapleader is a
# literal space, so a leading space in lhs means leader.
nvim_lhs_text() {
  printf '%s\n' "$1" | perl -pe '
    s/\A /LEADER /;
    s/<leader>/LEADER/g;
    s/<C-([A-Za-z])>/CTRL \U$1\E/g;
    s/<C-\\>/CTRL BACKSLASH/g;
    s/<([MA])-([A-Za-z])>/ALT \U$2\E/g;
    s/<S-([A-Za-z]+)>/SHIFT \U$1\E/g;
    s/<D-([A-Za-z])>/CMD \U$1\E/g;
    s/<CR>/ENTER/gi;      s/<Enter>/ENTER/g;
    s/<Esc>/ESC/g;        s/<Tab>/TAB/g;      s/<BS>/BACKSPACE/g;
    s/<Space>/SPACE/g;    s/<Del>/DELETE/g;
    s/<PageUp>/PAGE UP/gi;   s/<PageDown>/PAGE DOWN/gi;
    s/<Home>/HOME/gi;     s/<End>/END/gi;
    s/<Up>/UP/g; s/<Down>/DOWN/g; s/<Left>/LEFT/g; s/<Right>/RIGHT/g;
    s/<nowait>//gi;       s/<silent>//gi;
    s/<F(\d+)>/F$1/g;
    s/<([A-Za-z0-9_-]+)>/\U$1\E/g;
    s/([a-z])/\U$1/g;
  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

collect_nvim() {
  command -v nvim >/dev/null 2>&1 || return 0
  [[ -f $NVIM_CONFIG ]] || return 0

  # --headless loads the user config (plugins included: telescope, neo-tree,
  # ...), so this dump sees every effective mapping with its description.
  # Only mappings WITH a description are kept — that drops keymap noise
  # without losing anything the user can act on meaningfully.
  local dump raw m lhs desc
  dump=$(mktemp /tmp/keybinds-nvim.XXXXXX.lua)
  cat >"$dump" <<'LUA'
local modes = { 'n', 'x', 's', 'o', 'i', 't', 'c' }
local rows = {}
for _, m in ipairs(modes) do
  for _, k in ipairs(vim.api.nvim_get_keymap(m)) do
    if k.desc and k.desc ~= '' and k.lhs and k.lhs ~= '' then
      rows[#rows + 1] = string.format('%s\t%s\t%s', m, k.lhs, k.desc)
    end
  end
end
print(table.concat(rows, '\n'))
LUA

  raw=$(nvim --headless +"lua dofile('$dump')" +qa 2>/dev/null) || raw=""
  rm -f "$dump"
  [[ -n $raw ]] || return 0

  while IFS=$'\t' read -r m lhs desc; do
    [[ -z ${m:-} ]] && continue
    printf 'nvim\t%s %s\t%s\n' "$m" "$(nvim_lhs_text "$lhs")" "$desc"
  done <<<"$raw" | awk -F'\t' '!seen[$0]++'
}
```

- [ ] **Step 2: Deploy and verify**

Run: `chezmoi apply && keybinds-cheatsheet --refresh --print nvim | wc -l`
Expected: roughly 180-215 rows (measured live: 213 described maps across modes before dedup).

Run: `keybinds-cheatsheet --print nvim | grep -F 'LEADER SF'`
Expected: `[nvim] n LEADER SF → [S]earch [F]iles`

Run: `keybinds-cheatsheet --print nvim | grep -F 'n CTRL H'`
Expected: `[nvim] n CTRL H → Move focus to the left window`

Run: `keybinds-cheatsheet --print nvim | grep -F 't ESC ESC'`
Expected: `[nvim] t ESC ESC → Exit terminal mode`

- [ ] **Step 3: Verify the full dump and cache**

Run: `keybinds-cheatsheet --print | wc -l`
Expected: total of all four tools (73 + ~150 + ~64 + ~200 ≈ 480-500 rows).

Run: `keybinds-cheatsheet --print | cut -d' ' -f1 | sort | uniq -c`
Expected: four lines, one per `[hypr]`, `[tmux]`, `[ghostty]`, `[nvim]`.

- [ ] **Step 4: Commit**

```bash
git add dot_local/bin/executable_keybinds-cheatsheet
git commit -m "Add nvim collector to keybinds-cheatsheet"
```

---

### Task 8: fuzzel menu, selection dispatch, and test hook

**Files:**
- Modify: `dot_local/bin/executable_keybinds-cheatsheet` (replace `main()`)

- [ ] **Step 1: Replace main() with the menu + dispatch version**

Replace the entire existing `main()` function (and keep `main "$@"` after it) with:

```bash
dispatch_selection() {
  local tool="$1" chord="$2" kind="$3" arg="$4"

  case "$tool:$kind" in
    hypr:exec)
      if ! hyprctl dispatch exec "$arg" >/dev/null 2>&1; then
        noctalia msg notification-show 'Cheatsheet' "Dispatch failed: $chord" 2>/dev/null || true
      fi
      ;;
    hypr:lua)
      if ! hyprctl eval "$arg" >/dev/null 2>&1; then
        noctalia msg notification-show 'Cheatsheet' "Dispatch failed: $chord" 2>/dev/null || true
      fi
      ;;
    *) : ;;
  esac
}

main() {
  if [[ -n $print_only ]]; then
    local rows
    rows=$(records | format_rows) || return 1
    if [[ $print_only != all ]]; then
      rows=$(grep -F "[$print_only] " <<<"$rows" || true)
    fi
    [[ -n $rows ]] && printf '%s\n' "$rows"
    return 0
  fi

  if [[ -z $selection ]]; then
    command -v fuzzel >/dev/null 2>&1 || {
      echo "keybinds-cheatsheet: fuzzel is not installed" >&2
      return 1
    }
    selection=$(records | format_rows | fuzzel --dmenu --prompt 'binds ') || return 0
  fi
  [[ -n $selection ]] || return 0

  local record tool chord action kind arg
  record=$(records | awk -F'\t' -v sel="$selection" \
    'sprintf("[%s] %s → %s", $1, $2, $3) == sel { print; exit }')
  [[ -n $record ]] || return 0

  IFS=$'\t' read -r tool chord action kind arg <<<"$record"
  dispatch_selection "$tool" "$chord" "${kind:-}" "${arg:-}"
}

main "$@"
```

- [ ] **Step 2: Deploy and test the exec dispatch path (harmless: toggles Noctalia settings panel)**

Run: `chezmoi apply && keybinds-cheatsheet --select '[hypr] SUPER + PERIOD → Noctalia settings'; echo "exit=$?"`
Expected: `exit=0` and the Noctalia settings panel toggles on the user's screen.

- [ ] **Step 3: Test the lua dispatch path (harmless: focuses left window or no-op)**

Run: `keybinds-cheatsheet --select '[hypr] SUPER + H → Focus window left'; echo "exit=$?"`
Expected: `exit=0`; focus moves left if a left window exists.

- [ ] **Step 4: Test a non-hypr row does nothing**

Run: `keybinds-cheatsheet --select '[tmux] PREFIX → CTRL B / CTRL A'; echo "exit=$?"`
Expected: `exit=0`, nothing happens.

- [ ] **Step 5: Test the real menu interactively (needs the user's screen)**

Run: `keybinds-cheatsheet`
Expected: centered fuzzel popup, rows grouped hypr → tmux → ghostty → nvim. Type `termi`, confirm `SUPER + RETURN → Terminal` surfaces; press Esc — popup closes, script exits 0. Note the popup appearance for the user to confirm.

- [ ] **Step 6: Commit**

```bash
git add dot_local/bin/executable_keybinds-cheatsheet
git commit -m "Wire fuzzel menu and hypr dispatch into keybinds-cheatsheet"
```

---

### Task 9: Launcher entry and prerequisite docs

**Files:**
- Create: `dot_local/share/applications/keybinds-cheatsheet.desktop`
- Modify: `README.md` (Prerequisites → System packages table)

- [ ] **Step 1: Create the desktop entry**

Create `dot_local/share/applications/keybinds-cheatsheet.desktop` with exactly:

```ini
[Desktop Entry]
Type=Application
Name=Keyboard Cheatsheet
Comment=Searchable keybindings for Hyprland, tmux, Ghostty and Neovim
Exec=/home/gunny/.local/bin/keybinds-cheatsheet
Icon=input-keyboard
Categories=Utility;
NoDisplay=false
```

(Absolute Exec path matches the existing `hyprland-toggle-layout.desktop` pattern — desktop launches don't reliably have `~/.local/bin` on PATH.)

- [ ] **Step 2: Add fuzzel to the README prerequisites table**

In `README.md`, find the *Prerequisites → System packages* table (rows for tmux, fzf, git, fish, ...). Add a row after the `fzf` row:

```markdown
| fuzzel | `sudo dnf install fuzzel` | `sudo apt install fuzzel` | — (Wayland only) |
```

- [ ] **Step 3: Deploy and verify the launcher sees it**

Run: `chezmoi apply && update-desktop-database ~/.local/share/applications 2>/dev/null; grep -c Name= ~/.local/share/applications/keybinds-cheatsheet.desktop`
Expected: `1`. Then have the user open the Noctalia launcher (SUPER+SPACE), type `cheat`, and confirm "Keyboard Cheatsheet" appears and launches the popup.

- [ ] **Step 4: Commit**

```bash
git add dot_local/share/applications/keybinds-cheatsheet.desktop README.md
git commit -m "Add Keyboard Cheatsheet launcher entry and fuzzel prerequisite"
```

---

### Task 10: End-to-end verification

**Files:** none (verification only; commit only if fixes were needed)

- [ ] **Step 1: SUPER+SLASH opens the cheatsheet**

Have the user press SUPER+SLASH. Expected: popup appears. Esc closes it.

- [ ] **Step 2: Launcher entry opens the cheatsheet**

As in Task 9 Step 3. Expected: popup appears.

- [ ] **Step 3: Dispatch from the menu**

Open the menu, type `settings`, select the `SUPER + PERIOD → Noctalia settings` row. Expected: settings panel toggles (menu closes on selection).

- [ ] **Step 4: Cache invalidation**

Run: `ls ~/.cache/keybinds-cheatsheet/ | wc -l && printf '\n-- cache test\n' >> ~/.config/hypr/hyprland.lua && keybinds-cheatsheet --print hypr | wc -l && ls ~/.cache/keybinds-cheatsheet/ | wc -l && chezmoi apply`
Expected: `1`, then `73`, then `1` (the content change produced a new cache file and pruned the old; `chezmoi apply` then restores the deployed config from the untouched repo).

- [ ] **Step 5: Degraded mode sanity**

Run: `PATH=/usr/bin:/bin ~/.local/bin/keybinds-cheatsheet --print | grep -c '^\[' || echo "degraded-ok"`
Expected: a row count (hypr rows survive — hyprctl/nvim/tmux/ghostty all live in /usr/bin) with the script never exiting nonzero with a stack trace. (Collectors whose binaries vanish from PATH skip cleanly via the `command -v` guards.)

- [ ] **Step 6: Final commit (only if any fixups were made)**

```bash
git add -A
git commit -m "Polish keybinds cheatsheet from end-to-end verification"
```
