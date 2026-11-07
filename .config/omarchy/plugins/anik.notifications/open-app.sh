#!/bin/bash
# Bring a notification's sender to the front: focus its window if one is open,
# otherwise launch it from its desktop entry. Used by popups and the bell panel.
#   open-app.sh <app-name> [desktop-entry]
app=${1:-}
entry=${2:-}
entry=${entry%.desktop}

for pattern in "$app" "$entry"; do
  [[ -n $pattern ]] && omarchy-hyprland-focus-app "$pattern" && exit 0
done

# Nothing open: launch it. Try the desktop entry the sender named, then a
# desktop file matching the app name (case-insensitive).
for candidate in "$entry" "$app"; do
  [[ -n $candidate ]] || continue
  if gtk-launch "$candidate" >/dev/null 2>&1 & sleep 0.3; kill -0 $! 2>/dev/null || wait $!; then
    exit 0
  fi
  file=$(find /usr/share/applications ~/.local/share/applications -maxdepth 1 -iname "*${candidate}*.desktop" 2>/dev/null | head -1)
  if [[ -n $file ]]; then
    setsid uwsm-app -- "$(basename "$file")" >/dev/null 2>&1 &
    exit 0
  fi
done
exit 1
