if status is-interactive
    # fzf key bindings: Ctrl-R (history), Ctrl-T (file find), Alt-C (cd)
    command -q fzf; and fzf --fish | source

    # zoxide (smart cd)
    command -q zoxide; and zoxide init fish --cmd cd | source

    # bat (cat with syntax highlighting, no pager)
    if command -q bat
        alias cat='bat --paging=never'
    end

    # eza (modern ls)
    if command -q eza
        alias ls='eza'
        alias ll='eza -l'
        alias la='eza -la'
        alias lt='eza --tree'
    end

    # docker completions (fall back to podman — see docker alias below)
    if command -q docker
        docker completion fish | source
    else if command -q podman
        podman completion fish | source
    end

    # uv / uvx completions
    command -q uv; and uv generate-shell-completion fish | source
    command -q uvx; and uvx --generate-shell-completion fish | source
end

# pi - coding agent alias
alias pi='npx @earendil-works/pi-coding-agent'

# zellij
alias zl='zellij'

# tmux
alias tm='tmux'
alias tma='tmux attach'
alias tml='tmux list-sessions'
alias ts='tmux-sessionizer'

# claude
alias csp='claude --dangerously-skip-permissions'

# opencode
alias osp='opencode --dangerously-skip-permissions'

# docker: alias to podman only when podman is installed AND docker is not
if not command -q docker; and command -q podman
    alias docker='podman'
end
