#!/usr/bin/env bash
#
# verifica.sh — com'e' messo il sistema. Sola lettura, niente sudo.
#
#   ./verifica.sh              tutto
#   ./verifica.sh --breve      solo cio' che non va
#
# Esce diverso da zero se qualcosa manca, cosi' si puo' mettere in fondo a uno
# script o dentro un controllo automatico.
#
# NON RIPARA NIENTE, di proposito. Uno strumento che diagnostica e nello stesso
# tempo aggiusta e' uno strumento di cui non ti puoi fidare quando le cose vanno
# male: non sai mai se quello che vedi e' com'era o com'e' diventato mentre
# guardavi.
#
# Le righe "guarda" non sono errori: sono cose su cui vale la pena posare
# l'occhio, tipicamente perche' dipendono da come stai usando la macchina in
# quel momento.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=comune.sh
source "$REPO/comune.sh"

BREVE=0
[ "${1:-}" = "--breve" ] && BREVE=1

problemi=0

ok()     { [ "$BREVE" = 1 ] || printf '  \033[32mok\033[0m      %-24s %s\n' "$1" "${2:-}"; }
ko()     { printf '  \033[31mmanca\033[0m   %-24s %s\n' "$1" "${2:-}"; problemi=$((problemi + 1)); }
guarda() { printf '  \033[33mguarda\033[0m  %-24s %s\n' "$1" "${2:-}"; }
salta()  { [ "$BREVE" = 1 ] || printf '  \033[33m-\033[0m       %-24s %s\n' "$1" "${2:-}"; }

# Molti controlli hanno senso solo su Arch: altrove si saltano invece di
# riempire l'output di finti errori.
ARCH=0; command -v pacman >/dev/null 2>&1 && ARCH=1

# ============================================================ 1. collegamenti
titolo "Collegamenti in ~/.config"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}"
for n in hypr waybar fuzzel swaync matugen alacritty xdg-desktop-portal; do
    b="$DEST/$n"
    if [ -L "$b" ] && [ "$(readlink -f "$b")" = "$(readlink -f "$REPO/config/$n")" ]; then
        ok "$n"
    elif [ -e "$b" ]; then
        ko "$n" "esiste ma non punta a questo repo"
    else
        ko "$n" "non c'e' — lancia ./installa.sh"
    fi
done

# ================================================================== 2. colori
titolo "Palette generate"
# Sono in .gitignore: senza, hyprland.lua fa require('colori') e non parte, e
# waybar muore sull'@import. E' il primo posto da guardare se il desktop non si
# apre affatto.
for f in config/waybar/colori.css config/hypr/colori.lua config/swaync/colori.css \
         config/alacritty/colori.toml config/fuzzel/colori.ini; do
    if [ -f "$REPO/$f" ]; then ok "$(basename "$(dirname "$f")")/$(basename "$f")"
    else ko "$(basename "$(dirname "$f")")/$(basename "$f")" "lancia ./installa.sh"; fi
done

# =============================================================== 3. pacchetti
titolo "Pacchetti"
if [ "$ARCH" = 0 ]; then
    salta "pacman" "non e' un sistema Arch, salto"
else
    mapfile -t voluti < <(elenco "$REPO/pacchetti/base.txt")
    assenti=()
    for p in "${voluti[@]}"; do
        pacman -Q "$p" >/dev/null 2>&1 || assenti+=("$p")
    done
    if [ "${#assenti[@]}" -eq 0 ]; then
        ok "base.txt" "tutti e ${#voluti[@]} installati"
    else
        ko "base.txt" "${#assenti[@]} mancanti: ${assenti[*]}"
    fi

    if pacman -Q mako >/dev/null 2>&1; then
        ko "mako" "ancora installato — litiga con swaync su dbus"
    else
        ok "mako" "rimosso, come dev'essere"
    fi
fi

# ==================================================================== 4. font
titolo "Font"
if command -v fc-list >/dev/null 2>&1; then
    # Senza MesloLGS le icone della barra sono rettangoli vuoti, e il sintomo
    # non fa pensare a un font mancante.
    fc-list 2>/dev/null | grep -qi "MesloLGS" \
        && ok "MesloLGS Nerd Font" || ko "MesloLGS Nerd Font" "ttf-meslo-nerd"
    fc-list 2>/dev/null | grep -qi "Adwaita Sans" \
        && ok "Adwaita Sans" || ko "Adwaita Sans" "adwaita-fonts"
else
    salta "fc-list" "fontconfig non c'e'"
fi

# ===================================================================== 5. GPU
titolo "GPU"
for s in /dev/dri/igpu /dev/dri/dgpu; do
    if [ -e "$s" ]; then ok "$s" "-> $(readlink -f "$s")"
    else ko "$s" "senza, Hyprland non parte: 'Found no gpus to use'"; fi
done

if lspci -D 2>/dev/null | grep -qE '(3D|VGA).*NVIDIA'; then
    m=/sys/module/nvidia_drm/parameters/modeset
    if [ -r "$m" ] && [ "$(cat "$m")" = "Y" ]; then ok "nvidia_drm.modeset" "Y"
    elif [ ! -e "$m" ]; then ko "nvidia_drm" "modulo non caricato"
    else ko "nvidia_drm.modeset" "non e' Y — Wayland con NVIDIA non va"; fi

    command -v prime-run >/dev/null 2>&1 \
        && ok "prime-run" "offload disponibile" \
        || ko "prime-run" "nvidia-prime"

    # Il numero che decide quanto dura la batteria. Vedi il commento in
    # sistema/modprobe.d/nvidia-risparmio.conf.
    pci="$(lspci -D 2>/dev/null | grep -E '(3D|VGA).*NVIDIA' | head -n1 | cut -d' ' -f1)"
    rt="/sys/bus/pci/devices/$pci/power/runtime_status"
    if [ -r "$rt" ]; then
        st="$(cat "$rt")"
        if [ "$st" = "suspended" ]; then
            ok "dGPU a riposo" "$st"
        else
            guarda "dGPU a riposo" "$st — se non la stai usando, vedi sotto (*)"
        fi
    fi
else
    salta "NVIDIA" "nessuna scheda discreta"
fi

# ================================================================= 6. energia
titolo "Energia"
[ -x /usr/local/bin/power-profile-auto ] \
    && ok "power-profile-auto" || ko "power-profile-auto" "lancia sudo ./sistema/udev.sh"

if command -v powerprofilesctl >/dev/null 2>&1; then
    attuale="$(powerprofilesctl get 2>/dev/null || echo '?')"
    # In corrente ci si aspetta balanced, a batteria power-saver. Se non
    # combaciano, la regola udev non sta scattando.
    in_rete=0
    for t in /sys/class/power_supply/*/type; do
        [ -r "$t" ] && [ "$(cat "$t")" = "Mains" ] || continue
        [ "$(cat "${t%type}online" 2>/dev/null || echo 0)" = "1" ] && in_rete=1
    done
    atteso=power-saver; [ "$in_rete" = 1 ] && atteso=balanced
    if [ "$attuale" = "$atteso" ]; then
        ok "profilo energetico" "$attuale (alimentazione: $([ "$in_rete" = 1 ] && echo rete || echo batteria))"
    else
        guarda "profilo energetico" "e' $attuale, mi aspettavo $atteso"
    fi
else
    salta "powerprofilesctl" "power-profiles-daemon non c'e'"
fi

# ================================================================= 7. servizi
titolo "Servizi"
if command -v systemctl >/dev/null 2>&1; then
    for u in NetworkManager.service bluetooth.service \
             power-profiles-daemon.service power-profile-auto.service; do
        if systemctl is-enabled --quiet "$u" 2>/dev/null; then ok "$u"
        else ko "$u" "non abilitato"; fi
    done
else
    salta "systemctl" "niente systemd"
fi

# ================================================================== 8. accesso
titolo "Schermata di accesso"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled --quiet ly@tty1.service 2>/dev/null; then ok "ly@tty1"
    else ko "ly@tty1" "lancia sudo ./sistema/greeter-ly.sh"; fi

    altri=$(ls -1 /etc/systemd/system/multi-user.target.wants/ 2>/dev/null \
            | grep '^ly@' | grep -v '^ly@tty1.service$' || true)
    [ -n "$altri" ] && ko "un solo ly@" "abilitati anche: $altri" || ok "un solo ly@"

    dm=/etc/systemd/system/display-manager.service
    if [ -L "$dm" ]; then
        guarda "altro display manager" "$(basename "$(readlink -f "$dm")") e' ancora attivo"
    else
        ok "nessun altro DM"
    fi
fi

# Senza questa, ly non ha niente da mostrare nel menu delle sessioni.
[ -f /usr/share/wayland-sessions/hyprland.desktop ] \
    && ok "sessione Hyprland" || ko "sessione Hyprland" "manca il .desktop"

# =============================================================== 9. portachiavi
titolo "Portachiavi"
if [ -r /etc/pam.d/system-login ]; then
    n=$(grep -c 'pam_gnome_keyring' /etc/pam.d/system-login 2>/dev/null || echo 0)
    if [ "$n" -ge 3 ]; then
        ok "pam_gnome_keyring" "$n righe"
    else
        # Il sintomo non e' un errore: il portachiavi viene creato con password
        # VUOTA e tutto sembra funzionare, coi segreti cifrati da niente.
        ko "pam_gnome_keyring" "$n righe su 3 — sudo ./sistema/pam-gnome-keyring.sh"
    fi
else
    salta "/etc/pam.d/system-login" "non leggibile"
fi

# ================================================================= 10. sfondo
titolo "Sfondo"
hp="$DEST/hypr/hyprpaper.conf"
if [ -r "$hp" ]; then
    img="$(grep -m1 -E '^[[:space:]]*path[[:space:]]*=' "$hp" | sed 's/^[^=]*=[[:space:]]*//')"
    if [ -z "$img" ]; then
        guarda "hyprpaper" "nessuna immagine impostata — premi SUPER+W"
    elif [ -f "$img" ]; then
        ok "hyprpaper" "$(basename "$img")"
    else
        ko "hyprpaper" "punta a un file che non esiste: $img"
    fi
else
    salta "hyprpaper.conf" "non leggibile"
fi

# =================================================================== esito
echo
if [ "$problemi" -gt 0 ]; then
    rosso "$problemi cose da sistemare."
    echo
    echo "Quasi tutto si risolve con:  ./installa-tutto.sh"
    exit 1
fi
verde "Tutto a posto."

cat <<'NOTE'

(*) Sulla dGPU "active" a riposo: NVreg_DynamicPowerManagement le permette di
    spegnersi del tutto, ma solo se nessuno tiene aperto un file descriptor DRM
    verso di lei — e hyprland.lua la elenca in AQ_DRM_DEVICES, dove aquamarine
    la apre all'avvio e non la lascia piu'. Sono grosso modo dieci watt. Per
    riprenderli: togli ":/dev/dri/dgpu" dalla riga AQ_DRM_DEVICES in
    config/hypr/hyprland.lua e rimisura. Si perde l'uscita HDMI, che e' cablata
    sulla discreta e serve solo con un monitor esterno collegato.
NOTE
