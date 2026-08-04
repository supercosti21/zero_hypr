# comune.sh — funzioni condivise. Si include con `source`, non si lancia.
#
# Le tiene insieme perche' installa-tutto.sh, verifica.sh e gli script di
# sistema/ stampano tutti nello stesso modo, e perche' il dry-run deve
# comportarsi identico ovunque: un `--prova` che in uno script salta un comando
# e in un altro no e' peggio di non averlo.
#
# NON la includono installa.sh, greeter-ly.sh e pam-gnome-keyring.sh: quei tre
# funzionano, sono lanciabili da soli e hanno gia' le loro copie di queste
# funzioni. Riscriverli per centralizzare trenta righe sarebbe rischio senza
# guadagno.

# --- colori ---------------------------------------------------------------
# Se stdout non e' un terminale (log, pipe, systemd) niente sequenze di
# escape: in un file di log si vedrebbero come spazzatura.
if [ -t 1 ]; then
    _c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
else
    _c() { printf '%s\n' "$2"; }
fi

# Il "${1:-}" non e' pignoleria: chiamarle senza argomenti per stampare una riga
# vuota e' naturale in mezzo a un blocco di avvisi, e con `set -u` (che hanno
# tutti gli script qui) un $1 non definito farebbe morire lo script proprio
# mentre sta spiegando all'utente cosa e' andato storto.
azzurro() { _c 36 "${1:-}"; }
giallo()  { _c 33 "${1:-}"; }
verde()   { _c 32 "${1:-}"; }
rosso()   { _c 31 "${1:-}"; }

# Gli errori vanno su stderr, altrimenti spariscono in un `| tee` distratto.
errore()  { rosso "${1:-}" >&2; }

titolo() {
    echo
    azzurro "── $* ─────────────────────────────────────────────────"
}

# --- dry-run ----------------------------------------------------------------
# Stessa forma di installa.sh, cosi' chi ha letto quello ha gia' letto questo.
PROVA="${PROVA:-0}"

fai() {
    if [ "$PROVA" = 1 ]; then
        echo "   [prova] $*"
    else
        "$@"
    fi
}

# Legge un file-elenco (un pacchetto per riga, # per i commenti) su stdout.
# Uso:  mapfile -t pacchetti < <(elenco "$REPO/pacchetti/base.txt")
elenco() {
    [ -f "$1" ] || { errore "elenco mancante: $1"; return 1; }
    grep -vE '^[[:space:]]*(#|$)' "$1" | tr -d '[:blank:]'
}

# --- guardie ------------------------------------------------------------------
# Gli script di sistema/ girano come root e non devono MAI scrivere in una home:
# un file di root dentro ~/.config rompe matugen in silenzio.
serve_root() {
    [ "$(id -u)" = "0" ] || {
        errore "Serve root: sudo $0 $*"
        exit 1
    }
}

vieta_root() {
    [ "$(id -u)" != "0" ] || {
        errore "Non lanciarlo con sudo: creerebbe file di root dentro la home."
        errore "Lancialo da utente normale."
        exit 1
    }
}
