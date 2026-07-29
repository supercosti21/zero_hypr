#!/usr/bin/env bash
#
# wifi.sh — selettore di reti wi-fi in fuzzel. Aperto dal modulo rete in waybar.
#
# Perche' esiste: nm-applet e' il "secret agent" di NetworkManager, cioe' cio'
# che fa comparire la finestrella della password. Ma per farlo pianta anche una
# sua icona nel tray, doppiando l'icona rete della barra. Questo script fa lo
# stesso lavoro con nmcli: chiede la password in fuzzel (mascherata) e la passa
# a NetworkManager, che poi la ricorda nel profilo. Cosi' niente applet, niente
# tray, niente icone doppie.

set -euo pipefail

menu() { fuzzel --dmenu --lines="${2:-12}" --width="${3:-52}" --prompt="$1"; }
avvisa() { notify-send -a wifi "Wi-Fi" "$1" 2>/dev/null || echo "$1" >&2; }

# --- radio spenta: prima cosa da controllare, altrimenti la scansione da' 0 reti
if [ "$(nmcli -t -f WIFI radio 2>/dev/null)" != "enabled" ]; then
    if [ "$(printf 'Accendi il Wi-Fi\nAnnulla' | menu 'wi-fi spento> ' 2 30)" = "Accendi il Wi-Fi" ]; then
        nmcli radio wifi on && avvisa "Wi-Fi acceso"
    fi
    exit 0
fi

# --- elenco reti -------------------------------------------------------------
# --rescan yes costringe una scansione fresca: senza, nmcli serve una cache che
# puo' avere minuti e mostrare reti non piu' presenti.
# I ':' negli SSID sono sfuggiti da nmcli come '\:', quindi si separa su ':'
# non sfuggiti usando un separatore raro.
elenco=$(nmcli --terse --escape no --fields IN-USE,SIGNAL,SECURITY,SSID \
             device wifi list --rescan yes 2>/dev/null || true)

[ -n "$elenco" ] || { avvisa "Nessuna rete trovata"; exit 1; }

# Riga per riga: icona segnale + lucchetto se protetta + nome.
# Si scarta chi ha SSID vuoto (reti nascoste: non si possono scegliere a click).
# nmcli elenca gia' in ordine di segnale decrescente, quindi la prima
# occorrenza di un SSID e' la sua banda migliore: si tiene quella. Il dedup deve
# essere sull'SSID e non sulla riga intera, altrimenti la stessa rete a 2.4 e 5
# GHz compare due volte con due icone di segnale diverse.
voci=$(printf '%s\n' "$elenco" | awk -F':' '
    {
        inuso = $1; segnale = $2 + 0; sicurezza = $3;
        # ATTENZIONE: qui dentro non si possono usare apostrofi. Il programma
        # awk sta in una stringa fra apici singoli della shell, e un apostrofo
        # in un commento la chiude a meta lasciando awk con un pezzo di codice.
        # Gli SSID possono contenere ":", quindi si riattacca tutto il resto.
        ssid = $4;
        for (i = 5; i <= NF; i++) ssid = ssid ":" $i;
        if (ssid == "") next;      # reti nascoste: non si scelgono a click

        if (!(ssid in visto)) {
            visto[ssid] = 1;
            ordine[++n] = ssid;

            if      (segnale >= 75) barra[ssid] = "󰤨";
            else if (segnale >= 50) barra[ssid] = "󰤥";
            else if (segnale >= 25) barra[ssid] = "󰤢";
            else                    barra[ssid] = "󰤟";

            lucchetto[ssid] = (sicurezza == "" || sicurezza == "--") ? "  " : "󰌾 ";
        }

        # Basta che UNA delle bande sia quella in uso.
        if (inuso == "*") attiva[ssid] = 1;
    }
    END {
        for (i = 1; i <= n; i++) {
            s = ordine[i];
            printf "%s %s%s%s\n", barra[s], lucchetto[s], s, (s in attiva ? "  ●" : "");
        }
    }')

scelta=$(printf '%s\n' "$voci" | menu 'rete> ') || exit 0
[ -n "$scelta" ] || exit 0

# Ripulisce la voce dalle decorazioni per riottenere l'SSID esatto.
ssid=${scelta#* }          # via l'icona segnale
ssid=${ssid#󰌾 }            # via il lucchetto, se c'era
ssid=${ssid#  }            # via lo spazio doppio delle reti aperte
ssid=${ssid% ●}            # via il pallino "attiva"

[ -n "$ssid" ] || exit 0

# --- connessione -------------------------------------------------------------
# Se esiste gia' un profilo salvato, NetworkManager ha gia' la password: si
# tenta senza chiedere niente.
if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "$ssid"; then
    if nmcli connection up id "$ssid" >/dev/null 2>&1; then
        avvisa "Connesso a $ssid"
        exit 0
    fi
    # Profilo presente ma rifiutato: password cambiata. Si continua e si chiede.
fi

if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
    avvisa "Connesso a $ssid"
    exit 0
fi

# Serve la password: fuzzel --password la maschera mentre si digita.
chiave=$(fuzzel --dmenu --password --lines=0 --width=34 \
                --prompt="password $ssid> " </dev/null) || exit 0
[ -n "$chiave" ] || exit 0

if nmcli device wifi connect "$ssid" password "$chiave" >/dev/null 2>&1; then
    avvisa "Connesso a $ssid"
else
    avvisa "Connessione a $ssid fallita"
    exit 1
fi
