#!/usr/bin/env bash
#
# bonifica.sh — toglie di mezzo cio' che litiga con questa configurazione.
#
#   sudo ./sistema/bonifica.sh            applica
#   sudo ./sistema/bonifica.sh --prova    dice cosa farebbe, senza toccare nulla
#
# Idempotente. Questo script non scrive MAI dentro una home.
#
# DA DOVE NASCE
# L'edizione Hyprland dell'installatore CachyOS tira dentro
# cachyos-hyprland-settings, che porta una configurazione completa e concorrente
# a questa: mako, wofi, wlogout, una waybar sua, swaylock-effects,
# polkit-kde-agent, network-manager-applet, kvantum, un tema Nord, un tema
# cursore.
#
# Quasi tutta quella roba e' innocua, ma per un motivo preciso: non la avvia
# nessuno. hyprland.lua lancia hyprpolkitagent e non polkit-kde-agent; il README
# rifiuta il tray, quindi network-manager-applet resta fermo; i config in
# ~/.config li sposta da parte installa.sh. Quindi non si disinstalla: rimuovere
# cachyos-hyprland-settings puo' far cadere a cascata pacchetti che servono, e
# lasciare inerte cio' che e' inerte costa zero.
#
# L'ECCEZIONE E' MAKO, e vale la pena capire perche'.
# org.freedesktop.Notifications e' un nome dbus unico: due demoni non possono
# tenerlo insieme, vince chi arriva primo. E mako e' ATTIVABILE VIA DBUS, cioe'
# ha un file .service che dice a dbus di lanciarlo su richiesta. Non basta non
# metterlo in autostart: la prima notifica che arriva prima che swaync sia su lo
# risveglia, e da quel momento le notifiche finiscono in un demone senza
# pannello, con i colori sbagliati, e swaync sembra rotto. L'unico modo per
# chiudere la faccenda e' disinstallarlo.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

AZIONE="${1:-applica}"
[ "$AZIONE" = "--prova" ] && PROVA=1

serve_root "$AZIONE"
command -v pacman >/dev/null || { errore "pacman non c'e': non e' un sistema Arch."; exit 1; }

# ------------------------------------------------------------------- 1. mako
if pacman -Q mako >/dev/null 2>&1; then
    echo ">> rimuovo mako (conflitto dbus con swaync)"
    # -Rdd e no: si vuole che pacman si lamenti se qualcosa dipende davvero da
    # mako, invece di sfondare le dipendenze in silenzio.
    if [ "$PROVA" = 1 ]; then
        echo "   [prova] pacman -Rns --noconfirm mako"
    elif ! pacman -Rns --noconfirm mako; then
        giallo "   mako non si e' potuto rimuovere: qualcosa dipende da lui."
        giallo "   Guarda con:  pacman -Qi mako | grep 'Required By'"
        giallo "   Finche' resta, le notifiche possono finire nel demone"
        giallo "   sbagliato. Non e' fatale, ma va risolto."
    fi
else
    verde ">> mako non c'e': niente da fare"
fi

# ------------------------------------ 2. cosa e' rimasto in giro, e perche' va bene
# Non si tocca: si elenca. Serve a non farsi domande fra sei mesi trovando wofi
# installato e non ricordando se serviva.
titolo "Cosa ha lasciato l'installatore di CachyOS"

inerti=()
for p in wofi wlogout swaybg swaylock-effects bemenu grimblast \
         polkit-kde-agent network-manager-applet kvantum qt5ct \
         cachyos-nord-gtk-theme capitaine-cursors; do
    pacman -Q "$p" >/dev/null 2>&1 && inerti+=("$p")
done

if [ "${#inerti[@]}" -eq 0 ]; then
    verde "  niente: installazione pulita"
else
    echo "  Installati ma inerti — nessuno li avvia, quindi restano dove sono:"
    printf '    · %s\n' "${inerti[@]}"
    echo
    echo "  Se un giorno volessi fare pulizia: pacman -Rns <nome>. Occhio pero'"
    echo "  che potrebbero essere dipendenze di cachyos-hyprland-settings, e"
    echo "  toglierne uno puo' portarsi via meta' meta-pacchetto."
fi

# ----------------------------------------------------- 3. il secondo portachiavi
# kwalletd6 arriva come dipendenza dei pacchetti KDE (polkit-kde-agent, per
# dirne uno). Se gira in una sessione che non e' KDE, certe app chiedono la
# password del wallet ad OGNI avvio, anche con gnome-keyring gia' sbloccato:
# il sintomo e' "mi richiede sempre la password" e nessuno lo collega a KDE.
if pacman -Q kwallet kwallet6 kwalletmanager >/dev/null 2>&1 \
   || command -v kwalletd6 >/dev/null 2>&1; then
    echo
    giallo "  ATTENZIONE: c'e' KWallet installato."
    giallo "  Questo setup usa gnome-keyring come Secret Service (e' quello che"
    giallo "  sistema/pam-gnome-keyring.sh sblocca al login). Se kwalletd6 parte"
    giallo "  accanto, certe app chiedono la password del wallet ad ogni avvio"
    giallo "  anche col portachiavi gia' sbloccato."
    giallo
    giallo "  Non lo tolgo da qui perche' e' dipendenza di pacchetti KDE. Se il"
    giallo "  sintomo si presenta, il rimedio e' disattivarne l'avvio:"
    giallo "    systemctl --user mask plasma-kwallet-pam.service"
fi

echo
verde "Bonifica finita."
