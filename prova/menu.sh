#!/usr/bin/env bash
#
# menu.sh — prova l'instradamento della palette, senza aprire niente a schermo.
#
#   ./prova/menu.sh
#
# Gira ovunque: fuzzel, hyprctl, wl-copy e notify-send sono finti, e le
# applicazioni sono file .desktop costruiti apposta in una cartella temporanea.
#
# PERCHE' ESISTE
# menu.sh sta su SUPER+R, il tasto che si preme piu' spesso di qualunque altro.
# Un errore li' non e' un fastidio: e' il desktop che smette di rispondere al
# gesto piu' automatico che c'e'. E il grosso della sua logica — quale
# prefisso porta dove, come si risale dal nome scelto al comando — non si puo'
# provare a mano senza aprire e chiudere la finestra venti volte.
#
# I file .desktop del banco coprono le trappole vere della specifica:
# NoDisplay, Hidden, TryExec verso un programma assente, i segnaposto %U, le
# azioni secondarie in fondo al file e la precedenza fra cartelle.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
MENU="$REPO/config/hypr/scripts/menu.sh"
APP="$REPO/config/hypr/scripts/applicazioni.py"

BANCO="$(mktemp -d)"
trap 'rm -rf "$BANCO"' EXIT

FINTI="$BANCO/bin"
SISTEMA="$BANCO/dati/applications"
UTENTE="$BANCO/utente/applications"
AZIONI="$BANCO/azioni.log"
mkdir -p "$FINTI" "$SISTEMA" "$UTENTE"

# ---------------------------------------------------------------- i finti
cat > "$FINTI/fuzzel" <<EOF
#!/bin/sh
cat > "$BANCO/ultimo-elenco.txt"
[ -n "\${FUZZEL_RISPOSTA:-}" ] || exit 1
printf '%s\n' "\$FUZZEL_RISPOSTA"
EOF
cat > "$FINTI/hyprctl" <<EOF
#!/bin/sh
printf 'exec %s\n' "\$*" | sed 's/^exec dispatch exec -- //' >> "$AZIONI"
EOF
cat > "$FINTI/notify-send" <<EOF
#!/bin/sh
printf 'notifica %s\n' "\$*" >> "$AZIONI"
EOF
cat > "$FINTI/wl-copy" <<EOF
#!/bin/sh
printf 'appunti %s\n' "\$(cat)" >> "$AZIONI"
EOF
chmod +x "$FINTI"/*

# ------------------------------------------------------- le applicazioni finte
scrivi() { printf '%s\n' "$2" > "$1"; }

scrivi "$SISTEMA/navigatore.desktop" '[Desktop Entry]
Type=Application
Name=Navigatore
Name[it]=Navigatore Tradotto
Exec=navigatore %u
Icon=web-browser
[Desktop Action nuova]
Name=Nuova finestra
Exec=navigatore --new-window %u'

scrivi "$SISTEMA/monitor.desktop" '[Desktop Entry]
Type=Application
Name=Monitor
Exec=btop
Terminal=true'

scrivi "$SISTEMA/interna.desktop" '[Desktop Entry]
Type=Application
Name=Voce di servizio
Exec=niente
NoDisplay=true'

scrivi "$SISTEMA/fantasma.desktop" '[Desktop Entry]
Type=Application
Name=Programma assente
Exec=programma-che-non-esiste-xyz
TryExec=programma-che-non-esiste-xyz'

scrivi "$UTENTE/navigatore.desktop" '[Desktop Entry]
Type=Application
Name=Navigatore
Exec=navigatore --profilo mio %u
Icon=web-browser'

# --------------------------------------------------------------- gli aiuti
export XDG_DATA_DIRS="$BANCO/dati"
export XDG_DATA_HOME="$BANCO/utente"
export XDG_CACHE_HOME="$BANCO/cache"
export PATH="$FINTI:$PATH"

falliti=0

verifica() { # verifica <descrizione> <cosa si sceglie> <cosa deve risultare>
    : > "$AZIONI"
    FUZZEL_RISPOSTA="$2" "$MENU" >/dev/null 2>&1
    local ottenuto
    ottenuto="$(cat "$AZIONI" 2>/dev/null | head -n1)"
    if [ "$ottenuto" = "$3" ]; then
        printf '  ok      %-34s %s\n' "$1" "$ottenuto"
    else
        printf '  ERRORE  %-34s\n          atteso  %s\n          ottenuto %s\n' "$1" "$3" "${ottenuto:-(niente)}"
        falliti=$((falliti + 1))
    fi
}

contiene() { # contiene <descrizione> <cosa NON deve esserci nell elenco>
    : > "$AZIONI"
    FUZZEL_RISPOSTA="" "$MENU" >/dev/null 2>&1
    if grep -q "$2" "$BANCO/ultimo-elenco.txt" 2>/dev/null; then
        printf '  ERRORE  %-34s "%s" non doveva comparire\n' "$1" "$2"
        falliti=$((falliti + 1))
    else
        printf '  ok      %-34s\n' "$1"
    fi
}

# ------------------------------------------------------------------ le prove
echo "Instradamento:"
# La voce dell'utente vince su quella di sistema, e i %u spariscono.
verifica "applicazione"              "Navigatore"        "navigatore --profilo mio"
verifica "applicazione da terminale" "Monitor"           "alacritty -e btop"
verifica "prefisso >"                "> htop"            "htop"
verifica "prefisso \$"                '$ journalctl -f'   "alacritty -e journalctl -f"
verifica "ricerca g"                 "g wayland"         "xdg-open https://www.google.com/search?q=wayland"
verifica "ricerca arch"              "arch pipewire"     "xdg-open https://wiki.archlinux.org/index.php?search=pipewire"
verifica "calcolo"                   "= 6*7"             "appunti 42"

echo
echo "Cosa NON deve finire nell'elenco:"
contiene "NoDisplay=true"            "Voce di servizio"
contiene "TryExec verso un assente"  "Programma assente"
contiene "azioni secondarie"         "Nuova finestra"
contiene "nomi tradotti"             "Navigatore Tradotto"

# ------------------------------------------------------- il lettore .desktop
echo
echo "Lettore dei .desktop:"
if "$APP" --comando "Navigatore" | grep -q '^diretto|navigatore --profilo mio$'; then
    printf '  ok      %s\n' "precedenza utente su sistema"
else
    printf '  ERRORE  %s\n' "precedenza utente su sistema"
    falliti=$((falliti + 1))
fi

if "$APP" --comando "Monitor" | grep -q '^terminale|'; then
    printf '  ok      %s\n' "Terminal=true riconosciuto"
else
    printf '  ERRORE  %s\n' "Terminal=true riconosciuto"
    falliti=$((falliti + 1))
fi

if ! "$APP" --comando "Non esiste affatto" >/dev/null 2>&1; then
    printf '  ok      %s\n' "nome sconosciuto -> uscita diversa da zero"
else
    printf '  ERRORE  %s\n' "nome sconosciuto -> uscita diversa da zero"
    falliti=$((falliti + 1))
fi

# La calcolatrice non deve essere una via per eseguire codice: l'espressione
# arriva a python come argomento, in un ambiente senza builtins.
echo
echo "Calcolatrice:"
: > "$AZIONI"
FUZZEL_RISPOSTA="= __import__('os').system('touch $BANCO/BUCATO')" "$MENU" >/dev/null 2>&1
if [ -e "$BANCO/BUCATO" ]; then
    printf '  ERRORE  %s\n' "eval e uscito dal recinto"
    falliti=$((falliti + 1))
else
    printf '  ok      %s\n' "eval resta dentro il recinto"
fi

# ---------------------------------------------------------------------- esito
echo
if [ "$falliti" -gt 0 ]; then
    echo "$falliti prove fallite." >&2
    exit 1
fi
echo "menu.sh: tutte le prove passate."
