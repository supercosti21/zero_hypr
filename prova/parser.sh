#!/usr/bin/env bash
#
# parser.sh — i parser contro i campioni, senza nessuno dei programmi veri.
#
#   ./prova/parser.sh
#
# PERCHE' ESISTE
# Quattro punti del desktop leggono l'output testuale di altri programmi:
# `wpctl status`, `powerprofilesctl list`, `bluetoothctl devices` e
# `hyprctl clients -j`. Scritti guardando la documentazione, non l'output vero.
# E' la categoria di codice che sbaglia piu' spesso e nel modo piu' silenzioso:
# quando un formato non e' quello atteso, il risultato non e' un errore ma un
# menu vuoto o — peggio — un menu con dentro le voci sbagliate.
#
# I parser sono stati separati dai comandi che li alimentano proprio per poterli
# provare qui. Ogni funzione legge da stdin (o da argomenti), quindi le si puo'
# dare in pasto un file.
#
# ATTENZIONE, il limite di questo file: i campioni in prova/campioni/ sono
# riproduzioni fedeli al formato documentato, non catture da una macchina vera.
# Un campione sbagliato darebbe un test verde e un desktop rotto. Vedi
# prova/campioni/PROVENIENZA.md per come rifarli dal vero sul portatile.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
CAMPIONI="$QUI/campioni"
MENU="$REPO/config/hypr/scripts/menu.sh"
BT="$REPO/config/hypr/scripts/bluetooth.sh"

# Si estrae la singola funzione invece di eseguire lo script: menu.sh e
# bluetooth.sh in fondo aprono fuzzel, e qui non c'e' nessuno che risponda.
carica() { # carica <file> <nome funzione>
    sed -n "/^$2()/,/^}/p" "$1"
}

falliti=0

uguale() { # uguale <descrizione> <atteso> <ottenuto>
    if [ "$2" = "$3" ]; then
        printf '  ok      %s\n' "$1"
    else
        printf '  ERRORE  %s\n' "$1"
        printf '          atteso:\n%s\n' "$(printf '%s\n' "$2" | sed 's/^/            /')"
        printf '          ottenuto:\n%s\n' "$(printf '%s\n' "$3" | sed 's/^/            /')"
        falliti=$((falliti + 1))
    fi
}

# ============================================================ uscite audio
echo "wpctl status → uscite audio"
audio() { bash -c "$(carica "$MENU" leggi_uscite_audio); leggi_uscite_audio" < "$1"; }

uguale "due o piu uscite, una predefinita" \
"$(printf '󰓃  Built-in Audio Analog Stereo ●\t56\n󰓃  HDMI / DisplayPort 1\t70\n󰓃  Cuffie BT\t72')" \
"$(audio "$CAMPIONI/wpctl-status.txt")"

uguale "una sola uscita, nessuna predefinita" \
"$(printf '󰓃  Built-in Audio Analog Stereo\t56')" \
"$(audio "$CAMPIONI/wpctl-status-una.txt")"

uguale "sezione Sinks vuota" "" "$(audio "$CAMPIONI/wpctl-status-vuoto.txt")"

# Il caso che la prima versione sbagliava: cercava l asterisco in tutta la riga,
# quindi un dispositivo con "*" nel nome risultava quello predefinito.
uguale "asterisco DENTRO il nome: non e la predefinita" \
"$(printf '󰓃  Scheda *speciale* USB\t70\n󰓃  Built-in Audio Analog Stereo ●\t56')" \
"$(audio "$CAMPIONI/wpctl-status-asterisco.txt")"

# Le Sources non devono finire fra le uscite: hanno lo stesso formato e stanno
# nella sezione subito dopo.
if audio "$CAMPIONI/wpctl-status.txt" | grep -q '	57$'; then
    printf '  ERRORE  %s\n' "una Source e finita fra le uscite"
    falliti=$((falliti + 1))
else
    printf '  ok      %s\n' "le Sources restano fuori"
fi

# ========================================================= profili energetici
echo
echo "powerprofilesctl list → profili"
energia() { bash -c "$(carica "$MENU" leggi_profili_energia); leggi_profili_energia" < "$1"; }

uguale "i tre profili, output multi-riga" \
"$(printf 'performance\nbalanced\npower-saver')" \
"$(energia "$CAMPIONI/powerprofilesctl-list.txt")"

uguale "con Degraded valorizzato" \
"$(printf 'performance\nbalanced\npower-saver')" \
"$(energia "$CAMPIONI/powerprofilesctl-list-degradato.txt")"

# Il criterio e la POSIZIONE, non il nome: le chiavi di dettaglio sono rientrate
# di quattro. Il filtro precedente guardava il nome e reggeva solo perche
# "Driver" e "Degraded" hanno la maiuscola — una chiave minuscola lo rompeva.
uguale "chiave di dettaglio minuscola: non diventa un profilo" \
"$(printf 'performance\nbalanced')" \
"$(printf '  performance:\n    active: yes\n    Driver: x\n\n* balanced:\n    active: no\n' \
   | bash -c "$(carica "$MENU" leggi_profili_energia); leggi_profili_energia")"

# Nessun elenco fisso di profili ammessi: se ppd ne aggiungesse uno, deve
# comparire invece di sparire in silenzio.
uguale "un profilo nuovo non viene scartato" \
"$(printf 'performance\nbalanced\nultra-saver')" \
"$(printf '  performance:\n    Driver: x\n\n* balanced:\n    Driver: x\n\n  ultra-saver:\n    Driver: x\n' \
   | bash -c "$(carica "$MENU" leggi_profili_energia); leggi_profili_energia")"

# ================================================================= finestre
echo
echo "hyprctl clients -j → finestre"
if command -v jq >/dev/null 2>&1; then
    finestre="$(bash -c "$(carica "$MENU" leggi_finestre); leggi_finestre" \
                < "$CAMPIONI/hyprctl-clients.json")"

    uguale "tre finestre, scratchpad compreso" "3" "$(printf '%s\n' "$finestre" | wc -l | tr -d ' ')"

    printf '%s\n' "$finestre" | grep -qF "special:magic" \
        && printf '  ok      %s\n' "lo scratchpad compare: ci si puo tornare" \
        || { printf '  ERRORE  %s\n' "lo scratchpad manca"; falliti=$((falliti + 1)); }

    printf '%s\n' "$finestre" | grep -qF "0x55d1a2b3c500" \
        && { printf '  ERRORE  %s\n' "una finestra non mappata e nell elenco"; falliti=$((falliti + 1)); } \
        || printf '  ok      %s\n' "le finestre non mappate restano fuori"

    printf '%s\n' "$finestre" | grep -qF "0x55d1a2b3c4d0" \
        && printf '  ok      %s\n' "l indirizzo arriva fino in fondo" \
        || { printf '  ERRORE  %s\n' "indirizzo mancante"; falliti=$((falliti + 1)); }
else
    printf '  -       %s\n' "jq non installato, salto"
fi

# ================================================================ bluetooth
echo
echo "bluetoothctl devices → dispositivi"
bt="$(bash -c "
    $(carica "$BT" componi_voci)
    componi_voci \"\$(cat '$CAMPIONI/bluetoothctl-devices.txt')\" \
                 \"\$(cat '$CAMPIONI/bluetoothctl-devices-connessi.txt')\" \
                 \"\$(cat '$CAMPIONI/bluetoothctl-devices-accoppiati.txt')\"
")"

uguale "connesso ●, accoppiato ·, sconosciuto niente" \
"$(printf '󰂯 Cuffie Sony WH-1000XM4 ●\t04:52:C7:2A:1B:9F\n󰂯 Logitech MX Master 3 ·\tA0:C5:89:11:22:33\n󰂯 JBL Go 3\t5C:F3:70:AA:BB:CC')" \
"$bt"

# I nomi con spazi non devono spezzarsi: read -r _ mac nome funziona perche
# l ultima variabile prende tutto il resto della riga.
printf '%s\n' "$bt" | grep -qF "Cuffie Sony WH-1000XM4" \
    && printf '  ok      %s\n' "i nomi con spazi restano interi" \
    || { printf '  ERRORE  %s\n' "nome troncato"; falliti=$((falliti + 1)); }

# Nessun dispositivo: non deve produrre una riga vuota che nel menu sembrerebbe
# una voce scegliibile.
vuoto="$(bash -c "$(carica "$BT" componi_voci); componi_voci '' '' ''")"
uguale "nessun dispositivo: zero righe" "" "$vuoto"

# ==================================================================== esito
echo
if [ "$falliti" -gt 0 ]; then
    echo "$falliti prove fallite." >&2
    exit 1
fi
echo "parser: tutte le prove passate."
