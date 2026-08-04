#!/usr/bin/env bash
#
# gpu-nvidia.sh — driver della scheda discreta: VERIFICA, non forza.
#
#   sudo ./sistema/gpu-nvidia.sh            controlla e sistema il sistemabile
#   sudo ./sistema/gpu-nvidia.sh --prova    dice cosa farebbe, senza toccare nulla
#
# Idempotente. Questo script non scrive MAI dentro una home.
#
# PERCHE' VERIFICA E NON INSTALLA
# Su CachyOS i driver NVIDIA li gestisce `chwd`, che l'installatore ha gia'
# eseguito: sceglie il profilo giusto per la scheda, tira dentro gli headers del
# kernel CachyOS in uso e configura da solo il PRIME offload. Nel caso normale
# qui non c'e' niente da fare, e installare pacchetti "a mano" sopra il suo
# lavoro e' il modo migliore per litigarci.
#
# Quello che invece manca sempre e' il controllo: nessuno verifica che il
# modesetting sia attivo, che i servizi di sospensione ci siano, che i moduli si
# siano davvero compilati per il kernel in esecuzione. Sono le tre cose che, se
# mancano, danno sintomi che nessuno collega alla causa: schermo nero al
# risveglio, sessione corrotta dopo aver chiuso il coperchio, prime-run che non
# fa niente.
#
# I flag di `chwd` sono cambiati fra le versioni, quindi non si tirano a
# indovinare: si guarda cosa c'e' gia' installato e, se manca tutto, si stampa il
# comando da lanciare invece di eseguirne uno sbagliato.

set -euo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
# shellcheck source=../comune.sh
source "$REPO/comune.sh"

AZIONE="${1:-applica}"
[ "$AZIONE" = "--prova" ] && PROVA=1

DEST_MODPROBE=/etc/modprobe.d/nvidia-risparmio.conf

serve_root "$AZIONE"

# ------------------------------------------------------- 1. c'e' una NVIDIA?
# "3D controller" e' come si presenta una discreta su un portatile ibrido; su un
# fisso sarebbe "VGA compatible controller". Si accettano entrambi.
if ! lspci -D 2>/dev/null | grep -qE '(3D controller|VGA compatible controller).*NVIDIA'; then
    giallo "Nessuna GPU NVIDIA sul bus PCI: salto tutto."
    exit 0
fi

pci_dgpu="$(lspci -D 2>/dev/null | grep -E '(3D controller|VGA compatible controller).*NVIDIA' \
            | head -n1 | cut -d' ' -f1)"
echo ">> trovata una NVIDIA su $pci_dgpu"

# --------------------------------------------------------- 2. c'e' un driver?
if pacman -Q nvidia-utils >/dev/null 2>&1; then
    echo ">> driver gia' installato: $(pacman -Q nvidia-utils)"
    driver_presente=1
else
    driver_presente=0
    giallo ">> nvidia-utils non risulta installato"

    if command -v chwd >/dev/null 2>&1; then
        echo
        giallo "Su CachyOS i driver li mette chwd, che conosce la mappa dei"
        giallo "profili e tira dentro gli headers del kernel giusto. Lancialo tu,"
        giallo "guardando cosa propone, invece di farlo fare a questo script:"
        giallo
        giallo "    sudo chwd --list-available     # cosa c'e' per questa scheda"
        giallo "    sudo chwd -a                   # installa il profilo adatto"
        giallo
        giallo "Poi rilancia questo script per il controllo."
    else
        giallo "chwd non c'e'. Ripiego su pacchetti/nvidia.txt."
        mapfile -t pkg < <(elenco "$REPO/pacchetti/nvidia.txt")

        # Gli headers servono a dkms per compilare i moduli, e ne serve uno per
        # OGNI kernel installato: se ne hai due e ne copri uno solo, l'altro
        # avvia senza scheda e sembra un guasto casuale.
        mapfile -t kernel < <(pacman -Qq 2>/dev/null | grep -E '^linux(-cachyos[a-z0-9-]*)?$' || true)
        for k in "${kernel[@]}"; do pkg+=("$k-headers"); done

        echo ">> installerei: ${pkg[*]}"
        fai pacman -S --needed --noconfirm "${pkg[@]}"
    fi
fi

# ------------------------------------------- 3. risparmio energetico del modulo
echo ">> installo $DEST_MODPROBE"
fai install -Dm 644 "$QUI/modprobe.d/nvidia-risparmio.conf" "$DEST_MODPROBE"

# ------------------------------------------------- 4. servizi sospendi/riprendi
# Preservano la VRAM attraverso la sospensione. Su un portatile che chiude il
# coperchio dieci volte al giorno (hyprland.lua lega proprio Lid Switch) sono la
# differenza fra riprendere e riprendere con la sessione a pezzi.
# Il preset di systemd di solito li ha gia' presi: qui si controlla e basta.
for u in nvidia-suspend nvidia-hibernate nvidia-resume; do
    # `systemctl cat` e non `list-unit-files`: quest'ultimo esce 0 anche quando
    # non trova niente ("0 unit files listed"), quindi non distingue.
    systemctl cat "$u.service" >/dev/null 2>&1 || continue

    if systemctl is-enabled --quiet "$u.service" 2>/dev/null; then
        echo ">> $u.service gia' abilitato"
    else
        echo ">> abilito $u.service"
        fai systemctl enable "$u.service"
    fi
done

# nvidia-powerd (Dynamic Boost) esiste solo su alcuni portatili: se non c'e'
# l'unit, non e' un problema da segnalare.
if systemctl cat nvidia-powerd.service >/dev/null 2>&1; then
    systemctl is-enabled --quiet nvidia-powerd.service 2>/dev/null \
        || fai systemctl enable nvidia-powerd.service
fi

# --------------------------------------------------------------- 5. controllo
if [ "$PROVA" = 1 ]; then
    echo "   [prova] (qui controllerei modeset, moduli e runtime PM)"
    exit 0
fi

echo
echo "--- controllo ---"
esito=0

if [ "$driver_presente" = 0 ]; then
    rosso "  manca   il driver: finche' non c'e', il resto non si puo' verificare"
    exit 1
fi

# --- modesetting: senza, Wayland con NVIDIA non funziona ---------------------
# Il bootloader NON si tocca: un'installazione CachyOS puo' usare systemd-boot,
# GRUB o limine, sono tre percorsi diversi e ognuno sa produrre una macchina che
# non avvia. Dai driver 560 in poi il modesetting e' attivo di default grazie
# allo snippet modprobe.d del pacchetto, quindi qui si guarda e basta.
modeset=/sys/module/nvidia_drm/parameters/modeset
if [ -r "$modeset" ] && [ "$(cat "$modeset")" = "Y" ]; then
    verde "  ok      nvidia_drm.modeset = Y"
elif [ ! -e "$modeset" ]; then
    giallo "  attesa  il modulo nvidia_drm non e' caricato: normale se hai appena"
    giallo "          installato il driver. Si vede dopo il riavvio."
else
    rosso "  manca   nvidia_drm.modeset non e' Y — Wayland con NVIDIA non va"
    giallo "          Rimedio, senza toccare il bootloader:"
    giallo "            echo 'options nvidia_drm modeset=1' |"
    giallo "              sudo tee /etc/modprobe.d/nvidia-modeset.conf"
    giallo "            sudo mkinitcpio -P && riavvia"
    esito=1
fi

# --- i moduli sono per il kernel in esecuzione? -------------------------------
if lsmod 2>/dev/null | grep -q '^nvidia'; then
    verde "  ok      moduli nvidia caricati"
else
    giallo "  attesa  moduli nvidia non caricati. Se hai appena aggiornato il"
    giallo "          kernel e' proprio cosi' che deve essere: dkms li ha"
    giallo "          compilati per il kernel NUOVO, ma in esecuzione c'e'"
    giallo "          ancora il vecchio. Riavvia."
fi

# --- prime-run: l'offload per singolo programma -------------------------------
if command -v prime-run >/dev/null 2>&1; then
    verde "  ok      prime-run (offload: prime-run <programma>)"
else
    giallo "  manca   prime-run — installa nvidia-prime se ti serve l'offload"
fi

# --- il dato che conta davvero per la batteria --------------------------------
rt="/sys/bus/pci/devices/$pci_dgpu/power/runtime_status"
if [ -r "$rt" ]; then
    stato="$(cat "$rt")"
    if [ "$stato" = "suspended" ]; then
        verde "  ok      la dGPU e' sospesa a riposo ($stato)"
    else
        giallo "  guarda  la dGPU risulta '$stato' mentre non la usa nessuno."
        giallo
        giallo "          Perche' importa: NVreg_DynamicPowerManagement=0x02 le"
        giallo "          permette di spegnersi del tutto, ma solo se nessuno"
        giallo "          tiene aperto un file descriptor DRM verso di lei."
        giallo "          hyprland.lua la elenca in AQ_DRM_DEVICES, e aquamarine"
        giallo "          apre quel device all'avvio e non lo lascia piu'."
        giallo
        giallo "          Se vuoi quei dieci watt: togli ':/dev/dri/dgpu' dalla"
        giallo "          riga AQ_DRM_DEVICES in config/hypr/hyprland.lua e"
        giallo "          rimisura. Si perde l'uscita HDMI, che e' cablata sulla"
        giallo "          discreta e serve solo con un monitor esterno."
    fi
fi

exit "$esito"
