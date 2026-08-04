#!/usr/bin/env bash
#
# power-profile.sh — prova sistema/bin/power-profile-auto senza toccare il
#                    sistema vero, con un /sys finto e un powerprofilesctl finto.
#
#   ./prova/power-profile.sh
#
# Gira ovunque: non serve Arch, non serve power-profiles-daemon, non serve root.
#
# PERCHE' ESISTE
# Quel binario viene lanciato da udev, cioe' in un contesto dove nessuno guarda:
# se sbaglia, il sintomo e' "il portatile dura meno di prima" — mesi dopo, senza
# un messaggio, senza un log. E' proprio il genere di codice che va provato
# adesso, che si puo'.
#
# Le situazioni provate sono quattro, e la terza e' quella che conta di piu':
# la regola udev originale filtrava per KERNEL=="ACAD", che e' il nome che da'
# il firmware di questo Acer. Su un'altra macchina si chiama ADP1 o AC, e la
# regola non sarebbe mai scattata.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
BANCO="$(mktemp -d)"
trap 'rm -rf "$BANCO"' EXIT

FINTI="$BANCO/bin"
SYS="$BANCO/sys"
STATO="$BANCO/profilo"
mkdir -p "$FINTI" "$SYS"

# --- i finti -----------------------------------------------------------------
cat > "$FINTI/powerprofilesctl" <<EOF
#!/bin/sh
case "\$1" in
  list) printf 'performance:\nbalanced:\npower-saver:\n' ;;
  get)  cat "$STATO" 2>/dev/null || echo balanced ;;
  set)  echo "\$2" > "$STATO" ;;
esac
EOF

# is-active risponde sempre di si': il ramo "demone non ancora su" e' un exit 0
# silenzioso, non c'e' niente da osservare.
printf '#!/bin/sh\nexit 0\n' > "$FINTI/systemctl"
chmod +x "$FINTI"/*

# Il binario cerca powerprofilesctl con percorso assoluto (gira da udev, dove il
# PATH non e' garantito): per la prova si dirotta quella riga sola.
SOTTO_PROVA="$BANCO/power-profile-auto"
sed "s|^PPCTL=.*|PPCTL=$FINTI/powerprofilesctl|" \
    "$REPO/sistema/bin/power-profile-auto" > "$SOTTO_PROVA"
chmod +x "$SOTTO_PROVA"

lancia() { PATH="$FINTI:$PATH" POWER_SUPPLY_ROOT="$SYS" "$SOTTO_PROVA"; }
profilo() { cat "$STATO" 2>/dev/null || echo "(non impostato)"; }

falliti=0
verifica() { # verifica <descrizione> <atteso>
    local atteso="$2" ottenuto
    ottenuto="$(profilo)"
    if [ "$ottenuto" = "$atteso" ]; then
        printf '  ok      %-46s %s\n' "$1" "$ottenuto"
    else
        printf '  ERRORE  %-46s atteso %s, ottenuto %s\n' "$1" "$atteso" "$ottenuto"
        falliti=$((falliti + 1))
    fi
}

# --- 1. alimentatore attaccato ------------------------------------------------
mkdir -p "$SYS/ACAD" "$SYS/BAT1"
echo Mains   > "$SYS/ACAD/type"
echo Battery > "$SYS/BAT1/type"
echo power-saver > "$STATO"      # si parte dal profilo sbagliato, apposta
echo 1 > "$SYS/ACAD/online"
lancia
verifica "in corrente" balanced

# --- 2. alimentatore staccato --------------------------------------------------
echo 0 > "$SYS/ACAD/online"
lancia
verifica "a batteria" power-saver

# --- 3. alimentatore con un altro nome -----------------------------------------
# Questo e' il motivo per cui la regola udev filtra per tipo e non per nome.
rm -rf "$SYS/ACAD"
mkdir -p "$SYS/ADP1"
echo Mains > "$SYS/ADP1/type"
echo 1     > "$SYS/ADP1/online"
lancia
verifica "alimentatore chiamato ADP1, non ACAD" balanced

# --- 4. profilo che su questo hardware non esiste --------------------------------
# Deve lasciare le cose come stanno invece di far fallire la regola udev ad ogni
# singolo evento.
# `set` qui non deve proprio essere chiamato: se lo fosse, scrive un valore
# riconoscibile e la verifica qui sotto se ne accorge.
cat > "$FINTI/powerprofilesctl" <<EOF
#!/bin/sh
case "\$1" in
  list) printf 'balanced:\n' ;;
  get)  echo balanced ;;
  set)  echo "HA-CHIAMATO-SET-\$2" > "$STATO" ;;
esac
EOF
chmod +x "$FINTI/powerprofilesctl"
echo balanced > "$STATO"
rm -rf "$SYS/ADP1"               # a batteria: vorrebbe power-saver, che non c'e'
lancia
verifica "profilo assente: non insiste" balanced

# --- esito ----------------------------------------------------------------------
echo
if [ "$falliti" -gt 0 ]; then
    echo "$falliti prove fallite." >&2
    exit 1
fi
echo "power-profile-auto: tutte le prove passate."
