# GPG needs the current TTY for passphrase prompts
set -gx GPG_TTY (tty)
