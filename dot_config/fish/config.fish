if status is-interactive
    # fzf key bindings: Ctrl-R (history), Ctrl-T (file find), Alt-C (cd)
    command -q fzf; and fzf --fish | source

    # zoxide (smart cd)
    command -q zoxide; and zoxide init fish | source

    # docker completions
    command -q docker; and docker completion fish | source

    # bun completions
    command -q bun; and bun completions | source

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
