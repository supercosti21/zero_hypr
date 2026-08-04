#!/usr/bin/env bash
#
# tema-gtk.sh — applica il tema alle app GTK all'avvio di Hyprland.
#
# Serve perche' sotto un window manager non c'e' nessun settings-daemon a farlo:
# senza questo, GTK parte con Adwaita chiaro e le finestre sembrano fari accesi
# accanto a una barra scura.
#
# Viene eseguito solo dentro Hyprland: chi lancia un'altra sessione resta libero
# di gestire il proprio tema come preferisce.
#
# Per cambiare tema con un'interfaccia grafica:  nwg-look

set -euo pipefail

TEMA_GTK="adw-gtk3-dark"
TEMA_ICONE="Papirus-Dark"
TEMA_CURSORE="Adwaita"
DIM_CURSORE=24
FONT="Adwaita Sans 11"

# gsettings arriva con glib2, ma gli schemi org.gnome.desktop.* stanno in
# gsettings-desktop-schemas e i valori li persiste dconf. Se manca uno dei due,
# con `set -e` la prima riga qui sotto abortisce lo script a meta': niente tema,
# niente icone, niente cursore, niente font, e nessun messaggio. Meglio uscire
# subito dicendo perche'.
if ! command -v gsettings >/dev/null 2>&1; then
    echo "tema-gtk: gsettings non c'e' (manca glib2?), tema GTK non applicato" >&2
    exit 0
fi
if ! gsettings writable org.gnome.desktop.interface gtk-theme >/dev/null 2>&1; then
    echo "tema-gtk: schemi org.gnome.desktop.interface assenti — installa" \
         "gsettings-desktop-schemas e dconf. Tema GTK non applicato." >&2
    exit 0
fi

i="gsettings set org.gnome.desktop.interface"
$i gtk-theme      "$TEMA_GTK"
$i icon-theme     "$TEMA_ICONE"
$i cursor-theme   "$TEMA_CURSORE"
$i cursor-size    "$DIM_CURSORE"
$i font-name      "$FONT"
# Le app GTK4/libadwaita e Electron leggono questa: e' l'interruttore
# chiaro/scuro vero e proprio.
$i color-scheme   "prefer-dark"

# Comunica il cursore anche al compositore, per le zone senza finestre.
hyprctl setcursor "$TEMA_CURSORE" "$DIM_CURSORE" >/dev/null 2>&1 || true
