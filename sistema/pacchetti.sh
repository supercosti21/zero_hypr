#!/usr/bin/env bash
#
# pacchetti.sh — installa l'ambiente da pacchetti/base.txt.
#
#   sudo ./sistema/pacchetti.sh            aggiorna il sistema e installa
#   sudo ./sistema/pacchetti.sh --prova    dice cosa farebbe, senza toccare nulla
#
# Idempotente: `--needed` salta cio' che c'e' gia'.
# Questo script non scrive MAI dentro una home.
#
# DUE SCELTE CHE VALE LA PENA SPIEGARE
#
# 1. `pacman -Syu`, mai `-Sy`. Gli aggiornamenti parziali non sono supportati su
#    Arch e derivate: installare pacchetti nuovi contro un database sincronizzato
#    a meta' e' il modo classico per ritrovarsi con librerie disallineate. Se
#    l'aggiornamento tocca il kernel lo si dice a fine corsa, perche' i moduli
#    dkms sono stati compilati per il kernel NUOVO mentre in esecuzione c'e'
#    ancora quello vecchio: finche' non si riavvia, la NVIDIA non funziona ed e'
#    normale.
#
# 2. I nomi si validano PRIMA con `pacman -Si`. Un solo nome sbagliato in una
#    transazione da sessanta pacchetti la fa abortire tutta, e pacman dice solo
#    "target not found: <nome>" senza installare niente. Meglio installare i
#    cinquantanove buoni e stampare in rosso l'unico da correggere.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

ELENCO="$REPO/pacchetti/base.txt"
[ "${1:-}" = "--prova" ] && PROVA=1

serve_root "${1:-}"
command -v pacman >/dev/null || { errore "pacman non c'e': non e' un sistema Arch."; exit 1; }

mapfile -t voluti < <(elenco "$ELENCO")
[ "${#voluti[@]}" -gt 0 ] || { errore "$ELENCO e' vuoto."; exit 1; }

echo "Elenco: $ELENCO (${#voluti[@]} pacchetti)"

# --- 1. aggiornamento completo -------------------------------------------------
kernel_prima="$(pacman -Q linux-cachyos linux 2>/dev/null | tr '\n' ' ' || true)"

if [ "$PROVA" = 1 ]; then
    echo "   [prova] pacman -Syu --noconfirm"
else
    echo ">> aggiorno il sistema (pacman -Syu)"
    pacman -Syu --noconfirm
fi

# --- 2. cosa manca davvero -----------------------------------------------------
# Si separa "gia' installato" da "da installare" solo per avere un riepilogo
# leggibile: a installare ci pensa comunque --needed.
gia=() mancanti=()
for p in "${voluti[@]}"; do
    if pacman -Q "$p" >/dev/null 2>&1; then gia+=("$p"); else mancanti+=("$p"); fi
done

echo ">> gia' installati: ${#gia[@]} — da installare: ${#mancanti[@]}"

if [ "${#mancanti[@]}" -eq 0 ]; then
    verde "Niente da fare: ci sono tutti."
    exit 0
fi

# --- 3. validazione dei nomi ---------------------------------------------------
# `pacman -Si` interroga i repo sincronizzati. In --prova il database potrebbe
# non essere aggiornato, e va bene lo stesso: qui interessa sapere se il NOME
# esiste, non quale versione.
echo ">> controllo i nomi nei repo ufficiali"
installabili=() introvabili=()
for p in "${mancanti[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1; then installabili+=("$p"); else introvabili+=("$p"); fi
done

# --- 4. installazione ----------------------------------------------------------
if [ "${#installabili[@]}" -gt 0 ]; then
    if [ "$PROVA" = 1 ]; then
        echo "   [prova] pacman -S --needed --noconfirm ${installabili[*]}"
    else
        echo ">> installo ${#installabili[@]} pacchetti"
        pacman -S --needed --noconfirm "${installabili[@]}"
    fi
fi

# --- 5. il rapporto ------------------------------------------------------------
if [ "${#introvabili[@]}" -gt 0 ]; then
    echo
    rosso "NON TROVATI NEI REPO UFFICIALI (${#introvabili[@]}):"
    printf '  · %s\n' "${introvabili[@]}"
    rosso "Controlla il nome — potrebbe essere stato rinominato o sostituito."
    rosso "NON installarli dall'AUR: questo setup sta nei repo ufficiali di"
    rosso "proposito, cosi' un aggiornamento di sistema non puo' romperlo."
    echo
    # Non e' un errore fatale: il resto e' stato installato e ha senso
    # proseguire. Chi orchestra decide, guardando questo codice di uscita.
    exit 3
fi

if [ "$PROVA" = 0 ]; then
    kernel_dopo="$(pacman -Q linux-cachyos linux 2>/dev/null | tr '\n' ' ' || true)"
    if [ "$kernel_prima" != "$kernel_dopo" ]; then
        echo
        giallo "Il kernel e' stato aggiornato in questa passata."
        giallo "I moduli dkms (NVIDIA) sono compilati per il kernel NUOVO, ma in"
        giallo "esecuzione c'e' ancora il vecchio: fino al riavvio la scheda"
        giallo "discreta non funziona, ed e' normale. Non e' un guasto."
    fi
fi

verde "Pacchetti a posto."
