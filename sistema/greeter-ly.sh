#!/usr/bin/env bash
#
# greeter-ly.sh — sostituisce cosmic-greeter con ly alla schermata di accesso.
#
#   sudo ./sistema/greeter-ly.sh            applica
#   sudo ./sistema/greeter-ly.sh --stato    mostra la situazione, non tocca nulla
#   sudo ./sistema/greeter-ly.sh --annulla  rimette cosmic-greeter
#
# COSA FA
# 1. installa `ly` (repo ufficiali, niente AUR)
# 2. mette `numlock = true` in /etc/ly/config.ini, cosi' il tastierino numerico
#    scrive cifre gia' alla schermata di accesso
# 3. disabilita cosmic-greeter.service e abilita ly@tty1.service
#
# PERCHE' tty1
# ly 1.4 non ha piu' un servizio singolo ma un modello, `ly@.service`: il pezzo
# dopo la @ e' il terminale virtuale su cui si mette. cosmic-greeter oggi sta su
# tty1 (`Conflicts=getty@tty1.service`, e /etc/greetd/config.toml dice `vt = 1`),
# quindi tty1 lascia l'avvio identico a com'e' adesso: si accende e la schermata
# di accesso e' li', senza cambi di terminale. Il `Conflicts=getty@%i.service`
# dentro ly@.service si occupa da solo di togliere di mezzo il getty su tty1,
# esattamente come faceva cosmic-greeter.
#
# COSA NON CAMBIA
# - Le sessioni restano quelle in /usr/share/wayland-sessions: ly le legge da
#   sola, quindi Hyprland e COSMIC restano entrambi scegliibili dal menu.
#   COSMIC non viene toccato: si disabilita solo il suo *greeter*.
# - Il portachiavi continua a funzionare: /etc/pam.d/ly include
#   system-local-login -> system-login, che e' dove sta pam_gnome_keyring.
#
# NON RIAVVIA NIENTE ADESSO. Fermare cosmic-greeter mentre ci sei dentro
# significa ammazzare la sessione in corso: qui si cambia solo cosa parte al
# prossimo avvio.

set -euo pipefail

CONF=/etc/ly/config.ini
TTY=tty1
AZIONE="${1:-applica}"

# Elenca ogni ly@<qualcosa> abilitato. Serve perche' il modello puo' essere
# abilitato su piu' terminali insieme senza che nessun comando se ne lamenti.
ly_abilitati() {
    ls -1 /etc/systemd/system/multi-user.target.wants/ 2>/dev/null \
        | grep '^ly@' || true
}

stato() {
    echo "--- chi parte al prossimo avvio ---"
    for u in cosmic-greeter.service "ly@$TTY.service"; do
        printf '  %-26s %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1)"
    done
    dm=/etc/systemd/system/display-manager.service
    printf '  %-26s %s\n' "display-manager.service" \
        "$([ -L "$dm" ] && readlink -f "$dm" || echo '(nessuno)')"
    altri=$(ly_abilitati | grep -v "^ly@$TTY.service$" || true)
    [ -n "$altri" ] && printf '  ATTENZIONE, altri ly@ abilitati: %s\n' "$(echo $altri)"
    if [ -f "$CONF" ]; then
        echo "--- $CONF ---"
        grep -n '^numlock' "$CONF" | sed 's/^/  /' || echo "  (nessuna riga numlock)"
    fi
    return 0
}

# --stato e' sola lettura, non serve root.
if [ "$AZIONE" = "--stato" ]; then
    stato
    exit 0
fi

[ "$(id -u)" = "0" ] || { echo "Serve root: sudo $0 $AZIONE" >&2; exit 1; }

# --- annulla -----------------------------------------------------------------
if [ "$AZIONE" = "--annulla" ]; then
    for u in $(ly_abilitati); do systemctl disable "$u" || true; done
    systemctl enable cosmic-greeter.service
    echo "Rimesso cosmic-greeter. Riavvia per vederlo."
    stato
    exit 0
fi

# --- 1. installa ly -----------------------------------------------------------
if ! pacman -Q ly >/dev/null 2>&1; then
    echo ">> installo ly"
    pacman -S --needed --noconfirm ly
else
    echo ">> ly gia' installato: $(pacman -Q ly)"
fi

[ -f "$CONF" ] || { echo "Manca $CONF — l'installazione di ly non e' andata come previsto." >&2; exit 1; }

# --- 2. numlock acceso --------------------------------------------------------
# Il file e' un .ini con `chiave = valore`. Se la riga c'e' la si riscrive, se
# non c'e' la si aggiunge in fondo: rilanciare lo script non duplica nulla.
if ! grep -q '^numlock *= *true' "$CONF"; then
    backup="$CONF.backup-$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONF" "$backup"
    if grep -q '^ *numlock *=' "$CONF"; then
        sed -i 's/^ *numlock *=.*/numlock = true/' "$CONF"
    else
        printf '\n# Bloc Num acceso all\x27avvio della schermata di accesso.\nnumlock = true\n' >> "$CONF"
    fi
    echo ">> $CONF: numlock = true (backup: $backup)"
else
    echo ">> $CONF: numlock era gia' true"
fi

# --- 3. scambio dei servizi ---------------------------------------------------
# `disable` di cosmic-greeter toglie anche il collegamento
# display-manager.service, che punta a lui. ly non usa quel nome: il suo unit
# non ha nessun Alias, si aggancia direttamente a multi-user.target.
echo ">> disabilito cosmic-greeter.service"
systemctl disable cosmic-greeter.service

echo ">> abilito ly@$TTY.service"
systemctl enable "ly@$TTY.service"

# Su questa macchina l'installatore di CachyOS aveva lasciato `ly@tty2.service`
# abilitato dal 20/06 pur senza il pacchetto ly: un collegamento verso un unit
# inesistente, che non dava fastidio a nessuno. Installando ly diventa vivo, e
# al riavvio partirebbero DUE schermate di accesso, una per terminale — con in
# piu' il guaio che tty2 e' proprio il terminale di scorta a cui si ricorre se
# quella su tty1 non parte. `systemctl enable` non se ne lamenta: il modello
# puo' legittimamente stare su piu' terminali. Quindi si controlla a mano.
for u in $(ly_abilitati | grep -v "^ly@$TTY.service$" || true); do
    echo ">> tolgo $u (ne basta uno, e tty2 deve restare libero come scorta)"
    systemctl disable "$u"
done

echo
stato
cat <<FINE

Fatto. Adesso serve un riavvio: non fermo cosmic-greeter da qui perche'
la sessione aperta e' figlia sua e morirebbe insieme a lui.

    systemctl reboot

SE AL RIAVVIO LA SCHERMATA NON APPARE: passa a un terminale libero con
Ctrl+Alt+F3, dove logind fa comparire un login testuale a richiesta. Da li':
    sudo $(readlink -f "$0") --annulla
    systemctl reboot
e torni a cosmic-greeter.
FINE
