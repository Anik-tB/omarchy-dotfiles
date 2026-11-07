#!/bin/bash
# GTK/libadwaita accent (selections, toggles in Nautilus etc.): purple for Anik's morpho violet, GNOME's blue otherwise.
if [[ $1 == "anik" ]]; then
  gsettings set org.gnome.desktop.interface accent-color purple
else
  gsettings set org.gnome.desktop.interface accent-color blue
fi
