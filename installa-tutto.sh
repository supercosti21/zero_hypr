#!/usr/bin/env bash
#
# installa-tutto.sh — da CachyOS appena installato a questo desktop, in un colpo.
#
#   ./installa-tutto.sh           fa tutto (chiede la password sudo UNA volta)
#   ./installa-tutto.sh --prova   dice cosa farebbe, senza toccare niente
#
# Idempotente: rilanciarlo su un sistema gia' a posto non fa danni e non cambia
# nulla. Serve anche a questo — e' il modo per riportare la macchina in riga
# dopo aver smanettato.
#
# SI LANCIA DA UTENTE NORMALE, MAI CON SUDO.
# I passi che servono root sono script separati in sistema/, lanciati uno per
# uno con sudo. Se girasse tutto come root, i symlink e i file di colore
# finirebbero di proprieta' di root dentro ~/.config: il desktop partirebbe lo
# stesso, ma matugen non potrebbe piu' riscrivere la palette al cambio sfondo, e
# fallirebbe in silenzio. Nessuno script sotto sistema/ scrive dentro una home.
#
# L'ORDINE NON E' CASUALE
# I pacchetti prima dei collegamenti, altrimenti si seminano file di colore per
# programmi che non ci sono. Il greeter per ULTIMO, perche' e' l'unica cosa che
# puo' impedirti di fare login al prossimo avvio: se qualcosa va storto prima,
# la schermata di accesso non e' mai stata toccata e la macchina resta
# raggiungibile.

set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=comune.sh
source "$REPO/comune.sh"

[ "${1:-}" = "--prova" ] && PROVA=1
ARG=(); [ "$PROVA" = 1 ] && ARG=(--prova)

# Un passo che va storto non deve fermare tutto: quasi sempre gli altri hanno
# comunque senso, e fermarsi a meta' lascia una macchina in uno stato peggiore
# di quella di partenza. Si segna e si va avanti, e il riepilogo lo dice.
guai=()

passo() { # passo <numero/totale> <titolo> <comando...>
    local etichetta="$1"; shift
    local nome="$1"; shift
    titolo "$etichetta  $nome"

    # `uscita=0; cmd || uscita=$?` e non `if cmd; then ... fi; uscita=$?`:
    # dopo un `if` senza else, $? e' lo stato del costrutto if — che vale 0
    # anche quando la condizione e' fallita. Con quella forma ogni passo andato
    # storto veniva riportato come "uscito con 0".
    local uscita=0
    "$@" || uscita=$?

    [ "$uscita" = 0 ] && return 0

    giallo "!! \"$nome\" e' uscito con $uscita — vado avanti col resto"
    guai+=("$nome (uscita $uscita)")
    return 0
}

# ============================================================ 0. controlli
titolo "0/10  Controlli preliminari"

vieta_root

if ! command -v pacman >/dev/null 2>&1; then
    errore "pacman non c'e': questo script e' per CachyOS (o comunque Arch)."
    exit 1
fi
verde "  ok      pacman"

if ! command -v sudo >/dev/null 2>&1; then
    errore "sudo non c'e'. Installalo e aggiungi il tuo utente al gruppo wheel."
    exit 1
fi
verde "  ok      sudo"

# Non e' l'unico modo di avere i privilegi, ma e' quello standard: se non c'e',
# meglio dirlo adesso che a meta' installazione, davanti a una richiesta di
# password che non verra' mai accettata.
if id -nG 2>/dev/null | grep -qw wheel; then
    verde "  ok      sei nel gruppo wheel"
else
    giallo "  guarda  non sei nel gruppo wheel: sudo potrebbe rifiutarti."
    # id -un e non $USER: quella variabile non e' garantita — manca sotto cron,
    # dentro `su` senza -l, e in qualsiasi ambiente ripulito. Con set -u
    # ucciderebbe lo script proprio mentre sta dando un consiglio.
    giallo "          Da un utente che puo': usermod -aG wheel $(id -un)"
fi

# Senza rete non si va da nessuna parte, e scoprirlo al primo `pacman -Syu`
# vuol dire aver gia' chiesto la password per niente.
if [ "$PROVA" = 0 ]; then
    if ping -c1 -W3 archlinux.org >/dev/null 2>&1 \
       || ping -c1 -W3 1.1.1.1 >/dev/null 2>&1; then
        verde "  ok      rete"
    else
        errore "Nessuna rete: i pacchetti non si possono scaricare."
        errore "Collega il cavo, o il wi-fi con:  nmcli device wifi connect <rete>"
        exit 1
    fi
fi

for f in installa.sh verifica.sh pacchetti/base.txt sistema/pacchetti.sh; do
    [ -e "$REPO/$f" ] || { errore "Manca $f: il clone e' incompleto?"; exit 1; }
done
verde "  ok      il repo e' completo"

# ================================================ una password sola, poi basta
# `sudo -v` aggiorna il timestamp; il ciclo in sottofondo lo tiene vivo mentre i
# pacchetti si scaricano, cosi' non ti ritrovi una richiesta di password a meta'
# strada su un terminale che nel frattempo hai lasciato. Niente NOPASSWD, niente
# modifiche a /etc/sudoers: quando lo script finisce, non resta niente.
if [ "$PROVA" = 0 ]; then
    echo
    azzurro "Serve la password di sudo. Viene chiesta una volta sola."
    sudo -v

    ( while true; do sleep 50; sudo -n true 2>/dev/null || exit; done ) &
    keepalive=$!
    trap 'kill "$keepalive" 2>/dev/null || true; sudo -k 2>/dev/null || true' EXIT
fi

SUDO=(sudo)
[ "$PROVA" = 1 ] && SUDO=()   # in prova non si chiede niente a nessuno

# ============================================================ ritocchi utente
# Definita qui e non piu' in basso: in bash una funzione deve esistere PRIMA
# della riga che la chiama, e i passi cominciano subito sotto.
finiture_utente() {
    # Le cartelle standard: hyprshot salva in ~/Pictures, che su una macchina
    # appena installata non esiste. Il sintomo sarebbe "il tasto Stamp non fa
    # niente", che non porta da nessuna parte.
    if command -v xdg-user-dirs-update >/dev/null 2>&1; then
        fai xdg-user-dirs-update
    fi
    fai mkdir -p "$HOME/Pictures"

    # Primo sfondo e prima palette vera. Senza, si resta sui semi: colori
    # plausibili ma non tuoi, e uno sfondo nero.
    if [ "$PROVA" = 1 ]; then
        echo "   [prova] scelta del primo sfondo e generazione della palette"
        return 0
    fi

    local sfondo="$HOME/.config/hypr/scripts/sfondo.sh"
    [ -x "$sfondo" ] || return 0

    # --primo sceglie da solo, senza aprire nessun menu: qui non c'e' nessuno a
    # cui chiedere. E non tocca niente se uno sfondo e' gia' impostato.
    "$sfondo" --primo \
        || giallo "   sfondo iniziale non impostato: premi SUPER+W dopo il login"
}

# ============================================================== i dieci passi
passo "1/10" "Bonifica"            "${SUDO[@]}" "$REPO/sistema/bonifica.sh"   "${ARG[@]}"
passo "2/10" "Pacchetti"           "${SUDO[@]}" "$REPO/sistema/pacchetti.sh"  "${ARG[@]}"
passo "3/10" "GPU NVIDIA"          "${SUDO[@]}" "$REPO/sistema/gpu-nvidia.sh" "${ARG[@]}"
passo "4/10" "udev ed energia"     "${SUDO[@]}" "$REPO/sistema/udev.sh"       "${ARG[@]}"
passo "5/10" "Servizi"             "${SUDO[@]}" "$REPO/sistema/servizi.sh"    "${ARG[@]}"
passo "6/10" "Portachiavi"         "${SUDO[@]}" "$REPO/sistema/pam-gnome-keyring.sh" "${ARG[@]}"

# Da qui in poi si torna utente normale: e' roba che sta dentro la home.
passo "7/10" "Collegamenti"        "$REPO/installa.sh" "${ARG[@]}"
passo "8/10" "Ritocchi"            finiture_utente

passo "9/10" "Schermata di accesso" "${SUDO[@]}" "$REPO/sistema/greeter-ly.sh" "${ARG[@]}"

# ============================================================ 10. verifica
titolo "10/10  Verifica"
if [ "$PROVA" = 1 ]; then
    echo "   [prova] ./verifica.sh"
else
    "$REPO/verifica.sh" --breve || true
fi

# ============================================================== riepilogo
echo
if [ "${#guai[@]}" -gt 0 ]; then
    giallo "Passi che non sono andati lisci:"
    printf '  · %s\n' "${guai[@]}"
    echo
fi

if [ "$PROVA" = 1 ]; then
    azzurro "Era una prova: non e' stato toccato niente."
    azzurro "Per farlo davvero:  ./installa-tutto.sh"
    exit 0
fi

cat <<'FINE'
────────────────────────────────────────────────────────────────────────
Cosa resta a te:

  1. RIAVVIA.
         systemctl reboot

     Non fermo la schermata di accesso da qui: la sessione aperta e'
     figlia sua e morirebbe insieme a lei. Il riavvio serve anche se in
     questa passata si e' aggiornato il kernel — i moduli NVIDIA sono
     compilati per quello NUOVO, mentre in esecuzione c'e' ancora il
     vecchio.

  2. Al riavvio compare ly. Scegli la sessione Hyprland e accedi.

  3. Al primo accesso il portachiavi viene creato con la tua password:
     e' normale che non chieda niente in piu'.

  4. SUPER+W per cambiare sfondo — e con lui barra, launcher, notifiche,
     terminale e schermata di blocco.
     SUPER+R per il launcher, che e' anche il centro di controllo.

Per rivedere com'e' messo il sistema, quando vuoi:   ./verifica.sh

SE AL RIAVVIO NON COMPARE NESSUNA SCHERMATA DI ACCESSO:
Ctrl+Alt+F3 apre un login testuale su un terminale libero. Da li':
    sudo ./sistema/greeter-ly.sh --annulla
    systemctl reboot
e torni alla schermata di prima.
────────────────────────────────────────────────────────────────────────
FINE
