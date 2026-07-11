# General PATH entries
test -d $HOME/.local/bin; and fish_add_path $HOME/.local/bin
test -d $HOME/bin; and fish_add_path $HOME/bin
test -d /usr/local/opt/libpq/bin; and fish_add_path /usr/local/opt/libpq/bin

# Neovim (official release tarball extracted to /opt)
test -d /opt/nvim-linux-x86_64/bin; and fish_add_path /opt/nvim-linux-x86_64/bin

# Bun
set -gx BUN_INSTALL "$HOME/.bun"
test -d $BUN_INSTALL/bin; and fish_add_path $BUN_INSTALL/bin

# Go
command -q go; and fish_add_path (go env GOPATH)/bin

# Volta (Node version manager)
set -gx VOLTA_HOME "$HOME/.volta"
test -d $VOLTA_HOME/bin; and fish_add_path $VOLTA_HOME/bin

# opencode
test -d $HOME/.opencode/bin; and fish_add_path $HOME/.opencode/bin

# jenv
test -d $HOME/.jenv/bin; and fish_add_path $HOME/.jenv/bin
