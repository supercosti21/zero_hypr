#!/usr/bin/env bash
#
# power-watch.sh — adatta il desktop all'alimentazione.
#
# Reagisce al collegamento/scollegamento dell'alimentatore e:
#   1. spegne gli effetti costosi in GPU (blur, ombre) quando si va a batteria;
#   2. ricarica hypridle con tempi aggressivi a batteria, rilassati in AC.
#
# E' guidato dagli eventi udev, non da un polling: a riposo consuma zero CPU.
# Il profilo energetico della CPU NON viene toccato qui: se ne occupa gia'
# /usr/local/bin/power-profile-auto tramite la sua regola udev.

set -uo pipefail

AC_ONLINE=/sys/class/power_supply/ACAD/online
CONF_DIR="$HOME/.config/hypr"

in_corrente() {
    [[ "$(cat "$AC_ONLINE" 2>/dev/null || echo 0)" == "1" ]]
}

riavvia_hypridle() {
    local profilo=$1
    pkill -x hypridle 2>/dev/null
    hypridle -c "$CONF_DIR/hypridle-${profilo}.conf" &
}

applica() {
    if in_corrente; then
        # --- Collegato alla rete: tutti gli effetti attivi ---
        hyprctl --batch "\
            keyword decoration:blur:enabled true; \
            keyword decoration:shadow:enabled true" >/dev/null 2>&1
        riavvia_hypridle ac
    else
        # --- A batteria: via blur e ombre, gli unici effetti che costano
        #     davvero in GPU. Le animazioni restano: durano 3 frame e con il
        #     VFR attivo il loro costo e' trascurabile. ---
        hyprctl --batch "\
            keyword decoration:blur:enabled false; \
            keyword decoration:shadow:enabled false" >/dev/null 2>&1
        riavvia_hypridle batteria
    fi
}

# Stato iniziale al login
applica

# Poi resta in ascolto degli eventi dell'alimentatore.
# stdbuf serve a non far bufferizzare l'output di udevadm nella pipe.
stdbuf -oL udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null |
while read -r _; do
    # Gli eventi arrivano a raffica quando si stacca il cavo: piccola pausa
    # per applicare una volta sola invece di quattro.
    sleep 1
    applica
done
