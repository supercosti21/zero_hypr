#!/usr/bin/env bash
#
# notifiche.sh — avvia il demone delle notifiche.
#
# Perche' non un `exec-once = swaync` secco: se il pacchetto non fosse
# installato si resterebbe SENZA notifiche e senza capire perche'. Qui, se
# swaync manca, lo si dice invece di tacere.
#
# Un solo demone, di proposito. org.freedesktop.Notifications e' un nome dbus
# unico: due demoni insieme (il caso classico e' mako, che CachyOS installa con
# cachyos-hyprland-settings) se lo contendono e vince chi parte primo, quindi le
# notifiche finiscono a caso in uno dei due. sistema/bonifica.sh disinstalla
# mako proprio per questo — non basta non avviarlo, perche' e' attivabile via
# dbus e la prima notifica lo risveglia da sola.

set -u

if command -v swaync >/dev/null 2>&1; then
    exec swaync
fi

# Nessun notify-send qui: senza demone non lo vedrebbe nessuno. Il messaggio va
# nel log di Hyprland, che e' l'unico posto dove qualcuno andra' a guardare.
echo "notifiche: swaync non installato — nessuna notifica sara' visibile." >&2
echo "notifiche: rimedio -> ./installa-tutto.sh, oppure pacman -S swaync" >&2
exit 1
