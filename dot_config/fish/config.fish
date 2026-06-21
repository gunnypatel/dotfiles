if status is-interactive
    # Commands to run in interactive sessions can go here

    # fzf key bindings: Ctrl-R (history), Ctrl-T (file find), Alt-C (cd)
    fzf --fish | source
end


# opencode
fish_add_path /home/gunny/.opencode/bin
set PATH $HOME/.jenv/bin $PATH

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

# if status is-interactive && not set -q ZELLIJ
#     zellij
# end
