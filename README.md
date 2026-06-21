# dotfiles

Portable, [chezmoi](https://www.chezmoi.io)-managed dotfiles. This first pass
manages **tmux** only — built on [Oh My TMUX](https://github.com/gpakosz/.tmux)
and [TPM](https://github.com/tmux-plugins/tpm), laid out cleanly under XDG
(no files in `$HOME`).

## What gets installed

| Target | What |
|--------|------|
| `~/.config/tmux/tmux.conf` | symlink → Oh My TMUX base (vendored as a git submodule) |
| `~/.config/tmux/tmux.conf.local` | local customizations (overrides; sourced last) |
| `~/.config/tmux/plugins/` | TPM + all plugins (XDG location, auto-detected by TPM) |
| `~/.config/tmux-sessionizer/tmux-sessionizer.conf` | search paths for the session picker |
| `~/.local/bin/tmux-sessionizer` | fuzzy project switcher (vendored script) |

The plugin install location is centralized in `tmux.conf.local` as `@plugin_dir`
and referenced via `#{@plugin_dir}` — change it in one place to move plugins.

## Prerequisites

### System packages

chezmoi manages **files**, not system packages — install these with your OS
package manager.

| Tool | Fedora | Ubuntu / Debian | macOS |
|------|--------|-----------------|-------|
| tmux | `sudo dnf install tmux` | `sudo apt install tmux` | `brew install tmux` |
| fzf | `sudo dnf install fzf` | `sudo apt install fzf` | `brew install fzf` |
| git | `sudo dnf install git` | `sudo apt install git` | `brew install git` |
| clipboard | `sudo dnf install wl-clipboard` † | `sudo apt install wl-clipboard` † | built-in (`pbcopy`) |
| chezmoi | see [chezmoi install](https://www.chezmoi.io/install/) | same | `brew install chezmoi` |

† `wl-clipboard` for Wayland sessions; use `xclip` on X11. `tmux-yank`
auto-detects the available tool, so this needs no config.

**macOS shortcut** — a `Brewfile` is included:

```sh
brew bundle install    # run from this repo, or: chezmoi cd && brew bundle install
```

### chezmoi

Install from <https://www.chezmoi.io/install/>.

## Install

### On this machine (repo already cloned here)

```sh
chezmoi init --source="$PWD"
chezmoi apply -v
```

Run `chezmoi init` from inside this repo, or substitute the absolute path.

### On a new machine (clone from a remote)

```sh
chezmoi init --apply <your-git-remote-url>
```

This clones the repo to chezmoi's source dir, applies everything, and runs the
one-shot TPM bootstrap (which clones TPM and installs all plugins).

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
│   └── tmux-sessionizer/
│       └── tmux-sessionizer.conf
├── dot_local/
│   └── bin/
│       └── executable_tmux-sessionizer      # +x via chezmoi prefix
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
- **`bind S` does nothing** — ensure `tmux-sessionizer` is on `$PATH`
  (`~/.local/bin` should be). Verify with `which tmux-sessionizer`.
- **Reload after editing `tmux.conf.local`** — `prefix + r`.
- **Config not loading at all** — confirm `~/.config/tmux/tmux.conf` is a valid
  symlink (`readlink ~/.config/tmux/tmux.conf`).

## Scope

This first iteration is **tmux-only**. zsh / nvim / git and friends can be
added under the same `dot_*` layout when ready.
