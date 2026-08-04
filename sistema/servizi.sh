#!/usr/bin/env bash
#
# servizi.sh — abilita i servizi di sistema che l'ambiente da' per scontati.
#
#   sudo ./sistema/servizi.sh            applica
#   sudo ./sistema/servizi.sh --prova    dice cosa farebbe, senza toccare nulla
#
# Idempotente: quelli gia' abilitati vengono solo nominati.
# Questo script non scrive MAI dentro una home.
#
# COSA NON C'E' IN ELENCO, E PERCHE'
#   udisks2   — attivato da dbus a richiesta. Abilitarlo non serve, e un
#               servizio abilitato che non serve e' solo un altro modo di
#               allungare l'avvio.
#   udiskie, hyprpolkitagent, cliphist — vivono nella sessione utente, li lancia
#               hyprland.lua all'avvio di Hyprland. Un servizio di SISTEMA per
#               quelle cose sarebbe sbagliato: girerebbero anche senza nessuno
#               connesso.
#   power-profile-auto — lo abilita sistema/udev.sh, che e' anche quello che
#               installa il binario. Tenerli insieme evita di abilitare un
#               servizio che punta a un file che non c'e' ancora.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

AZIONE="${1:-applica}"
# shellcheck disable=SC2034  # la legge fai(), che sta in comune.sh
[ "$AZIONE" = "--prova" ] && PROVA=1

serve_root "$AZIONE"

# --now oltre a enable: cosi' rete e bluetooth funzionano subito, senza dover
# riavviare per forza. Sono tre demoni di sistema, non tocca la sessione aperta.
SERVIZI=(
    NetworkManager.service
    bluetooth.service
    power-profiles-daemon.service
)

esito=0
for u in "${SERVIZI[@]}"; do
    if ! systemctl cat "$u" >/dev/null 2>&1; then
        rosso "  manca   $u — il pacchetto non e' installato"
        esito=1
        continue
    fi

    if systemctl is-enabled --quiet "$u" 2>/dev/null; then
        verde "  ok      $u (gia' abilitato)"
        # Abilitato ma fermo capita dopo un'installazione senza riavvio.
        if ! systemctl is-active --quiet "$u" 2>/dev/null; then
            echo "          non e' in esecuzione, lo avvio"
            fai systemctl start "$u"
        fi
    else
        echo "  abilito $u"
        fai systemctl enable --now "$u"
    fi
done

exit "$esito"
