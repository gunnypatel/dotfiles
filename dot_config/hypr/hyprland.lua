-- Hyprland config: 57" ultrawide + Noctalia shell.
-- Lua API: https://wiki.hypr.land/Configuring/Start/

------------------
-- MONITORS
------------------

-- Samsung Odyssey G95NC 57" 7680x2160@120 (verify names: `hyprctl monitors`)
hl.monitor({
    output   = "DP-5",
    mode     = "7680x2160@120",
    position = "0x0",
    scale    = 1.25,
})

------------------
-- PROGRAMS
------------------

local terminal    = "ghostty"
local fileManager = "dolphin"
local ipc         = "noctalia msg "

------------------
-- AUTOSTART
------------------

-- Noctalia provides bar, launcher, notifications, OSDs, lock screen and idle
-- handling. It also runs the polkit agent (enabled in noctalia/config.toml).
hl.on("hyprland.start", function()
    hl.exec_cmd("noctalia")
end)

--------------------------
-- ENVIRONMENT
--------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Chrome/Electron as native Wayland clients: crisp at scale 1.25, no XWayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

------------------
-- LOOK & LAYOUT
------------------

-- Centered master: the active window sits mid-screen (~42% width, like a
-- comfortable 27" window), reference/background windows tile to both sides.
-- Nothing ever spans the full 32:9 except an explicit fullscreen.
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,
        layout   = "master",
    },
    master = {
        orientation = "center",
        mfact       = 0.42,
        -- center the master even with 0-1 side windows (default needs 2
        -- slaves and otherwise falls back to a left split)
        slave_count_for_center_master = 0,
    },
    decoration = {
        rounding       = 20,
        rounding_power = 2,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled  = true,
            size     = 3,
            passes   = 2,
            vibrancy = 0.1696,
        },
    },
})

------------------
-- ANIMATIONS
------------------

-- Workspace switches cross-fade linearly over 1s: constant-opacity fade so
-- the transition stays predictable (no ease-in/out).
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 4, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 4, bezier = "linear", style = "fade" })

------------------
-- KEYBINDINGS
------------------

local mainMod = "SUPER"

-- Launch
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + SPACE",  hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"))

-- Window ops (SUPER+W mirrors Ctrl+W: apps close a tab, or the window)
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + C", hl.dsp.window.center())               -- center a floating window
hl.bind(mainMod .. " + M", hl.dsp.layout("swapwithmaster"))      -- promote focused window to center

-- Focus / move, vim-style (matches Ctrl+hjkl window nav in nvim)
for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
    hl.bind(mainMod .. " + " .. key:upper(),         hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. key:upper(), hl.dsp.window.move({ direction = dir }))
end

-- Workspaces 1-9; SUPER+SHIFT+N moves the window there
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad: drop-down layer over the current workspace
hl.bind(mainMod .. " + D",         hl.dsp.workspace.toggle_special("scratchpad"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.window.move({ workspace = "special:scratchpad" }))

-- Mouse: SUPER+LMB move, SUPER+RMB resize, SUPER+scroll cycle workspaces
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Noctalia shell surfaces and session
hl.bind("ALT + TAB",               hl.dsp.exec_cmd(ipc .. "window-switcher"))
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"))
hl.bind(mainMod .. " + COMMA",     hl.dsp.exec_cmd(ipc .. "settings-toggle"))
hl.bind(mainMod .. " + ESCAPE",    hl.dsp.exec_cmd(ipc .. "session lock"))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(ipc .. "panel-toggle session"))
hl.bind("PRINT",                   hl.dsp.exec_cmd(ipc .. "screenshot-region"))

-- Reload (no Lua reload dispatcher yet; hyprctl works from any bind)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

-- Hardware/media keys -> Noctalia OSDs
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(ipc .. "volume-up"),     { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(ipc .. "volume-down"),   { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(ipc .. "volume-mute"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(ipc .. "brightness-up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"), { locked = true, repeating = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd(ipc .. "media next"),    { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd(ipc .. "media previous"), { locked = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd(ipc .. "media toggle"),  { locked = true })
hl.bind("XF86AudioPause",        hl.dsp.exec_cmd(ipc .. "media toggle"),  { locked = true })

------------------
-- RULES
------------------

-- Blur behind Noctalia surfaces; it animates itself, so no layer animations
hl.layer_rule({
    name  = "noctalia-blur",
    match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
    no_anim      = true,
    ignore_alpha = 0.5,
    blur         = true,
    blur_popups  = true,
})

-- Noctalia settings window
hl.window_rule({
    name  = "noctalia-settings",
    match = { class = "dev.noctalia.Noctalia" },
    float = true,
    size  = { 1080, 920 },
})

-- Apps requesting maximize get suppressed: keep windows off the full 32:9
hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})
