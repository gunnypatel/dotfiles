# Keybinds Cheatsheet — Design

Date: 2026-08-30
Status: approved (pre-implementation)

## Problem

Keybindings live in five places (Hyprland Lua config, nvim, tmux, Ghostty
defaults, muscle memory) with no quick way to see them. Want: a fuzzy-searchable
cheatsheet covering all installed tools, launchable from the Noctalia launcher
and a global keybind. Omarchy's `omarchy-menu-keybindings` (source:
`~/repos/omarchy`) is the reference; its menu UI (omarchy-shell Quickshell
summon) is not portable to Noctalia, but its extraction logic is.

## Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Presentation | `fuzzel --dmenu` | Native Wayland layer-shell popup, fuzzy, instant. ~1 MiB install (fuzzel + fcft/nanosvg/utf8proc, Fedora repo). Noctalia has no generic menu API; fzf-in-Ghostty and zenity rejected (terminal flash / weak search). |
| Hypr bind data | Descriptions in config + `nvim -l` source scan, merged with `hyprctl binds` | `hyprctl binds` reports Lua binds as dispatcher `__lua` with opaque `arg` (callback id) and no description. Source scan (Omarchy's approach) provides descriptions and dispatch expressions. No standalone `lua` binary — use `nvim -l`. |
| nvim binds | Headless `nvim --headless` dump of `nvim_get_keymap()` + cache | Accurate: includes plugin maps (telescope, neo-tree…). ~1s cold; cached. |
| Select behavior | Hypr rows dispatch; other tools' rows close | Matches Omarchy UX; dispatch possible only for hypr (scan provides expressions). |
| Launch | `.desktop` entry + SUPER+SLASH | Slash = "?" mnemonic; unused in current config. |
| Scope | Hyprland, nvim, tmux, Ghostty | Fish has no custom binds/abbrs; wezterm/kitty installed but not the daily terminal. Sources stay pluggable for later. |

## Components

All changes in this chezmoi repo. New system package: `fuzzel` (dnf).

### 1. `dot_local/bin/executable_keybinds-cheatsheet` (new, ~250 lines bash)

Single script containing:

- **Collectors** (one function per tool) emitting TSV records:
  `tool \t chord \t action \t dispatch \t arg`
- **Hyprland collector**:
  - `hyprctl binds` (plain-text parse as in Omarchy): modmask → text
    (SUPER/SHIFT/CTRL/ALT), key normalization (comma→COMMA, grave→~,
    bracketleft→[ …), mouse binds → "MOUSE LEFT/RIGHT".
  - Embedded scanner (Lua heredoc run via `nvim -l`): stubs the `hl.*` API
    (port of Omarchy's `dsp_proxy` + `lua_literal`), `dofile`s
    `~/.config/hypr/hyprland.lua`, prints
    `modmask \t description \t key \t kind \t arg` for every `hl.bind` with a
    description. No-ops for `hl.monitor/config/env/curve/animation/on/
    workspace_rule/window_rule/layer_rule/dispatch/exec_cmd`.
  - Merge on modmask+key: live truth from `hyprctl binds`, labels + dispatch
    expressions from the scan.
- **nvim collector**: `nvim --headless -u ~/.config/nvim/init.lua` evaluating
  `nvim_get_keymap()` for modes n/v/x/s/o/i/t, JSON to stdout via `vim.json`.
  Rows require a non-empty `desc` (plugin noise without descriptions is
  dropped). Key display translation: `<C-h>`→`CTRL H`, `<leader>sf`→`LEADER S F`,
  `<Esc>`→`ESC`, special keys uppercased; mode prefix on the chord
  (e.g. `n LEADER S F`, `i CTRL H`, `t ESC ESC`). Leader resolved from
  `vim.g.mapleader`.
- **tmux collector**: Omarchy's isolated-server trick (temp socket, unbind all,
  source `~/.config/tmux/tmux.conf`, `list-keys -aN` for prefix/root/
  copy-mode-vi tables with key notes) + PREFIX header row showing the prefix
  chord.
- **ghostty collector**: `ghostty +list-keybinds` (`trigger=action` lines);
  actions prettified (`copy_to_clipboard:mixed` → "Copy", `increase_font_size:1`
  → "Increase font size"); triggers normalized (`ctrl+shift+c` → `CTRL SHIFT C`).
- **Cache**: `~/.cache/keybinds-cheatsheet/records.tsv` keyed by sha256 of
  (hyprland.lua, nvim init.lua + nvim-pack-lock.json, tmux.conf, ghostty
  config, `hyprctl binds` output). Atomic write (mktemp + mv). Corrupt/empty
  → regenerate.
- **UI**: rows formatted `[tool] CHORD → action`, section order hypr, tmux,
  ghostty, nvim; piped to
  `fuzzel --dmenu --prompt 'binds '`. On selection, look up the record by
  exact row text (awk over records, Omarchy-style); dispatch hypr rows:
  - `exec` kind → `hyprctl dispatch exec "<arg>"`
  - lua expressions → `hyprctl eval "<expr>"` (verify vs
    `hyprctl dispatch "<expr>"`; whichever works on Hyprland 0.56.x — spike
    step below)
  - non-hypr or no dispatch → exit 0
- **Flags**: `--print` (dump formatted rows, no UI — test/debug mode),
  `--refresh` (ignore cache once).

### 2. `dot_config/hypr/hyprland.lua` (edit)

- Add `{ description = "..." }` to every `hl.bind` call, including
  loop-generated binds (workspace/focus/move binds get programmatic
  descriptions: "Focus workspace 3", "Move window left", …).
- New bind:
  `hl.bind(mainMod .. " + SLASH", hl.dsp.exec_cmd("keybinds-cheatsheet"), { description = "Keyboard cheatsheet" })`
- No window rules needed: fuzzel is layer-shell, never tiles.

### 3. `dot_config/fuzzel/fuzzel.ini` (new)

- Theme: Catppuccin Mocha Green to match the Noctalia palette; same font
  family as the Noctalia bar.
- Geometry: ~900px wide, ~15 lines, anchored center, dmenu-friendly
  (no icons, prompt `binds ❯`).

### 4. `dot_local/share/applications/keybinds-cheatsheet.desktop` (new)

- Name=Keyboard Cheatsheet, Exec=keybinds-cheatsheet,
  Icon=input-keyboard, Categories=Utility. Same pattern as
  `hyprland-toggle-layout.desktop`.

### 5. Repo housekeeping

- `docs/` added to `.chezmoiignore` (repo metadata, like README.md/Brewfile).
- README: document `fuzzel` as a desktop prerequisite alongside existing ones.

## Data flow

```
launch (SUPER+/ or Noctalia launcher)
  → cache key fresh? yes → load records
                     no  → run 4 collectors → merge → atomic cache write
  → format rows "[tool] CHORD → action" (hypr, tmux, ghostty, nvim)
  → fuzzel --dmenu
  → Esc/other-tool row → exit 0
  → hypr row → dispatch (exec via hyprctl dispatch exec; lua via hyprctl eval)
```

## Error handling

- Collector failure/empty → omit that section; exit nonzero only if all fail.
- Scanner failure → degraded hypr rows from `hyprctl binds` (no labels, no
  dispatch); picks in that state just close.
- Dispatch failure after config drift → `noctalia msg notification-show`
  (matches `hyprland-toggle-layout` pattern), exit 0.
- Cache corruption → regenerate; never serve a broken file.
- fuzzel cancelled → clean exit 0.

## Testing

No test framework in the repo; verification is manual + built-in modes:

1. `keybinds-cheatsheet --print` — assert known rows: `SUPER + RETURN`,
   tmux `PREFIX`, ghostty `CTRL SHIFT C`, nvim `LEADER S F`.
2. Scanner sanity: record count ≈ `hl.bind` call count in hyprland.lua
   (loops expand programmatically).
3. Dispatch: one exec bind (SUPER+RETURN opens terminal), one lua bind
   (close a disposable window).
4. Cache: touch a config → regenerates; untouched → cache hit (mtimes/keys).
5. Spike first: (a) descriptions surface in `hyprctl binds` on this Hyprland
   build; (b) `hyprctl eval` vs `hyprctl dispatch` for Lua bind expressions.

## Risks / assumptions

- Descriptions in `hyprctl binds` for Lua binds: high confidence (Omarchy
  depends on it; `description:` field exists in current output), but scanner
  provides desc regardless — design holds either way.
- Headless nvim dump loads plugins; first run ~1s (accepted; cached).
- `nvim -l` as Lua interpreter for the scanner: nvim is a hard dependency of
  this setup; stubbed API must track Hyprland's Lua API surface if new bind
  options are used later (maintainable: it no-ops everything).

## Out of scope

- wezterm/kitty sections, fish binds, opencode TUI keys (pluggable later).
- Dispatching non-hypr rows.
- Any Noctalia QML modification.
