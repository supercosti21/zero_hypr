#!/usr/bin/env bash
#
# appunti.sh — storico degli appunti in fuzzel.
#
# Legato a SUPER+V, e raggiungibile anche dalla palette (SUPER+R -> Appunti).
#
# Perche' un file e non una pipeline dentro la scorciatoia, com'era prima:
# adesso i posti da cui si apre sono due, e due copie della stessa pipeline
# prima o poi divergono — si aggiusta una e si dimentica l'altra. Qui c'e' anche
# spazio per il "cancella storico", che dentro una riga di config non ci stava.
#
# Lo storico lo riempiono i due `wl-paste --watch cliphist store` avviati da
# hyprland.lua al login: uno per il testo, uno per le immagini.

set -uo pipefail

command -v cliphist >/dev/null || {
    notify-send -a appunti "Appunti" "cliphist non c'e'" 2>/dev/null; exit 1; }

VOCE_PULISCI="󰃢  Cancella tutto lo storico"

elenco="$(cliphist list 2>/dev/null)"

if [ -z "$elenco" ]; then
    notify-send -a appunti "Appunti" "Storico vuoto" 2>/dev/null
    exit 0
fi

scelta="$(printf '%s\n%s\n' "$elenco" "$VOCE_PULISCI" \
          | fuzzel --dmenu --prompt='appunti> ' --lines=12 --width=60)" || exit 0
[ -n "$scelta" ] || exit 0

if [ "$scelta" = "$VOCE_PULISCI" ]; then
    # Si chiede conferma: lo storico degli appunti contiene spesso l'unica copia
    # di qualcosa, e non si torna indietro.
    conferma="$(printf 'No, lascia stare\nSi, cancella tutto' \
                | fuzzel --dmenu --prompt='sicuro? > ' --lines=2 --width=30)" || exit 0
    case "$conferma" in
        Si,*) cliphist wipe && notify-send -a appunti "Appunti" "Storico cancellato" 2>/dev/null ;;
    esac
    exit 0
fi

# `cliphist decode` risale dalla riga dell'elenco al contenuto vero: le voci
# mostrate sono troncate e con l'id davanti, non sono il testo da incollare.
printf '%s' "$scelta" | cliphist decode | wl-copy
