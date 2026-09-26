#!/bin/sh
# Installs the "Island" SDDM theme and makes it the active one.
# Run with: sudo sh ~/.config/quickshell/sddm/install.sh
# Undo:     sudo rm /etc/sddm.conf.d/10-island-theme.conf   (falls back to the default theme)
set -e
SRC="$(dirname "$(readlink -f "$0")")/island"
install -d /usr/share/sddm/themes
rm -rf /usr/share/sddm/themes/island
cp -r "$SRC" /usr/share/sddm/themes/island
chmod -R a+rX /usr/share/sddm/themes/island
install -d /etc/sddm.conf.d
printf '[Theme]\nCurrent=island\n' > /etc/sddm.conf.d/10-island-theme.conf
echo "Installed. Preview (safe, in a window): sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/island"
