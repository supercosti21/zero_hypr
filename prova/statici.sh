#!/usr/bin/env bash
#
# statici.sh — tutti i controlli che non richiedono una macchina Arch.
#
#   ./prova/statici.sh
#
# Sintassi di shell, python e lua, le regole udev, piu' le tre prove vere
# (incrocio, power-profile, menu). Esce diverso da zero se qualcosa non va.
#
# Cosa NON puo' provare, e va detto invece di lasciarlo credere: la risoluzione
# dei pacchetti sui repo CachyOS (serve pacman: c'e' prova/Containerfile), la
# compilazione dei moduli dkms, chwd, l'abilitazione dei servizi, e ovviamente
# come si vede il desktop. Il container prova i nomi e la disposizione dei file,
# una macchina virtuale prova l'avvio e la sessione, solo il portatile prova
# NVIDIA e batteria.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$QUI")"
cd "$REPO" || exit 1

falliti=0
ok()   { printf '  ok      %s\n' "$1"; }
ko()   { printf '  ERRORE  %s\n' "$1"; falliti=$((falliti + 1)); }
salta(){ printf '  -       %s\n' "$1"; }

echo "── Sintassi shell ──"
for f in ./*.sh sistema/*.sh config/hypr/scripts/*.sh prova/*.sh sistema/bin/*; do
    [ -f "$f" ] || continue
    # sistema/bin/power-profile-auto e' POSIX sh, non bash.
    if head -n1 "$f" | grep -q 'bin/sh'; then
        sh -n "$f" 2>/dev/null && ok "$f" || ko "$f"
    else
        bash -n "$f" 2>/dev/null && ok "$f" || { ko "$f"; bash -n "$f"; }
    fi
done

echo
echo "── shellcheck ──"
if command -v shellcheck >/dev/null 2>&1; then
    for f in ./*.sh sistema/*.sh config/hypr/scripts/*.sh; do
        [ -f "$f" ] || continue
        shellcheck -x -S warning "$f" >/dev/null 2>&1 && ok "$f" || {
            ko "$f"; shellcheck -x -S warning "$f" | head -20; }
    done
else
    salta "shellcheck non installato (pacman -S shellcheck)"
fi

echo
echo "── Python ──"
for f in config/hypr/scripts/*.py sfondi/*.py; do
    [ -f "$f" ] || continue
    python3 -m py_compile "$f" 2>/dev/null && ok "$f" || { ko "$f"; python3 -m py_compile "$f"; }
done
# Il blocco python dentro sfondo.sh: e' un heredoc, quindi bash -n non lo guarda.
awk "/<<'PY'/{f=1;next} /^PY\$/{f=0} f" config/hypr/scripts/sfondo.sh > /tmp/.zh-sfondo.py 2>/dev/null
if [ -s /tmp/.zh-sfondo.py ]; then
    python3 -m py_compile /tmp/.zh-sfondo.py 2>/dev/null \
        && ok "blocco python dentro sfondo.sh" || ko "blocco python dentro sfondo.sh"
    rm -f /tmp/.zh-sfondo.py
fi

echo
echo "── Lua ──"
# Solo sintassi: hl.* lo inietta Hyprland, quindi niente di semantico si puo'
# controllare da fuori. Basta comunque a intercettare la virgola dimenticata,
# che e' l'errore che impedisce alla sessione di partire.
if command -v luac >/dev/null 2>&1; then
    for f in config/hypr/hyprland.lua config/hypr/colori.default.lua; do
        luac -p "$f" 2>/dev/null && ok "$f" || { ko "$f"; luac -p "$f"; }
    done
    rm -f luac.out
else
    salta "luac non installato (pacman -S lua)"
fi

echo
echo "── Regole udev ──"
if command -v udevadm >/dev/null 2>&1 && udevadm verify --help >/dev/null 2>&1; then
    for f in sistema/udev/*.rules; do
        udevadm verify "$f" >/dev/null 2>&1 && ok "$f" || { ko "$f"; udevadm verify "$f"; }
    done
else
    salta "udevadm verify non disponibile"
fi

echo
echo "── Prove ──"
for p in incrocio power-profile menu; do
    if "./prova/$p.sh" >/dev/null 2>&1; then ok "prova/$p.sh"
    else ko "prova/$p.sh"; "./prova/$p.sh" 2>&1 | tail -20; fi
done

echo
if [ "$falliti" -gt 0 ]; then
    echo "$falliti controlli falliti." >&2
    exit 1
fi
echo "Tutti i controlli statici passano."
