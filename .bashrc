# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# ble.sh: as-you-type suggestions + highlighting (attached at the end of this file)
[[ -r /usr/share/blesh/ble.sh ]] && source /usr/share/blesh/ble.sh --noattach

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Modern ls with headers and icons (via eza)
alias ls='eza -h --icons=auto --group-directories-first'
alias ll='eza -lh --icons=auto --group-directories-first'
alias la='eza -h -a --icons=auto --group-directories-first'
alias lla='eza -lh -a --icons=auto --group-directories-first'
umask 002

# Make an alias for invoking commands you use constantly
# alias p='python'
export PATH="$HOME/.config/composer/vendor/bin:$PATH"

. "$HOME/.local/share/../bin/env"
. "$HOME/.cargo/env"

# Anik terminal: did-you-mean hints, then switch on ble.sh
[[ -r ~/.config/bash/anik-terminal.bash ]] && source ~/.config/bash/anik-terminal.bash
[[ ! ${BLE_VERSION-} ]] || ble-attach

# Keep the prompt in place: Tab cycles candidates inline instead of printing
# the whole list (which pushes the prompt down), and pastes are inserted
# literally so tabs/newlines in them don't trigger completion or run.
if [[ $- == *i* ]]; then
  bind 'set show-all-if-ambiguous off'
  bind 'set show-all-if-unmodified off'
  bind 'set enable-bracketed-paste on'
fi
