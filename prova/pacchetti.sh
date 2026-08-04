#!/usr/bin/env bash
#
# pacchetti.sh — ogni nome negli elenchi esiste davvero nei repo ufficiali?
#
#   ./prova/pacchetti.sh
#
# Serve pacman e un database sincronizzato, quindi gira su Arch/CachyOS oppure
# dentro prova/Containerfile. Non installa niente e non ha bisogno di root:
# `pacman -Si` interroga soltanto.
#
# PERCHE' E' IL CONTROLLO PIU' UTILE DI TUTTI
# I nomi dei pacchetti cambiano: vengono rinominati, divisi in due, assorbiti in
# un altro. Il sintomo di un nome sbagliato non arriva qui — arriva mesi dopo,
# sul portatile, a meta' installazione, quando pacman dice "target not found" e
# abortisce l'intera transazione senza installare niente. Due minuti adesso
# valgono quella mezz'ora.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

command -v pacman >/dev/null || {
    errore "pacman non c'e'. Questa prova gira su Arch/CachyOS, oppure con:"
    errore "  podman build -f prova/Containerfile -t zero-hypr-prova ."
    errore "  podman run --rm zero-hypr-prova"
    exit 1
}

# Il database dev'essere sincronizzato, se no ogni nome risulta introvabile.
# Sincronizzare serve root, quindi qui si controlla e si dice, invece di
# fallire in un modo che sembra colpa degli elenchi.
if ! pacman -Si bash >/dev/null 2>&1; then
    errore "Il database dei pacchetti non e' sincronizzato: prima  sudo pacman -Sy"
    exit 1
fi

falliti=0

controlla_elenco() {
    local file="$1"
    titolo "$(basename "$file")"

    mapfile -t voci < <(elenco "$file")
    local introvabili=()

    for p in "${voci[@]}"; do
        pacman -Si "$p" >/dev/null 2>&1 || introvabili+=("$p")
    done

    if [ "${#introvabili[@]}" -eq 0 ]; then
        verde "  ok      tutti e ${#voci[@]} i nomi esistono nei repo ufficiali"
    else
        rosso "  ${#introvabili[@]} nomi non trovati:"
        for p in "${introvabili[@]}"; do
            # Un suggerimento vale piu' di un errore secco: quasi sempre il
            # pacchetto c'e' ancora, con un nome leggermente diverso.
            simili="$(pacman -Ss "^${p%%-*}" 2>/dev/null | grep -oE '^[a-z0-9]+/\S+' \
                      | head -3 | tr '\n' ' ')"
            printf '    · %-28s %s\n' "$p" "${simili:+forse: $simili}"
        done
        falliti=$((falliti + 1))
    fi

    # La transazione intera: due nomi giusti presi singolarmente possono essere
    # in conflitto fra loro, e questo lo si vede solo risolvendoli insieme.
    # --print scarica zero byte.
    if pacman -S --needed --print "${voci[@]}" >/dev/null 2>&1; then
        verde "  ok      la transazione si risolve senza conflitti"
    else
        rosso "  la transazione NON si risolve:"
        pacman -S --needed --print "${voci[@]}" 2>&1 | grep -iE 'error|conflict' | head -10 | sed 's/^/    /'
        falliti=$((falliti + 1))
    fi
}

controlla_elenco "$REPO/pacchetti/base.txt"
controlla_elenco "$REPO/pacchetti/nvidia.txt"

echo
if [ "$falliti" -gt 0 ]; then
    rosso "$falliti elenchi con problemi."
    rosso "Correggi i nomi in pacchetti/. NON aggiungere l'AUR: questo setup sta"
    rosso "nei repo ufficiali di proposito, cosi' un aggiornamento non lo rompe."
    exit 1
fi
verde "Gli elenchi dei pacchetti sono a posto."
