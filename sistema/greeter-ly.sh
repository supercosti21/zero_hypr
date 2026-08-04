#!/usr/bin/env bash
#
# greeter-ly.sh — mette ly come schermata di accesso, al posto di quello che c'e'.
#
#   sudo ./sistema/greeter-ly.sh            applica
#   sudo ./sistema/greeter-ly.sh --stato    mostra la situazione, non tocca nulla
#   sudo ./sistema/greeter-ly.sh --prova    come --stato (per l'orchestratore)
#   sudo ./sistema/greeter-ly.sh --annulla  rimette il display manager di prima
#
# COSA FA
# 1. installa `ly` (repo ufficiali, niente AUR)
# 2. mette `numlock = true` in /etc/ly/config.ini, cosi' il tastierino numerico
#    scrive cifre gia' alla schermata di accesso
# 3. disabilita il display manager attivo e abilita ly@tty1.service
#
# COME TROVA IL DISPLAY MANAGER ATTIVO
# Non per nome. /etc/systemd/system/display-manager.service e' un symlink al
# servizio del display manager in uso, qualunque sia: si legge dove punta e si
# disabilita quello. Prima questo script cercava "cosmic-greeter.service" scritto
# a mano, e su un'installazione dove quel servizio non esiste — per esempio
# l'edizione Hyprland di CachyOS, che usa SDDM — falliva senza aver fatto niente.
# Il nome trovato finisce in $MEMORIA, cosi' --annulla sa cosa rimettere.
#
# PERCHE' tty1
# ly 1.4 non ha piu' un servizio singolo ma un modello, `ly@.service`: il pezzo
# dopo la @ e' il terminale virtuale su cui si mette. I display manager stanno
# praticamente sempre su tty1, quindi tty1 lascia l'avvio identico a com'e'
# adesso: si accende e la schermata di accesso e' li', senza cambi di terminale.
# Il `Conflicts=getty@%i.service` dentro ly@.service si occupa da solo di
# togliere di mezzo il getty su tty1.
#
# COSA NON CAMBIA
# - Le sessioni restano quelle in /usr/share/wayland-sessions: ly le legge da
#   sola. Se un giorno affianchi un altro desktop, comparira' nel suo menu senza
#   dover toccare niente qui.
# - Il portachiavi continua a funzionare: /etc/pam.d/ly include
#   system-local-login -> system-login, che e' dove sta pam_gnome_keyring.
#
# NON RIAVVIA NIENTE ADESSO. Fermare il display manager mentre ci sei dentro
# significa ammazzare la sessione in corso: qui si cambia solo cosa parte al
# prossimo avvio.

set -euo pipefail

CONF=/etc/ly/config.ini
TTY=tty1
DM_LINK=/etc/systemd/system/display-manager.service
MEMORIA=/var/lib/zero_hypr/greeter-precedente
AZIONE="${1:-applica}"

# --prova non ha senso qui come "fai finta di": abilitare un display manager e'
# o si' o no. Vale piu' mostrare la situazione, che e' esattamente --stato.
[ "$AZIONE" = "--prova" ] && AZIONE="--stato"

# Chi e' il display manager attivo adesso. Vuoto se non ce n'e' nessuno.
dm_attuale() {
    [ -L "$DM_LINK" ] || return 0
    basename "$(readlink -f "$DM_LINK")"
}

# Elenca ogni ly@<qualcosa> abilitato. Serve perche' il modello puo' essere
# abilitato su piu' terminali insieme senza che nessun comando se ne lamenti.
ly_abilitati() {
    ls -1 /etc/systemd/system/multi-user.target.wants/ 2>/dev/null \
        | grep '^ly@' || true
}

stato() {
    echo "--- chi parte al prossimo avvio ---"
    dm="$(dm_attuale)"
    printf '  %-26s %s\n' "display-manager.service" "${dm:-(nessuno)}"
    printf '  %-26s %s\n' "ly@$TTY.service" "$(systemctl is-enabled "ly@$TTY.service" 2>&1)"

    altri=$(ly_abilitati | grep -v "^ly@$TTY.service$" || true)
    [ -n "$altri" ] && printf '  ATTENZIONE, altri ly@ abilitati: %s\n' "$(echo "$altri")"

    if [ -f "$MEMORIA" ]; then
        printf '  %-26s %s\n' "prima c'era" "$(cat "$MEMORIA")"
    fi

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

    if [ -f "$MEMORIA" ] && [ -s "$MEMORIA" ]; then
        precedente="$(cat "$MEMORIA")"
        echo ">> rimetto $precedente"
        if systemctl enable "$precedente"; then
            rm -f "$MEMORIA"
        else
            echo "Non sono riuscito ad abilitare $precedente: abilitane uno a mano," >&2
            echo "altrimenti al prossimo avvio non c'e' nessuna schermata grafica." >&2
            exit 1
        fi
    else
        echo "Non so quale display manager ci fosse prima (manca $MEMORIA)." >&2
        echo "Ne trovi uno fra quelli installati e lo abiliti a mano, per esempio:" >&2
        echo "    systemctl enable sddm.service" >&2
        exit 1
    fi

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

# --- 3. via il vecchio, dentro ly ---------------------------------------------
vecchio="$(dm_attuale)"

if [ -n "$vecchio" ] && [ "$vecchio" != "ly@$TTY.service" ]; then
    # Si annota PRIMA di disabilitare: se qualcosa va storto a meta', --annulla
    # deve comunque sapere cosa rimettere.
    mkdir -p "$(dirname "$MEMORIA")"
    echo "$vecchio" > "$MEMORIA"

    echo ">> disabilito $vecchio (annotato in $MEMORIA)"
    # `disable` toglie anche il collegamento display-manager.service, che punta
    # a lui. ly non usa quel nome: il suo unit non ha nessun Alias, si aggancia
    # direttamente a multi-user.target.
    systemctl disable "$vecchio" || {
        echo "Non sono riuscito a disabilitare $vecchio. Mi fermo qui: due" >&2
        echo "schermate di accesso insieme sono peggio di quella sbagliata." >&2
        exit 1
    }
elif [ -z "$vecchio" ]; then
    echo ">> nessun display manager attivo: c'e' solo da mettere ly"
else
    echo ">> il display manager attivo e' gia' ly"
fi

echo ">> abilito ly@$TTY.service"
systemctl enable "ly@$TTY.service"

# Un installatore puo' lasciare un `ly@ttyN.service` abilitato senza il pacchetto
# ly: un collegamento verso un unit inesistente, che non da' fastidio a nessuno.
# Installando ly diventa vivo, e al riavvio partirebbero DUE schermate di
# accesso, una per terminale — con in piu' il guaio che tty2 e' proprio il
# terminale di scorta a cui si ricorre se quella su tty1 non parte.
# `systemctl enable` non se ne lamenta: il modello puo' legittimamente stare su
# piu' terminali. Quindi si controlla a mano.
for u in $(ly_abilitati | grep -v "^ly@$TTY.service$" || true); do
    echo ">> tolgo $u (ne basta uno, e tty2 deve restare libero come scorta)"
    systemctl disable "$u"
done

echo
stato
cat <<FINE

Fatto. Adesso serve un riavvio: non fermo la schermata di accesso da qui
perche' la sessione aperta e' figlia sua e morirebbe insieme a lei.

    systemctl reboot

SE AL RIAVVIO LA SCHERMATA NON APPARE: passa a un terminale libero con
Ctrl+Alt+F3, dove logind fa comparire un login testuale a richiesta. Da li':
    sudo $(readlink -f "$0") --annulla
    systemctl reboot
e torni a com'era prima.
FINE
