# Master Width Utility — Design

Date: 2026-09-10
Status: approved (pre-implementation)

## Problem

The master layout width (`mfact`) can only be adjusted blindly with
SUPER+[ / SUPER+] — there is no way to see the current width, apply a
known-good width, or set one by explicit value. Want: a launcher-runnable
utility listing preconfigured widths (e.g. gaming = 65% master) plus a custom
value prompt, applied to the current workspace.

The existing one-off auto-apply for the gaming workspace (applied once per
session from a `workspace.active` handler) is broken and gets deleted, not
fixed.

## Why the auto-apply broke (Hyprland 0.56.2 source findings)

Recorded so the mechanism isn't resurrected in the same shape:

- The `layout mfact` dispatcher requires a focused window **and** an existing
  master node. On an empty workspace it fails silently — while the one-shot
  `gamingMfactSet` flag still burned, so later activations never retried.
- `percMaster` is stored on the master **node**, not the workspace. It is
  re-seeded from the global config (`master:mfact` = 0.42) whenever a
  workspace transitions through empty (e.g. Steam restart). Any apply-once
  scheme is therefore inherently racy; reliable auto-apply would need
  re-apply-on-every-activation semantics. Chosen alternative: manual utility
  that makes setting the width trivial and visible.

## Decisions (from brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Approach | Launcher utility only; no auto-apply | User choice after root-cause findings; menu makes width explicit and visible, SUPER+[/] remain for nudges. |
| Presentation | `fuzzel --dmenu` | Keybinds-cheatsheet pattern ("similar to the cheatsheet"); native layer-shell popup. |
| Custom input | `Custom…` row → `zenity --entry` | ws-rename pattern; fuzzel dmenu only prints *selected* rows, so typed passthrough can't be relied on. |
| Apply mechanism | `hyprctl dispatch "hl.dsp.layout('mfact exact P')"` | Proven on Lua configs by ws-rename (`hl.dsp.workspace.rename`); `mfact exact` confirmed in MasterAlgorithm.cpp (clamped 0.05–0.95). |
| Current-width display | Widest tiled window on active workspace ÷ monitor logical width, from `hyprctl -j clients` | Only readable source of the live per-workspace ratio; shown in the fuzzel prompt. It is the *rendered* share (gaps included), so a 42 preset shows ~40 rendered — labeled as such. |
| Presets | Table at top of script | Single consumer; one line to add a preset. |
| Scope of apply | Current workspace only | mfact is per-workspace state in Hyprland itself; the utility never targets other workspaces. |

## Components

### 1. `dot_config/hypr/hyprland.lua` (edit)

Delete `gamingMfact` (line 189), `gamingMfactApply()` (209–213) and
`gamingMfactSet` with its `workspace.active` handler (226–234). Everything
else in the gaming block stays (workspace name, binds, window rules,
persistent rule). No new Lua code.

### 2. `dot_local/bin/executable_hyprland-master-width` (new, ~80 lines sh)

- Preset table at the top, one line per preset:

  ```
  42   Default (27"-comfort window)
  50   Half
  65   Gaming (wide sides for references)
  75   Wide (12.5% sides)
  Custom…
  ```

- Computes the current rendered share (clients + monitors JSON, python3 for
  parsing — existing repo pattern, rounded to a whole percent) and puts it in
  the prompt: `fuzzel --dmenu --prompt 'master 62% '` (omit the percent if
  queries fail).
- `Custom…` → `zenity --entry` titled "Master width", entry-text = the
  current rendered percent, accepts `^[0-9]+(\.[0-9]+)?$`,
  clamped to 5–95.
- Applies `hyprctl dispatch "hl.dsp.layout('mfact exact 0.65')"`, then
  `noctalia msg notification-show 'Master width' '65% on gaming'`
  (toggle-layout notification pattern).
- Flags for testability: `--print` (dump menu rows, no UI),
  `--apply N` (apply N directly, no menu — also usable from future binds).

### 3. `dot_local/share/applications/hyprland-master-width.desktop` (new)

Name=Hyprland Master Width, Icon=preferences-system, Categories=Utility;
same pattern as `hyprland-switch-layout-menu.desktop`.

## Data flow

```
launch (Noctalia launcher → "Master Width")
  → hyprctl -j clients + monitors → current rendered share
  → fuzzel --dmenu --prompt 'master 62% ' (or --apply N)
  → Esc → exit 0
  → preset row → percent known
  → Custom… → zenity --entry → validated percent (invalid → error, exit 0)
  → hyprctl dispatch "hl.dsp.layout('mfact exact 0.P')"
  → failure (empty / all-floating ws) → notification, exit 0
  → success → notification '<P>% on <workspace name>'
```

## Error handling

- Dispatch failure (no windows / no master node on the workspace) →
  notification "No tiled window on this workspace", exit 0.
- Invalid custom input (non-numeric) → error notification, exit 0.
- Cancelled fuzzel/zenity → exit 0, nothing applied.
- clients/monitors query failure → menu still opens, prompt without the
  current percent.

## Testing

No test framework; verification via built-in modes and live queries:

1. `hyprland-master-width --print` — preset rows listed.
2. `hyprland-master-width --apply 65` with the gaming workspace focused →
   steam window's width ratio in `hyprctl -j clients` changes accordingly.
3. `--apply 65` on an empty workspace → failure-notification path.
4. Custom input: `abc` rejected, `62.5` accepted, `3`/`140` clamp to 5/95.
5. Manual: launcher finds "Master Width"; menu selection applies and
   notifies; SUPER+[/] still nudge afterwards.

## Risks / assumptions

- `hyprctl dispatch` with an `hl.dsp.*` expression works for `layout` exactly
  as it does for ws-rename's `workspace.rename` — same mechanism, high
  confidence; confirmed first thing during implementation.
- Rendered share in the prompt differs from mfact by gaps — expected and
  labeled; the success notification reports the mfact value that was applied.
- Preset list is intentionally minimal; extending it is a one-line edit.

## Out of scope

- Auto-apply on workspace activation (would require re-apply semantics per
  the root-cause findings; revisit only if manual setting feels lacking).
- Persisting custom widths across sessions or into hyprland.lua.
- Orientation or other master options in the menu.
