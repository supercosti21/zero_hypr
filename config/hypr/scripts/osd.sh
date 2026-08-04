#!/usr/bin/env bash
#
# osd.sh — volume, microfono e luminosita' con un riscontro a schermo.
#
#   osd.sh volume su|giu|muto
#   osd.sh microfono muto
#   osd.sh luce su|giu
#
# Legato ai tasti dedicati della tastiera in hyprland.lua.
#
# PERCHE' ESISTE
# Prima quei tasti chiamavano wpctl e brightnessctl e basta: il volume
# cambiava davvero, ma senza NESSUN riscontro. Su un portatile e' un problema
# concreto — schiacci tre volte, non succede niente di visibile, e non sai se e'
# arrivato a zero, se il tasto non funziona o se stai regolando l'uscita
# sbagliata.
#
# PERCHE' UNA NOTIFICA E NON UN WIDGET
# swayosd fa un riquadro piu' bello, ma e' un demone in piu' sempre acceso, con
# un suo foglio di stile che sfuggirebbe a matugen: sarebbe l'unico pezzo del
# desktop a non seguire lo sfondo. swaync invece e' gia' in esecuzione, e' gia'
# intonato (colori.css lo riscrive matugen ad ogni SUPER+W) e sa disegnare una
# barra di avanzamento da solo. Costo aggiunto: zero demoni, zero pacchetti,
# zero CSS da mantenere.
#
# IL DETTAGLIO CHE FA LA DIFFERENZA
# x-canonical-private-synchronous: e' l'hint che dice al demone "questa notifica
# SOSTITUISCE quella con la stessa etichetta". Senza, tenendo premuto il tasto
# del volume si impilano venti notifiche e lo schermo diventa inguardabile.

set -uo pipefail

SINK="@DEFAULT_AUDIO_SINK@"
SOURCE="@DEFAULT_AUDIO_SOURCE@"
PASSO=5

manda() { # manda <etichetta> <icona> <titolo> <valore 0-100 oppure vuoto>
    local etichetta="$1" icona="$2" titolo="$3" valore="${4:-}"
    local args=(
        --app-name=osd
        --urgency=low
        --expire-time=1200
        --icon="$icona"
        # Stessa etichetta = stessa notifica riusata, invece di una nuova.
        --hint="string:x-canonical-private-synchronous:$etichetta"
    )
    # Il valore intero fa disegnare la barra di avanzamento. Se manca (muto),
    # resta solo il testo, che e' giusto: una barra a zero e una barra
    # silenziata si confonderebbero.
    [ -n "$valore" ] && args+=(--hint="int:value:$valore")

    notify-send "${args[@]}" "$titolo" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------- volume
# `wpctl get-volume` risponde "Volume: 0.42" oppure "Volume: 0.42 [MUTED]".
volume_stato() {
    local riga
    riga="$(wpctl get-volume "$1" 2>/dev/null)" || return 1
    local frazione muto=0
    frazione="$(echo "$riga" | awk '{print $2}')"
    echo "$riga" | grep -q MUTED && muto=1
    # Arrotondamento a intero: awk e non bash, che non fa virgola mobile.
    echo "$(awk -v f="$frazione" 'BEGIN{printf "%d", f*100+0.5}') $muto"
}

# Le icone sono nomi standard freedesktop: le risolve il tema in uso
# (Papirus-Dark), quindi seguono il tema come tutto il resto.
icona_volume() { # <percentuale> <muto>
    [ "$2" = 1 ] && { echo audio-volume-muted; return; }
    [ "$1" -eq 0 ]  && { echo audio-volume-muted; return; }
    [ "$1" -lt 34 ] && { echo audio-volume-low;    return; }
    [ "$1" -lt 67 ] && { echo audio-volume-medium; return; }
    echo audio-volume-high
}

mostra_volume() {
    local s pct muto
    s="$(volume_stato "$SINK")" || { manda volume audio-volume-muted "Audio non disponibile"; return; }
    pct="${s% *}"; muto="${s#* }"

    if [ "$muto" = 1 ]; then
        manda volume audio-volume-muted "Audio silenziato"
    else
        manda volume "$(icona_volume "$pct" "$muto")" "Volume  ${pct}%" "$pct"
    fi
}

mostra_microfono() {
    local s muto
    s="$(volume_stato "$SOURCE")" || { manda microfono microphone-sensitivity-muted "Microfono non disponibile"; return; }
    muto="${s#* }"
    if [ "$muto" = 1 ]; then
        manda microfono microphone-sensitivity-muted "Microfono silenziato"
    else
        manda microfono microphone-sensitivity-high "Microfono attivo"
    fi
}

# --------------------------------------------------------------- luminosita'
mostra_luce() {
    local ora max pct
    ora="$(brightnessctl get 2>/dev/null)" || return
    max="$(brightnessctl max 2>/dev/null)" || return
    [ "$max" -gt 0 ] || return
    pct=$(( (ora * 100 + max / 2) / max ))

    local icona=display-brightness-high
    [ "$pct" -lt 34 ] && icona=display-brightness-low
    [ "$pct" -lt 67 ] && [ "$pct" -ge 34 ] && icona=display-brightness-medium

    manda luce "$icona" "Luminosita'  ${pct}%" "$pct"
}

# ------------------------------------------------------------------- comandi
case "${1:-}" in
    volume)
        case "${2:-}" in
            # -l 1.0 impedisce di superare il 100%: oltre, l'audio distorce e
            # non e' quello che uno si aspetta tenendo premuto un tasto.
            su)   wpctl set-volume -l 1.0 "$SINK" "${PASSO}%+" ;;
            giu)  wpctl set-volume "$SINK" "${PASSO}%-" ;;
            muto) wpctl set-mute "$SINK" toggle ;;
            *)    echo "uso: $0 volume su|giu|muto" >&2; exit 1 ;;
        esac
        mostra_volume
        ;;
    microfono)
        wpctl set-mute "$SOURCE" toggle
        mostra_microfono
        ;;
    luce)
        case "${2:-}" in
            # Il minimo a 1% e non 0: a zero lo schermo si spegne del tutto e
            # per rialzarlo devi indovinare il tasto al buio.
            su)  brightnessctl set "${PASSO}%+" >/dev/null ;;
            giu) brightnessctl set "${PASSO}%-" -n 1 >/dev/null ;;
            *)   echo "uso: $0 luce su|giu" >&2; exit 1 ;;
        esac
        mostra_luce
        ;;
    *)
        echo "uso: $0 volume su|giu|muto | microfono muto | luce su|giu" >&2
        exit 1
        ;;
esac
