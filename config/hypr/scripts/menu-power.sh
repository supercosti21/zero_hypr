#!/usr/bin/env bash
#
# menu-power.sh — menu di spegnimento minimale via fuzzel.
# Richiamato dal pulsante 󰐥 in waybar e da SUPER+SHIFT+Q.

set -euo pipefail

scelta=$(printf '%s\n' \
    "  Blocca" \
    "󰤄  Sospendi" \
    "  Riavvia" \
    "󰐥  Spegni" \
    "󰗽  Esci dalla sessione" \
    | fuzzel --dmenu --prompt='  ' --lines=5 --width=26)

case "$scelta" in
    *Blocca*)   hyprlock ;;
    *Sospendi*) systemctl suspend ;;
    *Riavvia*)  systemctl reboot ;;
    *Spegni*)   systemctl poweroff ;;
    *Esci*)     hyprctl dispatch exit ;;
esac
