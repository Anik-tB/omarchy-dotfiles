# Anik terminal extras, sourced from ~/.bashrc.
#
# 1. "Did you mean …?" when a command isn't found: the closest installed
#    commands by edit distance, plus the package that provides it when the
#    pacman file database is available (`sudo pacman -Fy` once to enable).
# 2. ble.sh (if installed): fish-style suggestions from history as you type,
#    and live highlighting — valid commands violet/blue, unknown ones red.
#    Its colours live in ~/.blerc.

command_not_found_handle() {
  local cmd=$1
  printf '\e[1;38;2;211;95;95m✗ %s\e[0m\e[38;2;200;220;220m: command not found\e[0m\n' "$cmd" >&2

  local matches
  matches=$(compgen -c | sort -u | awk -v w="$cmd" '
    # optimal string alignment distance: a swapped pair of letters counts as one typo
    function lev(a, b,   la, lb, i, j, c, d, t) {
      la = length(a); lb = length(b)
      delete t
      for (i = 0; i <= la; i++) t[i, 0] = i
      for (j = 0; j <= lb; j++) t[0, j] = j
      for (i = 1; i <= la; i++) {
        for (j = 1; j <= lb; j++) {
          c = (substr(a, i, 1) == substr(b, j, 1)) ? 0 : 1
          d = t[i - 1, j] + 1
          if (t[i, j - 1] + 1 < d) d = t[i, j - 1] + 1
          if (t[i - 1, j - 1] + c < d) d = t[i - 1, j - 1] + c
          if (i > 1 && j > 1 && substr(a, i, 1) == substr(b, j - 1, 1) && substr(a, i - 1, 1) == substr(b, j, 1) && t[i - 2, j - 2] + 1 < d)
            d = t[i - 2, j - 2] + 1
          t[i, j] = d
        }
      }
      return t[la, lb]
    }
    length($0) > 1 && (length($0) - length(w))^2 <= 4 {
      d = lev(w, $0)
      max = length(w) <= 4 ? 1 : 2
      if (d <= max) print d "\t" $0
    }' | sort -n | head -3 | cut -f2)

  if [[ -n $matches ]]; then
    printf '\e[38;2;169;209;215m  did you mean:\e[0m' >&2
    printf ' \e[1;38;2;173;240;233m%s\e[0m' $matches >&2
    printf '\n' >&2
  fi

  local pkg
  if compgen -G '/var/lib/pacman/sync/*.files' >/dev/null; then
    pkg=$(pacman -F -q "/usr/bin/$cmd" 2>/dev/null | head -1)
    [[ -n $pkg ]] && printf '\e[38;2;169;209;215m  install it with:\e[0m \e[1;38;2;173;240;233momarchy pkg add %s\e[0m\n' "${pkg##*/}" >&2
  fi

  return 127
}

# 3. fzf in the Anik palette (Ctrl+R history, Ctrl+T files, Alt+C dirs, `ff`):
#    rounded border, prompt on top, preview pane toggles with Ctrl+/.
export FZF_DEFAULT_OPTS="\
--height=60% --layout=reverse --border=rounded --margin=0,1 --info=inline-right \
--prompt='❯ ' --pointer='▌' --marker='┃' --separator='─' --scrollbar='│' \
--bind='ctrl-/:toggle-preview' \
--color=bg+:#241f36,bg:-1,fg:#c5bfe2,fg+:#e6e2f7,hl:#c29af0,hl+:#c29af0 \
--color=border:#2e2842,label:#a08ae6,prompt:#a08ae6,pointer:#a08ae6,marker:#c29af0 \
--color=info:#6e6893,spinner:#e2d8fb,header:#c9b8f2,query:#e6e2f7:bold,gutter:-1"
command -v fd &>/dev/null && {
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
}
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range=:300 {} 2>/dev/null || eza -la --icons --color=always {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons --color=always {}'"

# 4. Colour + reading: bat follows the terminal palette, man pages get syntax
#    colour through bat.
export BAT_THEME=ansi
command -v bat &>/dev/null && {
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT="-c"
}

# 5. Productivity helpers (names chosen not to clash with Omarchy's aliases).
#    mkcd DIR       make a directory and enter it
#    extract FILE   unpack any common archive
#    rgf PATTERN    search file contents, preview matches, open the pick at its line
#    fbr            switch git branch with a log preview
#    fkill          pick processes to kill (Tab marks several)
#    ports          what is listening on which port
#    cheat CMD      short practical examples (tldr)
mkcd() { mkdir -p -- "$1" && builtin cd -- "$1"; }

extract() {
  [[ -f $1 ]] || { echo "extract: '$1' is not a file" >&2; return 1; }
  case $1 in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz)   tar xzf "$1" ;;
    *.tar.xz|*.txz)   tar xJf "$1" ;;
    *.tar.zst)        tar --zstd -xf "$1" ;;
    *.tar)            tar xf "$1" ;;
    *.bz2)            bunzip2 "$1" ;;
    *.gz)             gunzip "$1" ;;
    *.xz)             unxz "$1" ;;
    *.zst)            unzstd "$1" ;;
    *.zip)            unzip "$1" ;;
    *.7z)             7z x "$1" ;;
    *.rar)            unrar x "$1" ;;
    *) echo "extract: don't know how to unpack '$1'" >&2; return 1 ;;
  esac
}

rgf() {
  local pick
  pick=$(rg --line-number --no-heading --color=always --smart-case "${@:-.}" |
    fzf --ansi --delimiter : --prompt='rg ❯ ' \
        --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
        --preview-window 'right,60%,+{2}+3/3') || return
  local file line
  IFS=: read -r file line _ <<<"$pick"
  "${EDITOR:-nvim}" "+$line" "$file"
}

fbr() {
  local branch
  branch=$(git branch --all --sort=-committerdate --format='%(refname:short)' 2>/dev/null |
    grep -v HEAD | fzf --prompt='branch ❯ ' \
      --preview 'git log --oneline --graph --color=always -20 {}') || return
  git switch "${branch#origin/}" 2>/dev/null || git switch --track "$branch"
}

fkill() {
  local pids
  pids=$(ps -u "$USER" -o pid=,%cpu=,%mem=,comm= --sort=-%cpu |
    fzf --multi --prompt='kill ❯ ' --header='Tab: mark several · Enter: kill' | awk '{print $1}') || return
  [[ -n $pids ]] && kill $pids && echo "killed: $pids"
}

ports() { ss -tulpn 2>/dev/null; }

cheat() { tldr "$@"; }
