#!/usr/bin/env bash
#
# udev.sh — installa le regole udev, il binario del profilo energetico e il suo
#           servizio, e POI controlla che abbiano funzionato davvero.
#
#   sudo ./sistema/udev.sh            applica
#   sudo ./sistema/udev.sh --prova    dice cosa farebbe, senza toccare nulla
#   sudo ./sistema/udev.sh --annulla  toglie tutto quello che ha messo
#
# Idempotente. Questo script non scrive MAI dentro una home.
#
# PERCHE' IL CONTROLLO FINALE CONTA
# 72-gpu.rules crea /dev/dri/igpu e /dev/dri/dgpu, e hyprland.lua li passa ad
# aquamarine con AQ_DRM_DEVICES. Se quei symlink non ci sono, Hyprland non parte
# affatto: muore con "Found no gpus to use" e ti lascia davanti a un cursore che
# lampeggia. Finora le regole si copiavano a mano e nessuno controllava. Fra
# accorgersene qui e accorgersene al primo login c'e' la differenza fra una
# correzione da cinque secondi e mezz'ora a capire cosa e' successo.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

AZIONE="${1:-applica}"
[ "$AZIONE" = "--prova" ] && PROVA=1

DEST_REGOLE=/etc/udev/rules.d
DEST_BIN=/usr/local/bin/power-profile-auto
DEST_UNIT=/etc/systemd/system/power-profile-auto.service

serve_root "$AZIONE"

# ---------------------------------------------------------------- annulla
if [ "$AZIONE" = "--annulla" ]; then
    systemctl disable --now power-profile-auto.service 2>/dev/null || true
    for f in "$QUI"/udev/*.rules; do
        rm -fv "$DEST_REGOLE/$(basename "$f")"
    done
    rm -fv "$DEST_BIN" "$DEST_UNIT"
    systemctl daemon-reload
    udevadm control --reload-rules
    verde "Rimosso. I symlink /dev/dri/igpu e dgpu spariscono al prossimo avvio."
    exit 0
fi

# ------------------------------------------------- 1. sintassi, prima di copiare
# udevadm verify esiste da systemd 250. Se non c'e', si tira avanti: e' un
# controllo in piu', non un requisito.
if udevadm verify --help >/dev/null 2>&1; then
    echo ">> controllo la sintassi delle regole"
    for f in "$QUI"/udev/*.rules; do
        udevadm verify "$f" >/dev/null || {
            errore "regola non valida: $f"
            udevadm verify "$f" || true
            exit 1
        }
    done
else
    giallo ">> udevadm verify non disponibile, salto il controllo di sintassi"
fi

# ------------------------------------------------------------- 2. i file
echo ">> installo le regole udev in $DEST_REGOLE"
for f in "$QUI"/udev/*.rules; do
    fai install -Dm 644 "$f" "$DEST_REGOLE/$(basename "$f")"
done

echo ">> installo $DEST_BIN"
fai install -Dm 755 "$QUI/bin/power-profile-auto" "$DEST_BIN"

echo ">> installo $DEST_UNIT"
fai install -Dm 644 "$QUI/systemd/power-profile-auto.service" "$DEST_UNIT"

# --------------------------------------------------------- 3. servizio e ricarica
if [ "$PROVA" = 0 ]; then
    systemctl daemon-reload
    # --now applica subito il profilo giusto, senza aspettare un riavvio.
    # Non e' rischioso: al massimo cambia il governor della CPU.
    systemctl enable --now power-profile-auto.service
else
    echo "   [prova] systemctl daemon-reload"
    echo "   [prova] systemctl enable --now power-profile-auto.service"
fi

echo ">> ricarico udev"
fai udevadm control --reload-rules
fai udevadm trigger --subsystem-match=drm --subsystem-match=power_supply

# ----------------------------------------------------------- 4. ha funzionato?
if [ "$PROVA" = 1 ]; then
    echo "   [prova] (qui controllerei /dev/dri/igpu e /dev/dri/dgpu)"
    exit 0
fi

echo
echo "--- controllo ---"
esito=0

for s in /dev/dri/igpu /dev/dri/dgpu; do
    if [ -e "$s" ]; then
        verde "  ok      $s -> $(readlink -f "$s")"
    else
        rosso "  manca   $s"
        esito=1
    fi
done

if [ "$esito" != 0 ]; then
    echo
    giallo "I symlink delle GPU non ci sono. Senza, Hyprland non parte:"
    giallo "muore con 'Found no gpus to use'."
    giallo
    giallo "Puo' essere normale se le schede non erano collegate al momento del"
    giallo "trigger: ricompaiono al prossimo avvio. Se nemmeno allora, gli"
    giallo "indirizzi PCI scritti in sistema/udev/72-gpu.rules non corrispondono"
    giallo "piu' a questa macchina. Quelli veri li dice:"
    giallo
    giallo "    lspci -D | grep -E 'VGA|3D'"
    giallo
    giallo "e vanno riportati nelle due righe KERNELS==\"...\" della regola."
fi

if [ -x "$DEST_BIN" ]; then
    verde "  ok      $DEST_BIN"
else
    rosso "  manca   $DEST_BIN"
    esito=1
fi

if systemctl is-enabled --quiet power-profile-auto.service 2>/dev/null; then
    profilo="$(powerprofilesctl get 2>/dev/null || echo '?')"
    verde "  ok      power-profile-auto.service (profilo adesso: $profilo)"
else
    rosso "  manca   power-profile-auto.service non abilitato"
    esito=1
fi

exit "$esito"
