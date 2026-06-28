local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Catppuccin Mocha — built-in color scheme, matches fish + tmux
config.color_scheme = 'Catppuccin Mocha'

-- JetBrainsMono Nerd Font — required for catppuccin/tmux status-line icons
config.font = wezterm.font('JetBrainsMono Nerd Font')

return config
