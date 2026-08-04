#!/usr/bin/env bash
#
# incrocio.sh — ogni comando invocato dai config arriva da un pacchetto in elenco?
#
#   ./prova/incrocio.sh
#
# Non serve una macchina Arch: e' pura analisi del testo, gira ovunque ci sia
# bash. Esce diverso da zero se qualcosa manca.
#
# PERCHE' ESISTE
# L'elenco dei pacchetti e i config vivono in due file diversi e non c'e' niente
# che li tenga allineati: si aggiunge una scorciatoia che chiama un programma
# nuovo, ci si dimentica di metterlo in pacchetti/base.txt, e il sintomo arriva
# mesi dopo su una macchina appena installata sotto forma di "quel tasto non fa
# niente". Questo controllo chiude il cerchio.
#
# La tabella qui sotto e' la parte da tenere aggiornata: dice da quale pacchetto
# arriva ogni comando. I comandi marcati "-" vengono dal sistema di base
# (coreutils, systemd, pacman) e non hanno bisogno di stare in elenco.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
cd "$REPO" || exit 1

declare -A DA=(
    # --- Hyprland e compagnia ---
    [hyprctl]=hyprland          [Hyprland]=hyprland
    [hyprpaper]=hyprpaper       [hyprlock]=hyprlock      [hypridle]=hypridle
    [hyprshot]=hyprshot         [hyprpicker]=hyprpicker

    # --- l'ambiente ---
    [waybar]=waybar             [fuzzel]=fuzzel
    [swaync]=swaync             [swaync-client]=swaync
    [matugen]=matugen           [alacritty]=alacritty    [satty]=satty
    [thunar]=thunar

    # --- utilita' ---
    [cliphist]=cliphist
    [wl-copy]=wl-clipboard      [wl-paste]=wl-clipboard
    [udiskie]=udiskie           [jq]=jq                  [python3]=python
    [notify-send]=libnotify     [xdg-open]=xdg-utils
    [xdg-user-dirs-update]=xdg-user-dirs

    # --- hardware ---
    [brightnessctl]=brightnessctl
    [playerctl]=playerctl       [wpctl]=wireplumber      [pavucontrol]=pavucontrol
    [nmcli]=networkmanager      [nm-connection-editor]=nm-connection-editor
    [bluetoothctl]=bluez-utils  [blueman-manager]=blueman
    [powerprofilesctl]=power-profiles-daemon
    [nwg-look]=nwg-look         [gsettings]=glib2

    # --- dal sistema di base: non vanno in elenco ---
    [systemctl]=-  [systemd-run]=-  [udevadm]=-  [loginctl]=-  [pacman]=-
    [pkill]=-      [pgrep]=-        [stdbuf]=-   [realpath]=-  [install]=-
    [lspci]=-      [lsmod]=-        [fc-list]=-  [chwd]=-
)

mapfile -t elenco < <(grep -vE '^[[:space:]]*(#|$)' pacchetti/base.txt | tr -d '[:blank:]')

in_elenco() {
    local p
    for p in "${elenco[@]}"; do [ "$p" = "$1" ] && return 0; done
    return 1
}

# Si cercano solo i nomi noti alla tabella: un grep aperto su qualunque parola
# darebbe centinaia di falsi positivi presi dai commenti italiani.
motivo="$(IFS='|'; echo "${!DA[*]}")"
mapfile -t usati < <(grep -rhoE "\\b(${motivo})\\b" config sistema prova 2>/dev/null | sort -u)

mancanti=0
for c in "${usati[@]}"; do
    pkg="${DA[$c]}"
    [ "$pkg" = "-" ] && continue
    if ! in_elenco "$pkg"; then
        printf '  MANCA  %-22s viene da "%s", che non e in pacchetti/base.txt\n' "$c" "$pkg"
        mancanti=$((mancanti + 1))
    fi
done

# Il controllo opposto: un pacchetto in elenco che nessuno usa non e' un errore
# (font, temi, librerie e demoni non compaiono come comandi), ma se un giorno
# l'elenco si gonfia questo dice da dove cominciare a guardare.
if [ "${1:-}" = "--verboso" ]; then
    echo "Comandi riconosciuti nei config: ${#usati[@]}"
    echo "Pacchetti in elenco: ${#elenco[@]}"
fi

if [ "$mancanti" -gt 0 ]; then
    echo
    echo "$mancanti comandi non sono coperti da pacchetti/base.txt." >&2
    exit 1
fi

echo "Tutti i comandi usati dai config sono coperti da pacchetti/base.txt."
