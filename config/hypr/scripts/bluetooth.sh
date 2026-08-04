#!/usr/bin/env bash
#
# bluetooth.sh — dispositivi bluetooth dentro fuzzel, senza aprire blueman.
#
# Aperto dalla palette (SUPER+R -> Bluetooth) e dal modulo bluetooth in barra.
#
# Perche' esiste: per collegare le cuffie non serve una finestra intera con
# tabelle e pulsanti. Serve un elenco, una scelta, fatto. blueman resta
# installato per le cose che qui non ci sono (trasferimento file, opzioni per
# profilo audio) ed e' raggiungibile dalla palette sotto Impostazioni.
#
# Stessa forma di wifi.sh, che fa la stessa cosa per le reti: chi ha capito uno
# ha capito l'altro.

set -euo pipefail

menu() { fuzzel --dmenu --lines="${2:-12}" --width="${3:-46}" --prompt="$1"; }
avvisa() { notify-send -a bluetooth "Bluetooth" "$1" 2>/dev/null || echo "$1" >&2; }

command -v bluetoothctl >/dev/null || { avvisa "bluetoothctl non c'e' (bluez-utils)"; exit 1; }

# --- radio spenta: prima cosa da controllare, se no la scansione da' zero -------
if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
    scelta=$(printf 'Accendi il Bluetooth\nAnnulla' | menu 'bluetooth spento> ' 2 32)
    if [ "$scelta" = "Accendi il Bluetooth" ]; then
        bluetoothctl power on >/dev/null && avvisa "Bluetooth acceso"
        # Al risveglio la radio ci mette un attimo prima di rispondere.
        sleep 1
    else
        exit 0
    fi
fi

################################################################################
#  Elenco dispositivi
################################################################################
# `devices` da' quelli gia' noti; una scansione breve aggiunge quelli nuovi.
# Non si scansiona all'infinito: cinque secondi bastano per un paio di cuffie
# accese, e una scansione perenne consuma batteria su entrambi i lati.
elenca_voci() {
    local noti connessi accoppiati
    noti="$(bluetoothctl devices 2>/dev/null || true)"
    connessi="$(bluetoothctl devices Connected 2>/dev/null || true)"
    accoppiati="$(bluetoothctl devices Paired 2>/dev/null || true)"

    printf '%s\n' "$noti" | while read -r _ mac nome; do
        [ -n "${mac:-}" ] || continue
        stato=""
        printf '%s' "$accoppiati" | grep -q "$mac" && stato=" ·"
        printf '%s' "$connessi"   | grep -q "$mac" && stato=" ●"
        printf '󰂯 %s%s\t%s\n' "${nome:-$mac}" "$stato" "$mac"
    done
}

cerca_nuovi() {
    avvisa "Cerco dispositivi…"
    # --timeout esiste da bluez 5.65; se non c'e', si ripiega su un scan in
    # sottofondo che si ferma da solo dopo il sleep.
    if bluetoothctl --timeout 5 scan on >/dev/null 2>&1; then
        return 0
    fi
    bluetoothctl scan on >/dev/null 2>&1 &
    local pid=$!
    sleep 5
    kill "$pid" 2>/dev/null || true
    bluetoothctl scan off >/dev/null 2>&1 || true
}

################################################################################
#  Menu principale
################################################################################
voci="$(elenca_voci)"

# La riga di ricerca sta in fondo e non in cima: in cima verrebbe scelta per
# sbaglio premendo Invio di slancio, che e' proprio l'azione piu' lenta.
elenco="$(printf '%s\n󰑐 Cerca dispositivi nuovi\t--cerca\n󰂲 Spegni il Bluetooth\t--spegni' "$voci")"

scelta="$(printf '%s\n' "$elenco" | cut -f1 | menu 'bluetooth> ')" || exit 0
[ -n "$scelta" ] || exit 0

# Dalla riga scelta si recupera il MAC, che e' la seconda colonna.
riga="$(printf '%s\n' "$elenco" | grep -F -m1 "$scelta" || true)"
mac="$(printf '%s' "$riga" | cut -f2)"
[ -n "$mac" ] || exit 0

case "$mac" in
    --spegni)
        bluetoothctl power off >/dev/null && avvisa "Bluetooth spento"
        exit 0
        ;;
    --cerca)
        cerca_nuovi
        exec "$0"          # si riapre col nuovo elenco
        ;;
esac

################################################################################
#  Cosa fare col dispositivo scelto
################################################################################
nome="${scelta#󰂯 }"; nome="${nome% ●}"; nome="${nome% ·}"

if bluetoothctl devices Connected 2>/dev/null | grep -q "$mac"; then
    azioni='󰂲 Disconnetti\t--disconnetti\n󰆴 Dimentica\t--dimentica'
else
    azioni='󰂱 Connetti\t--connetti\n󰆴 Dimentica\t--dimentica'
fi

azione_riga="$(printf "$azioni")"
az="$(printf '%s\n' "$azione_riga" | cut -f1 | menu "$nome> " 3 34)" || exit 0
[ -n "$az" ] || exit 0
az="$(printf '%s\n' "$azione_riga" | grep -F -m1 "$az" | cut -f2)"

case "$az" in
    --connetti)
        # trust prima di connect: senza, ogni riaccensione delle cuffie richiede
        # di riautorizzare, ed e' il fastidio numero uno del bluetooth su Linux.
        bluetoothctl trust "$mac" >/dev/null 2>&1 || true
        if bluetoothctl connect "$mac" >/dev/null 2>&1; then
            avvisa "Connesso a $nome"
        else
            # Mai accoppiato prima: si prova l'accoppiamento e poi si riconnette.
            if bluetoothctl pair "$mac" >/dev/null 2>&1 \
               && bluetoothctl connect "$mac" >/dev/null 2>&1; then
                avvisa "Connesso a $nome"
            else
                avvisa "Connessione a $nome fallita"
                exit 1
            fi
        fi
        ;;
    --disconnetti)
        bluetoothctl disconnect "$mac" >/dev/null 2>&1 \
            && avvisa "Disconnesso $nome" || avvisa "Non sono riuscito a disconnettere $nome"
        ;;
    --dimentica)
        bluetoothctl remove "$mac" >/dev/null 2>&1 \
            && avvisa "$nome dimenticato" || avvisa "Non sono riuscito a rimuovere $nome"
        ;;
esac
