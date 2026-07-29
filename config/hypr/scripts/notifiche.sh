#!/usr/bin/env bash
#
# notifiche.sh — avvia il demone delle notifiche.
#
# Perche' non un `exec-once = swaync` secco: swaync e mako sono entrambi demoni
# di org.freedesktop.Notifications, quindi si escludono a vicenda. Se in
# hyprland.conf ci fosse solo swaync e il pacchetto non fosse installato, si
# resterebbe SENZA notifiche e senza capire perche'. Qui si prende swaync se
# c'e' (ha il pannello con lo storico) e si ripiega su mako, che e' comunque
# installato e sa fare le notifiche a comparsa.

set -u

if command -v swaync >/dev/null 2>&1; then
    exec swaync
elif command -v mako >/dev/null 2>&1; then
    notify-send -a notifiche "Notifiche" \
        "swaync non installato: uso mako (niente pannello storico)" 2>/dev/null &
    exec mako
else
    exit 1
fi
