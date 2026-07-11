# dotfiles

Portable, [chezmoi](https://www.chezmoi.io)-managed dotfiles. Currently manages
**tmux**, **fish shell**, and **neovim** — built on [Oh My TMUX](https://github.com/gpakosz/.tmux),
[TPM](https://github.com/tmux-plugins/tpm), [catppuccin](https://github.com/catppuccin/tmux)
(mocha) theme, and [Fisher](https://github.com/jorgebucaran/fisher) plugins,
laid out cleanly under XDG (no files in `$HOME`).

## What gets installed

| Target | What |
|--------|------|
| `~/.config/tmux/tmux.conf` | symlink → Oh My TMUX base (vendored as a git submodule) |
| `~/.config/tmux/tmux.conf.local` | local customizations (overrides; sourced last) |
| `~/.config/tmux/plugins/` | TPM + all plugins (XDG location, auto-detected by TPM) |
| `~/.config/tmux-sessionizer/tmux-sessionizer.conf` | search paths for the session picker |
| `~/.local/bin/tmux-sessionizer` | fuzzy project switcher (vendored script) |
| `~/.config/fish/config.fish` | fish shell configuration |
| `~/.config/fish/fish_plugins` | Fisher plugin list |
| `~/.config/fish/conf.d/*.fish` | fish configuration snippets |
| `~/.config/fish/functions/*.fish` | custom fish functions |
| `~/.config/nvim/init.lua` | Neovim config (kickstart-inspired, single-file, `vim.pack`) |
| `~/.config/nvim/nvim-pack-lock.json` | pinned plugin versions (committed after first launch) |

The tmux plugin install location is centralized in `tmux.conf.local` as `@plugin_dir`
and referenced via `#{@plugin_dir}` — change it in one place to move plugins.

### Fish Shell

The fish configuration includes:

- **config.fish** - Main configuration with aliases, path setup, and fzf key bindings
- **fish_plugins** - Plugin list for [Fisher](https://github.com/jorgebucaran/fisher)
  - [nvm.fish](https://github.com/jorgebucaran/nvm.fish) - Node version manager
  - [tide](https://github.com/ilancosman/tide) - Modern, powerful prompt
- **conf.d/** - Additional configuration:
  - `rustup.fish` - Cargo/Rust environment
  - `uv.env.fish` - UV Python package manager environment
- **functions/** - Custom functions:
  - `pa.fish` - Quick Python virtual environment activation

Fisher and its plugins are installed automatically on `chezmoi apply` by
`run_once_bootstrap-fisher.sh`, which runs `fisher update` against
`fish_plugins`. To install manually (e.g. if the bootstrap was skipped because
fish wasn't installed yet, or it failed):

```bash
fish
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
fisher update
```

The tide prompt theme is applied automatically by the bootstrap (see the
`tide configure --auto` recipe in `run_once_bootstrap-fisher.sh`). To customize
it, run `tide configure` interactively and update that recipe to match.

### Neovim

The Neovim config is a single `init.lua`, written fresh but inspired by
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) (its current
`vim.pack` variant). Unlike tmux/fish it needs **no `run_once` bootstrap**:
plugins are managed by Neovim's built-in [`vim.pack`](https://neovim.io/doc/user/vim.pack.html),
and [Mason](https://github.com/mason-org/mason.nvim) auto-installs the LSPs and
formatters on first launch.

- **Languages**: Lua (lua-language-server + StyLua) and Python (basedpyright +
  ruff). Treesitter parsers install automatically.
- **Theme**: catppuccin (mocha), matching the kitty/tmux/wezterm setup.
- **File explorer**: [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) (`<leader>e`
  toggles the sidebar; `nvim .` opens it via netrw hijack).
- **Plugin manager**: `vim.pack` (built-in, requires Neovim ≥0.12). Plugin
  versions are pinned in `~/.config/nvim/nvim-pack-lock.json`, committed after
  the first launch for reproducibility.

Key bindings (leader is `<space>`):

| Key | Action |
|-----|--------|
| `<leader>sf` | Find files (Telescope) |
| `<leader>sg` | Live grep |
| `<leader>sh` | Search help |
| `<leader>e` | Toggle file explorer (neo-tree) |
| `<leader>f` | Format buffer |
| `grd` / `grr` | Go to definition / references |
| `<leader>th` | Toggle inlay hints |

## Prerequisites

### System packages

chezmoi manages **files**, not system packages — install these with your OS
package manager.

| Tool | Fedora | Ubuntu / Debian | macOS |
|------|--------|-----------------|-------|
| tmux | `sudo dnf install tmux` | `sudo apt install tmux` | `brew install tmux` |
| fzf | `sudo dnf install fzf` | `sudo apt install fzf` | `brew install fzf` |
| git | `sudo dnf install git` | `sudo apt install git` | `brew install git` |
| fish | `sudo dnf install fish` | `sudo apt install fish` | `brew install fish` |
| ripgrep | `sudo dnf install ripgrep` | `sudo apt install ripgrep` | `brew install ripgrep` |
| bat | `sudo dnf install bat` | `sudo apt install bat` | `brew install bat` |
| fd | `sudo dnf install fd-find` | `sudo apt install fd-find` | `brew install fd` |
| clipboard | `sudo dnf install wl-clipboard` † | `sudo apt install wl-clipboard` † | built-in (`pbcopy`) |
| git-delta | `cargo install git-delta` ‡ | `cargo install git-delta` ‡ | `brew install git-delta` |
| eza | `cargo install eza` ‡ | `cargo install eza` ‡ | `brew install eza` |
| zoxide | `cargo install zoxide` ‡ | `cargo install zoxide` ‡ | `brew install zoxide` |
| lazygit | `cargo install lazygit` ‡ | `cargo install lazygit` ‡ | `brew install lazygit` |
| neovim (≥0.12) †† | `sudo dnf install neovim` | PPA / release tarball (see ††) | `brew install neovim` |
| make | `sudo dnf install make` | `sudo apt install make` | Xcode CLT |
| unzip | `sudo dnf install unzip` | `sudo apt install unzip` | Xcode CLT |
| gcc (C compiler) | `sudo dnf install gcc` | `sudo apt install build-essential` | Xcode CLT |
| tree-sitter | `sudo dnf install tree-sitter` | `sudo apt install tree-sitter-cli` | `brew install tree-sitter` |
| chezmoi | see [chezmoi install](https://www.chezmoi.io/install/) | same | `brew install chezmoi` |

† `wl-clipboard` for Wayland sessions; use `xclip` on X11. `tmux-yank` auto-detects the available tool, so this needs no config.

‡ Install with `cargo` after `sudo dnf/apt install cargo`. On Fedora, some of these (git-delta, eza, zoxide, lazygit) are also available via `dnf`, but `cargo` ensures the latest versions.

†† The Neovim config uses `vim.pack` and the `vim.lsp.config` / `vim.lsp.enable` API, which require Neovim ≥0.12. Fedora's `dnf install neovim` is recent enough. On Ubuntu/Debian the stock package is usually too old — install via the [neovim PPA](https://launchpad.net/~neovim-ppa/+archive/ubuntu/unstable) or the [release tarball/appimage](https://github.com/neovim/neovim/releases). `make`, `unzip`, and the C compiler come from `build-essential` (Debian/Ubuntu) or `@development-tools` (Fedora); on macOS they're provided by the Xcode Command Line Tools.

† `wl-clipboard` for Wayland sessions; use `xclip` on X11. `tmux-yank`
auto-detects the available tool, so this needs no config.

**macOS shortcut** — a `Brewfile` is included:

```sh
brew bundle install    # run from this repo, or: chezmoi cd && brew bundle install
```

### chezmoi

Install from <https://www.chezmoi.io/install/>.

### Terminal font (required for the catppuccin icons)

The catppuccin theme uses Nerd Font glyphs for its status line icons and
window separators. Without one installed, those render as tofu boxes (□).

This repo standardizes on **JetBrains Mono Nerd Font**. chezmoi deliberately
does not manage fonts (see *Why chezmoi doesn't install system packages* —
fonts are no exception despite being files, because per-OS install paths and
update churn make it a poor fit). Install with your OS's mechanism:

**Linux (manual, any distro):**

```sh
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip JetBrainsMono.zip && rm JetBrainsMono.zip
fc-cache -fv
fc-list | grep -i 'JetBrains.*Nerd'   # verify
```

**macOS (Homebrew):**

```sh
brew install --cask font-jetbrains-mono-nerd-font
```

After installing, **set your terminal emulator's font to "JetBrainsMono Nerd Font"**.
No tmux reload is needed once the terminal picks up the new font.

## Install

```sh
chezmoi init --apply --verbose <your-git-remote-url>
```

This single command:
- Clones your repo to `~/.local/share/chezmoi` (chezmoi's source directory)
- Fetches git submodules (including Oh My TMUX)
- Applies all dotfiles to your home directory (Neovim plugins/LSPs install on first `nvim` launch)

`chezmoi apply` runs one-shot bootstraps: TPM (clones TPM and installs all tmux
plugins into the XDG plugin directory) and Fisher (installs Fisher and
reconciles the fish plugins in `fish_plugins`).

### Inspecting the repo without chezmoi

```sh
git clone --recursive <your-git-remote-url>
```

Then either link the files manually (see *What gets installed* for the targets)
or, from inside the clone: `chezmoi init --source="$PWD" && chezmoi apply`.

## Architecture

```
dotfiles/                                    # chezmoi source dir
├── README.md
├── Brewfile                                 # macOS deps
├── .gitmodules                              # pins Oh My TMUX
├── submodules/
│   └── oh-my-tmux/                          # gpakosz/.tmux (pinned)
├── dot_config/
│   ├── tmux/
│   │   ├── symlink_tmux.conf.tmpl           # → symlink whose target is the
│   │   │                                    #   submodule's .tmux.conf, resolved
│   │   │                                    #   via {{ .chezmoi.sourceDir }}
│   │   └── tmux.conf.local                  # customizations
│   ├── tmux-sessionizer/
│   │   └── tmux-sessionizer.conf
│   ├── fish/
│   │   ├── config.fish                      # main fish configuration
│   │   ├── fish_plugins                     # Fisher plugin list
│   │   ├── conf.d/
│   │   │   ├── rustup.fish
│   │   │   └── uv.env.fish
│   │   └── functions/
│   │       └── pa.fish                      # custom python activate alias
│   └── nvim/
│       └── init.lua                         # kickstart-inspired single-file config (vim.pack)
├── dot_local/
│   └── bin/
│       └── executable_tmux-sessionizer      # +x via chezmoi prefix
├── run_once_bootstrap-fisher.sh             # Fisher + plugins + tide theme
└── run_once_bootstrap-tmux-plugins.sh       # clones TPM + installs plugins
```

**Why it's portable:** the only machine-specific path is resolved at `apply`
time via chezmoi's `.chezmoi.sourceDir` (for the symlink target). Everything
else uses `$HOME`-relative or XDG paths, and clipboard handling is
auto-detected by `tmux-yank`. There are no hardcoded absolute paths and no
templates needed yet — the config is static on purpose.

### How Oh My TMUX is wired

Oh My TMUX [supports XDG natively](https://github.com/gpakosz/.tmux#faq): when
its base config lives at `~/.config/tmux/tmux.conf`, it resolves
`TMUX_CONF_LOCAL` to `~/.config/tmux/tmux.conf.local` and sources it
automatically. TPM in turn auto-detects the XDG plugin dir because the base
config exists under `~/.config/tmux/`.

## Key bindings (from `tmux.conf.local`)

| Key | Action |
|-----|--------|
| `prefix + r` | Reload config |
| `prefix + C-s` | Save session (tmux-resurrect) |
| `prefix + C-r` | Restore session (tmux-resurrect) |
| `prefix + S` | tmux-sessionizer (fuzzy project switch) |

Plus all of Oh My TMUX's defaults and the bound keys from each TPM plugin
(`prefix + I` to install plugins, `prefix + Space` for which-key, etc.).

## Updating

```sh
# Pull chezmoi source + submodule updates, then re-apply
chezmoi update          # if sourced from a remote
# or, for a local repo:
git -C "$(chezmoi source-path)" pull --ff-only
git -C "$(chezmoi source-path)" submodule update --remote --merge tmux 2>/dev/null || \
  git -C "$(chezmoi source-path)" submodule update --init --recursive
chezmoi apply -v

# Update TPM plugins (inside tmux)
#   prefix + U
```

## Troubleshooting

- **Plugins didn't install on `chezmoi apply`** — the bootstrap runs a
  headless tmux session to trigger TPM. If anything went wrong, just open tmux
  and press `prefix + I`.
- **Fish plugins didn't install on `chezmoi apply`** — the Fisher bootstrap
  installs Fisher and runs `fisher update` against `fish_plugins`. If it was
  skipped (fish not on `$PATH` yet) or failed, open fish and run `fisher update`.
- **`bind S` does nothing** — ensure `tmux-sessionizer` is on `$PATH`
  (`~/.local/bin` should be). Verify with `which tmux-sessionizer`.
- **Reload after editing `tmux.conf.local`** — `prefix + r`.
- **Tofu boxes (□) in the status line** — you're missing a Nerd Font. Install
  JetBrains Mono Nerd Font (see *Prerequisites → Terminal font*) and set your
  terminal's font to it.
- **Config not loading at all** — confirm `~/.config/tmux/tmux.conf` is a valid
  symlink (`readlink ~/.config/tmux/tmux.conf`) and that the target file exists.
  A missing target means the `submodules/oh-my-tmux/` submodule wasn't
  initialized — fix with `git -C "$(chezmoi source-path)" submodule update --init --recursive`.
- **nvim plugins/LSPs didn't install on first launch** — `vim.pack` (plugins) and
  Mason (LSPs/formatters) run on first launch. If something didn't, open nvim and
  run `:lua vim.pack.update()` (plugins) or `:Mason` (tools), then `:checkhealth`.
- **nvim errors about `vim.pack` or `vim.lsp.config`** — these require Neovim
  ≥0.12. Check `nvim --version`; on Ubuntu/Debian the stock package is usually too
  old (install via the neovim PPA or the release tarball/appimage).

## Scope

Currently manages **tmux**, **fish shell**, and **neovim**. git / other shells
can be added under the same `dot_*` layout when ready.
