#!/usr/bin/env bash
#
# installa.sh — collega questo repo a ~/.config.
#
# Il repo NON copia i file in ~/.config: crea dei symlink. Cosi' modificare un
# config e fare `git diff` sono la stessa cosa, e non esiste il rischio di
# lavorare per mezz'ora sulla copia sbagliata.
#
#   ./installa.sh            crea i symlink (salva cio' che trova)
#   ./installa.sh --prova    dice cosa farebbe, senza toccare nulla
#
# Idempotente: rilanciarlo su un sistema gia' a posto non fa danni.
#
# Per l'installazione completa (pacchetti, driver, /etc) c'e' installa-tutto.sh,
# che chiama anche questo script. Qui restano solo i symlink.

set -euo pipefail

# Mai con sudo: i symlink e i file di colore finirebbero di proprieta' di root
# dentro ~/.config. Il desktop partirebbe lo stesso, ma matugen non potrebbe piu'
# riscrivere la palette al cambio sfondo — e fallirebbe in silenzio, che e' il
# modo peggiore. installa-tutto.sh usa sudo solo sugli script di sistema/.
if [ "$(id -u)" = "0" ]; then
    echo "Non lanciarlo con sudo: creerebbe file di root in ~/.config." >&2
    echo "Lancialo da utente normale: ./installa.sh" >&2
    exit 1
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"
PROVA=0
[ "${1:-}" = "--prova" ] && PROVA=1

# Cartelle che vengono collegate a ~/.config/<nome>
CARTELLE=(hypr waybar fuzzel swaync matugen alacritty xdg-desktop-portal)

# Singoli file, per le app la cui cartella di config e' piena di stato che non
# ha senso versionare (cache, estensioni, cronologie). Si collega solo il file
# che conta. Formato: percorso/nel/repo|percorso/sotto/.config
FILE=(
    "config/Trae/argv.json|Trae/argv.json"
)

azzurro() { printf '\033[36m%s\033[0m\n' "$1"; }
giallo()  { printf '\033[33m%s\033[0m\n' "$1"; }
verde()   { printf '\033[32m%s\033[0m\n' "$1"; }

fai() {
    if [ "$PROVA" = 1 ]; then
        echo "   [prova] $*"
    else
        "$@"
    fi
}

azzurro "repo:        $REPO"
azzurro "destinazione: $DEST"
echo

# ---------------------------------------------------------------- 1. symlink
for nome in "${CARTELLE[@]}"; do
    sorgente="$REPO/config/$nome"
    bersaglio="$DEST/$nome"

    # Cartelle non ancora presenti nel repo (es. swaync prima di configurarlo)
    [ -d "$sorgente" ] || continue

    # Gia' collegata al posto giusto: niente da fare.
    if [ -L "$bersaglio" ] && [ "$(readlink -f "$bersaglio")" = "$(readlink -f "$sorgente")" ]; then
        verde "ok       $nome (symlink gia' corretto)"
        continue
    fi

    # C'e' qualcosa d'altro: si mette da parte invece di cancellarlo. Mai
    # distruggere config di cui non si sa la provenienza.
    if [ -e "$bersaglio" ] || [ -L "$bersaglio" ]; then
        salvataggio="$bersaglio.pre-git"
        # Se un salvataggio esiste gia', non lo si sovrascrive: si numera.
        n=1
        while [ -e "$salvataggio" ]; do salvataggio="$bersaglio.pre-git.$n"; n=$((n + 1)); done
        giallo "salvo    $nome -> $(basename "$salvataggio")"
        fai mv "$bersaglio" "$salvataggio"
    fi

    azzurro "collego  $nome"
    fai mkdir -p "$DEST"
    fai ln -s "$sorgente" "$bersaglio"
done

# ------------------------------------------------------------ 1b. file singoli
for voce in "${FILE[@]}"; do
    sorgente="$REPO/${voce%%|*}"
    bersaglio="$DEST/${voce##*|}"
    nome="${voce##*|}"

    [ -f "$sorgente" ] || continue

    if [ -L "$bersaglio" ] && [ "$(readlink -f "$bersaglio")" = "$(readlink -f "$sorgente")" ]; then
        verde "ok       $nome (symlink gia' corretto)"
        continue
    fi

    if [ -e "$bersaglio" ] || [ -L "$bersaglio" ]; then
        giallo "salvo    $nome -> $(basename "$bersaglio").pre-git"
        fai mv "$bersaglio" "$bersaglio.pre-git"
    fi

    azzurro "collego  $nome"
    # La cartella dell'app puo' non esistere ancora su una macchina nuova.
    fai mkdir -p "$(dirname "$bersaglio")"
    fai ln -s "$sorgente" "$bersaglio"
done

# ------------------------------------------------- 2. semi dei file generati
# I file di colore sono in .gitignore: su una macchina nuova non esistono e
# waybar morirebbe sull'@import. Qui si mette il seme, se manca.
echo
while IFS='|' read -r seme generato; do
    [ -f "$REPO/$seme" ] || continue
    if [ -f "$REPO/$generato" ]; then
        verde "ok       $(basename "$generato") (gia' presente)"
    else
        azzurro "semino   $(basename "$generato") da $(basename "$seme")"
        fai cp "$REPO/$seme" "$REPO/$generato"
    fi
done <<'SEMI'
config/waybar/colori.default.css|config/waybar/colori.css
config/hypr/colori.default.lua|config/hypr/colori.lua
config/swaync/colori.default.css|config/swaync/colori.css
config/alacritty/colori.default.toml|config/alacritty/colori.toml
config/fuzzel/colori.default.ini|config/fuzzel/colori.ini
SEMI

# --------------------------------------------------------- 3. cosa resta a te
cat <<'FINE'

Fatto: i collegamenti a ~/.config ci sono.

Questo script, di proposito, non installa pacchetti e non tocca /etc. Se sei
su una macchina nuova manca ancora tutto il resto — pacchetti, driver NVIDIA,
regole udev, portachiavi, schermata di accesso. Fa tutto un comando solo:

    ./installa-tutto.sh --prova     dice cosa farebbe
    ./installa-tutto.sh             lo fa (chiede la password sudo una volta)

Per controllare com'e' messo il sistema in qualsiasi momento:  ./verifica.sh

FINE
