#!/usr/bin/env bash
#
# sfondo.sh — selettore di sfondo: applica subito E rende permanente.
# Legato a SUPER+W.
#
# Uso:
#   sfondo.sh                       selettore fuzzel sulle immagini disponibili
#   sfondo.sh ~/foto/altro.jpg      imposta direttamente quel file
#   sfondo.sh --caso                una a caso
#   sfondo.sh --primo               solo se non ce n'e' gia' uno, e senza menu
#
# Perche' esiste: hyprpaper fa una cosa sola per volta. `hyprctl hyprpaper
# wallpaper` cambia lo sfondo adesso ma si dimentica tutto al riavvio; scrivere
# in hyprpaper.conf sopravvive al riavvio ma non si vede subito. Lo script fa
# entrambe le cose, cosi' non ci si ritrova con lo sfondo giusto a schermo e
# quello vecchio al login.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Dove cercare le immagini, in ordine. La prima e' la collezione personale, che
# vive in un repo a parte e su una macchina appena installata non esiste; la
# seconda e' lo sfondo di riserva dentro questo repo, che c'e' sempre.
#
# Senza la seconda, il primo avvio era: hyprpaper mostra nero, matugen non gira
# perche' non ha un'immagine da cui estrarre, e i colori restano i semi. Cioe'
# esattamente il momento in cui il desktop deve fare la sua figura migliore.
#
# SFONDI_DIR continua a sovrascrivere la prima, come prima.
CARTELLE=(
    "${SFONDI_DIR:-$HOME/Git/wallpapers}"
    "$QUI/../../../sfondi"
)

# I due file che tengono un percorso di immagine. Entrambi hanno una sola riga
# `path = ...` dentro un blocco (wallpaper{} e background{}), quindi la stessa
# sostituzione vale per tutti e due.
#   hyprpaper.conf -> lo sfondo del desktop
#   hyprlock.conf  -> lo sfondo della schermata di blocco, cosi' segue il primo
CONF_SFONDO="$HOME/.config/hypr/hyprpaper.conf"
CONF_BLOCCO="$HOME/.config/hypr/hyprlock.conf"

avvisa() {
    command -v notify-send >/dev/null && notify-send -a sfondo "Sfondo" "$1" \
        || echo "$1" >&2
}

################################################################################
#  1. Elenco delle immagini disponibili
################################################################################
# -print0 / -d '' per non inciampare sui nomi con spazi.
# .git escluso: la cartella puo' essere un repo, non serve pescare dentro gli
# oggetti. Le cartelle che non esistono si saltano senza lamentarsi: e' normale
# che la collezione personale non ci sia su una macchina appena installata.
elenca() {
    for c in "${CARTELLE[@]}"; do
        [ -d "$c" ] || continue
        find -L "$c" -type d -name .git -prune -o -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
               -o -iname '*.webp' -o -iname '*.bmp' \) -print0 2>/dev/null
    done | sort -z
}

################################################################################
#  2. Quale immagine
################################################################################
img="${1:-}"

# --primo: lo chiama installa-tutto.sh a fine installazione, quando non c'e'
# ancora nessuno davanti allo schermo. Quindi niente menu, e soprattutto niente
# da fare se uno sfondo valido c'e' gia': reinstallare non deve cambiare la
# scelta di chi lo aveva gia' impostato.
if [ "$img" = "--primo" ]; then
    gia="$(grep -m1 -E '^[[:space:]]*path[[:space:]]*=' "$HOME/.config/hypr/hyprpaper.conf" 2>/dev/null \
           | sed 's/^[^=]*=[[:space:]]*//')"
    if [ -n "$gia" ] && [ -f "$gia" ]; then
        echo "sfondo gia' impostato: $(basename "$gia")"
        exit 0
    fi
    # Il primo dell'elenco, non uno a caso: cosi' due installazioni sulla stessa
    # macchina partono identiche, e se qualcosa non va si sa da che immagine.
    mapfile -d '' -t trovate < <(elenca)
    [ "${#trovate[@]}" -gt 0 ] || { echo "Nessuna immagine trovata." >&2; exit 1; }
    img="${trovate[0]}"
fi

if [ -z "$img" ] || [ "$img" = "--caso" ]; then
    mapfile -d '' -t trovate < <(elenca)

    if [ "${#trovate[@]}" -eq 0 ]; then
        avvisa "Nessuna immagine in: ${CARTELLE[*]}"
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
#
# Solo se c'e' un compositore con cui parlare: installa-tutto.sh chiama --primo
# a fine installazione, quando Hyprland non e' ancora partito. In quel caso non
# c'e' niente da applicare adesso — basta scrivere nei file, e al primo avvio
# hyprpaper legge da li'.
if hyprctl monitors -j >/dev/null 2>&1; then
    while read -r mon; do
        [ -n "$mon" ] || continue
        hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null
    done < <(hyprctl monitors -j | jq -r '.[].name')
fi

################################################################################
#  4. Rendi permanente: riscrive la riga `path` in hyprpaper.conf e hyprlock.conf
################################################################################
# Si tocca solo quella riga: commenti e resto del file restano intatti.
# Il percorso arriva come argomento, non interpolato: nomi con spazi o apici
# non rompono niente.
#
# L'errore su un file non deve impedire di scrivere l'altro: se hyprlock.conf e'
# stato modificato a mano, lo sfondo del desktop deve comunque restare.
if ! motivo=$(python3 - "$img" "$CONF_SFONDO" "$CONF_BLOCCO" <<'PY' 2>&1
import sys, pathlib, re

img, files = sys.argv[1], sys.argv[2:]
problemi = []

for f in files:
    conf = pathlib.Path(f)
    if not conf.is_file():
        problemi.append(f"{conf.name}: non esiste")
        continue

    testo = conf.read_text()

    # Sostituisce il primo "path = ..." conservando l'indentazione originale.
    # In entrambi i file ce n'e' esattamente una, dentro il blocco che serve.
    nuovo, n = re.subn(
        r'^([ \t]*)path\s*=.*$',
        lambda m: f"{m.group(1)}path = {img}",
        testo,
        count=1,
        flags=re.MULTILINE,
    )

    if n == 0:
        problemi.append(f"{conf.name}: nessuna riga 'path ='")
        continue

    if nuovo != testo:
        conf.write_text(nuovo)

if problemi:
    sys.exit("; ".join(problemi))
PY
); then
    # Non e' fatale: lo sfondo e' gia' applicato a schermo, si perde solo la
    # persistenza al riavvio. Dirlo pero' serve, altrimenti la prossima
    # accensione sembra aver "dimenticato" la scelta senza motivo.
    avvisa "Sfondo applicato, ma non reso permanente: $motivo"
fi

################################################################################
#  5. Rigenera la palette dallo sfondo e ricarica chi la usa
################################################################################
# --prefer saturation NON e' opzionale: quando da un'immagine si possono
# estrarre piu' colori sorgente, matugen normalmente chiede all'utente quale
# usare. Lanciato da una scorciatoia non c'e' nessun terminale a cui chiedere e
# fallisce con "a terminal was not detected". Con --prefer sceglie da se'.
# "saturation" = il piu' saturo fra i candidati: da' accenti vivi invece di
# grigi slavati.
# Trovare matugen non e' banale e qui si nasconde un bug che e' costato tempo:
# le scorciatoie di Hyprland NON passano da una shell interattiva, quindi il
# loro PATH e' solo quello del compositore — /usr/bin e compagnia, senza
# ~/.local/bin (che lo aggiunge il profilo della shell). Risultato: da terminale
# funzionava, da SUPER+W cambiava lo sfondo e non i colori, senza dire niente.
# Quindi: si cerca nel PATH e poi nei posti noti, a mano.
MATUGEN=""
for candidato in matugen "$HOME/.local/bin/matugen" /usr/bin/matugen; do
    if percorso=$(command -v "$candidato" 2>/dev/null); then
        MATUGEN="$percorso"
        break
    fi
done

if [ -z "$MATUGEN" ]; then
    # Silenzio no: se la palette non si rigenera si deve sapere perche'.
    avvisa "Sfondo cambiato. matugen non trovato: i colori restano quelli di prima."
else
    # -j hex: oltre a riscrivere i template, matugen sputa la palette in json
    # sullo standard output. Serve a colori-terminale.py, che dai ruoli Material
    # (fondo, testo, accento) costruisce i 16 colori ANSI del terminale con il
    # contrasto garantito. Non li fa matugen perche' non puo': vedi il commento
    # nel suo config.toml.
    if palette=$("$MATUGEN" --quiet --prefer saturation -j hex image "$img" 2>/dev/null); then

        # L'errore non si butta via: finisce nella notifica, altrimenti il
        # terminale resterebbe coi colori vecchi senza dire perche'. Si tiene
        # l'ultima riga, che di un traceback e' quella che dice qualcosa.
        if ! motivo=$(printf '%s' "$palette" \
            | python3 "$QUI/colori-terminale.py" 2>&1); then
            avvisa "Colori aggiornati, tranne il terminale: ${motivo##*$'\n'}"
        fi

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
