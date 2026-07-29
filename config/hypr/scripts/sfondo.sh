#!/usr/bin/env bash
#
# sfondo.sh — selettore di sfondo: applica subito E rende permanente.
# Legato a SUPER+W.
#
# Uso:
#   sfondo.sh                       selettore fuzzel sulle immagini della cartella
#   sfondo.sh ~/foto/altro.jpg      imposta direttamente quel file
#   sfondo.sh --caso                una a caso dalla cartella
#
# Perche' esiste: hyprpaper fa una cosa sola per volta. `hyprctl hyprpaper
# wallpaper` cambia lo sfondo adesso ma si dimentica tutto al riavvio; scrivere
# in hyprpaper.conf sopravvive al riavvio ma non si vede subito. Lo script fa
# entrambe le cose, cosi' non ci si ritrova con lo sfondo giusto a schermo e
# quello vecchio al login.

set -euo pipefail

CARTELLA="${SFONDI_DIR:-$HOME/Git/wallpapers}"
CONF="$HOME/.config/hypr/hyprpaper.conf"

avvisa() {
    command -v notify-send >/dev/null && notify-send -a sfondo "Sfondo" "$1" \
        || echo "$1" >&2
}

################################################################################
#  1. Elenco delle immagini disponibili
################################################################################
# -print0 / -d '' per non inciampare sui nomi con spazi.
# .git escluso: la cartella e' un repo, non serve pescare dentro gli oggetti.
elenca() {
    find -L "$CARTELLA" -type d -name .git -prune -o -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.webp' -o -iname '*.bmp' \) -print0 2>/dev/null | sort -z
}

################################################################################
#  2. Quale immagine
################################################################################
img="${1:-}"

if [ -z "$img" ] || [ "$img" = "--caso" ]; then
    mapfile -d '' -t trovate < <(elenca)

    if [ "${#trovate[@]}" -eq 0 ]; then
        avvisa "Nessuna immagine in $CARTELLA"
        exit 1
    fi

    if [ "$img" = "--caso" ]; then
        img="${trovate[RANDOM % ${#trovate[@]}]}"
    else
        # Nel menu si mostra solo il nome del file: con path assoluti sarebbe
        # illeggibile. Poi si rimappa al percorso pieno.
        scelta=$(
            for f in "${trovate[@]}"; do basename "$f"; done \
            | fuzzel --dmenu --prompt='sfondo> ' --lines=12 --width=44
        ) || exit 0                      # Esc sul menu: non fare nulla
        [ -n "$scelta" ] || exit 0

        img=""
        for f in "${trovate[@]}"; do
            [ "$(basename "$f")" = "$scelta" ] && { img="$f"; break; }
        done
        [ -n "$img" ] || { avvisa "Scelta non riconosciuta: $scelta"; exit 1; }
    fi
fi

# Path assoluto: hyprpaper non risolve ne' ~ ne' i percorsi relativi.
img=$(realpath -e -- "$img" 2>/dev/null) || {
    avvisa "File inesistente: ${1:-}"
    exit 1
}

################################################################################
#  3. Applica adesso, su ogni monitor collegato
################################################################################
# Via IPC il monitor va nominato: la forma ",percorso" (= tutti) funziona nel
# file di config ma viene ignorata in silenzio dal comando IPC.
while read -r mon; do
    [ -n "$mon" ] || continue
    hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null
done < <(hyprctl monitors -j | jq -r '.[].name')

################################################################################
#  4. Rendi permanente: riscrive la riga `path` dentro il blocco wallpaper
################################################################################
# Si tocca solo quella riga: commenti e resto del file restano intatti.
# Il percorso arriva come argomento, non interpolato: nomi con spazi o apici
# non rompono niente.
python3 - "$CONF" "$img" <<'PY'
import sys, pathlib, re

conf, img = pathlib.Path(sys.argv[1]), sys.argv[2]
testo = conf.read_text()

# Sostituisce il primo "path = ..." conservando l'indentazione originale.
nuovo, n = re.subn(
    r'^([ \t]*)path\s*=.*$',
    lambda m: f"{m.group(1)}path = {img}",
    testo,
    count=1,
    flags=re.MULTILINE,
)

if n == 0:
    sys.exit(f"nessuna riga 'path =' trovata in {conf}: il file e' stato "
             f"modificato a mano? Lo sfondo e' comunque applicato adesso.")

conf.write_text(nuovo)
PY

################################################################################
#  5. Rigenera la palette dallo sfondo e ricarica chi la usa
################################################################################
# --prefer saturation NON e' opzionale: quando da un'immagine si possono
# estrarre piu' colori sorgente, matugen normalmente chiede all'utente quale
# usare. Lanciato da una scorciatoia non c'e' nessun terminale a cui chiedere e
# fallisce con "a terminal was not detected". Con --prefer sceglie da se'.
# "saturation" = il piu' saturo fra i candidati: da' accenti vivi invece di
# grigi slavati.
if command -v matugen >/dev/null; then
    if matugen --quiet --prefer saturation image "$img" 2>/dev/null; then

        # Ognuno si ricarica a modo suo. Nessuno di questi riavvia il
        # programma: sono ricariche a caldo, non si perde nulla.
        #   waybar     -> SIGUSR2 rilegge config e CSS
        #   hyprland   -> reload rilegge, e con esso il `source` dei colori
        #   swaync     -> -rs = reload style
        #   fuzzel     -> niente: legge la config ad ogni apertura
        #   alacritty  -> niente: rilegge da se' quando il file cambia
        pkill -x -SIGUSR2 waybar 2>/dev/null || true
        hyprctl reload >/dev/null 2>&1 || true
        command -v swaync-client >/dev/null && swaync-client -rs >/dev/null 2>&1 || true
    else
        avvisa "Sfondo cambiato, ma la palette non e' stata rigenerata"
    fi
fi

avvisa "$(basename "$img")"
