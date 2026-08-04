#!/usr/bin/env bash
#
# menu.sh — un tasto solo: applicazioni, azioni di sistema, ricerche, comandi.
# Legato a SUPER+R.
#
#   menu.sh              apre la palette
#   menu.sh --elenco     stampa l'elenco e basta, per guardarci dentro
#
# COM'E' FATTO
# Una sola finestra di fuzzel con dentro DUE cose: le applicazioni (lette da
# applicazioni.py, con le loro icone) e le azioni di sistema. Chi vuole solo
# aprire un programma scrive due lettere e Invio, come prima. Chi scrive un
# prefisso non corrisponde a niente, e li' succede la parte interessante.
#
# IL MECCANISMO, in una riga: in modalita' dmenu, se il testo digitato non
# corrisponde a nessuna voce, fuzzel lo stampa cosi' com'e' sullo standard
# output. (C'e' anche Shift+Invio, che restituisce il testo grezzo ignorando i
# match.) Quindi non serve un secondo passaggio di fuzzel per i prefissi: si
# scrive "= 3*7" nella stessa finestra dove si scriverebbe "firefox", e questo
# script capisce da se' cosa gli e' stato chiesto.
#
# Un secondo passaggio di fuzzel si vede solo entrando in un sottomenu (Rete,
# Bluetooth, Audio…), dove e' naturale che sia cosi'.
#
# PERCHE' NON SI E' TOCCATO SUPER+D
# Resta il launcher nativo di fuzzel, che non passa da qui e non dipende da
# niente di nuovo. Se un giorno questo script si rompe, il modo di aprire un
# programma c'e' ancora — che su un tasto usato cento volte al giorno non e'
# un dettaglio.

set -uo pipefail

QUI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP="$QUI/applicazioni.py"
TERM_CMD="alacritty"

avvisa() { notify-send -a menu "${1:-Menu}" "${2:-}" 2>/dev/null || echo "${2:-}" >&2; }

# `hyprctl dispatch exec` e non `cmd &`: cosi' il programma nasce figlio del
# compositore invece che di questo script, che sta per morire. Lanciandolo con
# & resterebbe attaccato a un processo defunto, e certi programmi (i browser
# soprattutto) se ne accorgono e si comportano male.
lancia() { hyprctl dispatch exec -- "$1" >/dev/null 2>&1; }
lancia_term() { hyprctl dispatch exec -- "$TERM_CMD -e $1" >/dev/null 2>&1; }

################################################################################
#  1. Le voci di sistema
################################################################################
# Formato: <etichetta><TAB><azione>. L'etichetta e' quello che si vede, con
# l'icona Nerd Font davanti; l'azione e' quello che si esegue.
#
# Cinque di queste nove chiamano script che esistevano gia' e che non sono stati
# toccati: questo file e' un centralino, non una riscrittura.
voci_sistema() {
    cat <<VOCI
󰖩  Rete$(printf '\t')@rete
󰂯  Bluetooth$(printf '\t')@bluetooth
󰕾  Audio$(printf '\t')@audio
󱂬  Finestre$(printf '\t')@finestre
󰸉  Sfondo$(printf '\t')@sfondo
󰅌  Appunti$(printf '\t')@appunti
󰞅  Emoji$(printf '\t')@emoji
󰒓  Impostazioni$(printf '\t')@impostazioni
󰐥  Spegnimento$(printf '\t')@spegnimento
VOCI
}

################################################################################
#  2. I sottomenu
################################################################################
sottomenu() { # sottomenu <prompt> <righe con TAB>
    local prompt="$1" righe="$2" scelta
    scelta="$(printf '%s\n' "$righe" | cut -f1 \
              | fuzzel --dmenu --prompt="$prompt" --lines=10 --width=42)" || return 1
    [ -n "$scelta" ] || return 1
    printf '%s\n' "$righe" | grep -F -m1 -- "$scelta" | cut -f2
}

# Legge `wpctl status` da stdin e stampa "<etichetta>\t<id>" per ogni uscita.
# Separata dal comando apposta: cosi' prova/parser.sh puo' darle in pasto i
# campioni in prova/campioni/ invece di aver bisogno di wireplumber.
#
# `wpctl status` disegna un albero con caratteri di box:
#
#   Audio
#    ├─ Sinks:
#    │  *   56. Built-in Audio Analog Stereo   [vol: 0.65]
#    │      70. HDMI                           [vol: 1.00]
#    │
#    ├─ Sources:
#
# Due dettagli che la prima versione sbagliava:
#   · la sezione finisce al PROSSIMO "├─", non su una riga di solo "│". La riga
#     vuota c'e' quasi sempre, ma e' spaziatura, non un delimitatore;
#   · l'asterisco del predefinito va cercato SOLO prima dell'id. Cercarlo in
#     tutta la riga fa risultare attivo un dispositivo che ha un "*" nel nome —
#     c'e' un campione apposta che lo verifica.
leggi_uscite_audio() {
    awk '
        # Entrati in Sinks. Il next evita di trattare questa riga come una voce.
        /├─ Sinks:/ { dentro = 1; next }
        # Qualunque altra sezione chiude la precedente.
        /├─/        { dentro = 0 }

        dentro && match($0, /[0-9]+\./) {
            id = substr($0, RSTART, RLENGTH - 1) + 0

            # Solo la parte PRIMA dell id: e li che sta il marcatore.
            prefisso = substr($0, 1, RSTART - 1)
            attivo = (prefisso ~ /\*/) ? " ●" : ""

            nome = substr($0, RSTART + RLENGTH)
            sub(/[[:space:]]*\[vol:.*$/, "", nome)   # via il volume
            sub(/^[[:space:]]+/, "", nome)           # via lo spazio di allineamento
            sub(/[[:space:]]+$/, "", nome)
            if (nome == "") next

            printf "󰓃  %s%s\t%d\n", nome, attivo, id
        }'
}

menu_audio() {
    local righe
    righe="$(wpctl status 2>/dev/null | leggi_uscite_audio)"

    # A voce alta: un menu vuoto senza spiegazione sembra "non c'e' niente da
    # scegliere", non "qualcosa non ha funzionato".
    [ -n "$righe" ] || {
        avvisa Audio "Nessuna uscita audio: 'wpctl status' non ha dato niente di leggibile"
        return
    }

    local id
    id="$(sottomenu 'uscita audio> ' "$righe")" || return
    [ -n "$id" ] || return
    wpctl set-default "$id" && avvisa Audio "Uscita cambiata"
}

# Legge `hyprctl clients -j` da stdin. Separata dal comando per poterla provare
# col campione in prova/campioni/hyprctl-clients.json.
#
# mapped == true scarta le finestre che esistono ma non sono a schermo. Lo
# scratchpad invece resta: workspace.name vale "special:magic", ed e' proprio
# quella la finestra a cui puo' servire tornare.
leggi_finestre() {
    jq -r '
        .[]
        | select(.mapped == true)
        | select((.title // "") != "")
        | "󱂬  \(.workspace.name)  ·  \(.class)  ·  \(.title)\t\(.address)"
    ' 2>/dev/null
}

menu_finestre() {
    # Un selettore di finestre: con cinque workspace e finestre affiancate,
    # trovare "quella dove stavo scrivendo" a colpi di SUPER+numero e' lento.
    local righe
    righe="$(hyprctl clients -j 2>/dev/null | leggi_finestre)"

    [ -n "$righe" ] || { avvisa Finestre "Nessuna finestra aperta"; return; }

    local indirizzo
    indirizzo="$(sottomenu 'finestra> ' "$righe")" || return
    [ -n "$indirizzo" ] || return
    hyprctl dispatch focuswindow "address:$indirizzo" >/dev/null
}

menu_emoji() {
    # emoji-test.txt del pacchetto unicode-emoji. Le righe utili sono
    #   1F600 ; fully-qualified # 😀 E1.0 grinning face
    # e si tengono solo le "fully-qualified": le altre sono varianti tecniche
    # che nella maggior parte dei font non si vedono.
    local dati=/usr/share/unicode/emoji/emoji-test.txt
    if [ ! -r "$dati" ]; then
        avvisa Emoji "Manca $dati — installa il pacchetto unicode-emoji"
        return
    fi

    local scelta
    # ATTENZIONE agli apostrofi qui dentro: il programma awk sta in una stringa
    # fra apici singoli, e un apostrofo in un commento italiano la chiude a
    # meta'. E' la trappola descritta nel README, e ci sono cascato scrivendo
    # proprio queste righe.
    scelta="$(awk -F'#' '/; fully-qualified/ {
                  sub(/^ /, "", $2)
                  # $2 vale "grinning face" preceduto da emoji e versione:
                  # togliendo la versione restano emoji e nome, che e il testo
                  # su cui si cerca.
                  sub(/ E[0-9]+\.[0-9]+ /, "  ", $2)
                  print $2
              }' "$dati" \
              | fuzzel --dmenu --prompt='emoji> ' --lines=12 --width=42)" || return
    [ -n "$scelta" ] || return

    # Il primo campo e' l'emoji vera e propria.
    printf '%s' "${scelta%% *}" | wl-copy
    avvisa Emoji "${scelta%% *} copiato negli appunti"
}

menu_impostazioni() {
    local righe azione
    righe="$(cat <<VOCI
󰕾  Audio (pavucontrol)$(printf '\t')pavucontrol
󰂯  Bluetooth (blueman)$(printf '\t')blueman-manager
󰖩  Rete (connessioni)$(printf '\t')nm-connection-editor
󰉼  Aspetto GTK (nwg-look)$(printf '\t')nwg-look
󰓅  Profilo energetico$(printf '\t')@energia
VOCI
)"
    azione="$(sottomenu 'impostazioni> ' "$righe")" || return
    [ -n "$azione" ] || return

    if [ "$azione" = "@energia" ]; then
        menu_energia
    else
        lancia "$azione"
    fi
}

# Legge `powerprofilesctl list` da stdin e stampa un nome di profilo per riga.
#
# L'output e' MULTI-RIGA, ed e' questo che rende il parsing meno ovvio di quanto
# sembri:
#
#     performance:
#         Driver:     intel_pstate
#         Degraded:   no
#
#   * balanced:
#         Driver:     intel_pstate
#
# Il filtro precedente era `grep -oE '^\*? *[a-z-]+:'`. Sul formato vero
# funzionava, ma per il motivo sbagliato: le chiavi di dettaglio si chiamano
# "Driver" e "Degraded", con la maiuscola, e la classe [a-z-] accetta solo
# minuscole. Bastava che a monte comparisse una chiave minuscola — poniamo
# "active:" — perche' nel menu spuntasse un profilo che non esiste.
#
# Il criterio giusto non e' il nome, e' la POSIZIONE: i profili stanno a inizio
# riga (al massimo dopo "* "), le chiavi di dettaglio sono rientrate di quattro.
# E' strutturale, quindi non si rompe con un nome nuovo.
#
# Niente elenco di profili ammessi, anche se sarebbe stato facile: oggi ppd ne
# ha tre, ma se un giorno ne aggiungesse uno un elenco fisso lo farebbe sparire
# dal menu in silenzio — che e' peggio di una voce di troppo, perche' non si
# vede. Se qualcosa passasse comunque, `powerprofilesctl set` fallisce, e
# adesso il fallimento si vede.
leggi_profili_energia() {
    awk '
        # {0,3} e non *: e questa la riga che separa un profilo da un dettaglio.
        /^\*?[[:space:]]{0,3}[a-z][a-z0-9_-]*:/ {
            riga = $0
            sub(/^\*/, "", riga)
            sub(/^[[:space:]]+/, "", riga)
            sub(/:.*$/, "", riga)
            if (riga != "") print riga
        }'
}

menu_energia() {
    command -v powerprofilesctl >/dev/null || {
        avvisa Energia "power-profiles-daemon non c'e'"; return; }

    local attuale profili righe scelto
    attuale="$(powerprofilesctl get 2>/dev/null)"
    profili="$(powerprofilesctl list 2>/dev/null | leggi_profili_energia)"

    [ -n "$profili" ] || {
        avvisa Energia "'powerprofilesctl list' non ha dato nessun profilo noto"
        return
    }

    righe="$(printf '%s\n' "$profili" | while read -r p; do
                 [ -n "$p" ] || continue
                 marca=""; [ "$p" = "$attuale" ] && marca=" ●"
                 printf '󰓅  %s%s\t%s\n' "$p" "$marca" "$p"
             done)"

    scelto="$(sottomenu 'profilo> ' "$righe")" || return
    [ -n "$scelto" ] || return

    # Il fallimento si vede: e' anche la rete di sicurezza se il parsing
    # producesse una voce che profilo non e'.
    if ! powerprofilesctl set "$scelto" 2>/dev/null; then
        avvisa Energia "'$scelto' non e' stato accettato da powerprofilesctl"
        return
    fi

    # Detto chiaro, se no sembra che non abbia funzionato: alla prossima
    # attaccata o staccata del cavo, power-profile-auto rimette il suo.
    avvisa Energia "Profilo: $scelto — vale fino al prossimo cambio di alimentazione"
}

################################################################################
#  3. I prefissi
################################################################################
# Nessuno di questi corrisponde a una voce dell'elenco, quindi fuzzel restituisce
# il testo grezzo e si arriva qui.
cerca_web() { # cerca_web <url-con-%s> <testo>
    local testo="$2"
    # Codifica percentuale: senza, una ricerca con spazi o & arriva troncata.
    local codificato
    codificato="$(printf '%s' "$testo" | jq -sRr @uri 2>/dev/null)" \
        || codificato="${testo// /+}"
    lancia "xdg-open ${1//%s/$codificato}"
}

calcola() {
    local espressione="$1" risultato
    # python e non bc: bc non fa le potenze con **, non ha le funzioni
    # trigonometriche senza -l e ha una sintassi che nessuno ricorda.
    # L'espressione NON viene passata alla shell: arriva a python come
    # argomento, quindi non c'e' niente da iniettare.
    risultato="$(python3 - "$espressione" <<'PY' 2>/dev/null
import sys, math
espressione = sys.argv[1]
# Solo matematica: niente builtins, niente import, niente accesso a file.
ambiente = {n: getattr(math, n) for n in dir(math) if not n.startswith("_")}
ambiente.update(abs=abs, round=round, min=min, max=max, sum=sum)
try:
    valore = eval(espressione, {"__builtins__": {}}, ambiente)
except Exception:
    sys.exit(1)
if isinstance(valore, float) and valore == int(valore):
    valore = int(valore)
print(valore)
PY
)" || { avvisa Calcolatrice "Non riesco a calcolare: $espressione"; return; }

    printf '%s' "$risultato" | wl-copy
    avvisa "= $risultato" "copiato negli appunti  ($espressione)"
}

instrada_grezzo() { # il testo che fuzzel ha restituito senza corrispondenze
    local t="$1"
    case "$t" in
        '>'*)  lancia      "$(printf '%s' "${t#>}" | sed 's/^ *//')" ;;
        '$'*)  lancia_term "$(printf '%s' "${t#$}" | sed 's/^ *//')" ;;
        '='*)  calcola     "$(printf '%s' "${t#=}" | sed 's/^ *//')" ;;
        'g '*)    cerca_web 'https://www.google.com/search?q=%s'        "${t#g }" ;;
        'w '*)    cerca_web 'https://it.wikipedia.org/w/index.php?search=%s' "${t#w }" ;;
        'y '*)    cerca_web 'https://www.youtube.com/results?search_query=%s' "${t#y }" ;;
        'arch '*) cerca_web 'https://wiki.archlinux.org/index.php?search=%s'  "${t#arch }" ;;
        *)
            # Nessun prefisso e nessuna corrispondenza: quasi sempre e' una
            # ricerca. Si chiede conferma invece di aprire il browser di slancio
            # su quello che poteva essere solo un errore di battitura.
            local conferma
            conferma="$(printf 'Cerca sul web:  %s\nEsegui come comando:  %s\nAnnulla' "$t" "$t" \
                        | fuzzel --dmenu --prompt='non trovato> ' --lines=3 --width=52)" || return
            case "$conferma" in
                Cerca*)   cerca_web 'https://www.google.com/search?q=%s' "$t" ;;
                Esegui*)  lancia "$t" ;;
            esac
            ;;
    esac
}

################################################################################
#  4. L'elenco unico e la scelta
################################################################################
# Le app prima, poi le azioni di sistema: chi apre la palette per lanciare un
# programma — il caso di gran lunga piu' frequente — trova subito quello che
# cerca, e le nove voci di sistema stanno in fondo dove non danno fastidio.
elenco_completo() {
    "$APP" 2>/dev/null
    voci_sistema | cut -f1
}

if [ "${1:-}" = "--elenco" ]; then
    elenco_completo | tr '\0' '|'
    exit 0
fi

command -v fuzzel >/dev/null || { avvisa Menu "fuzzel non c'e'"; exit 1; }

scelta="$(elenco_completo | fuzzel --dmenu --prompt='   ' --lines=12 --width=45)" || exit 0
[ -n "$scelta" ] || exit 0

# --- e' una voce di sistema? ---------------------------------------------------
azione="$(voci_sistema | grep -F -m1 -- "$scelta" | cut -f2 || true)"

case "$azione" in
    @rete)         exec "$QUI/wifi.sh" ;;
    @bluetooth)    exec "$QUI/bluetooth.sh" ;;
    @audio)        menu_audio;        exit 0 ;;
    @finestre)     menu_finestre;     exit 0 ;;
    @sfondo)       exec "$QUI/sfondo.sh" ;;
    @appunti)      exec "$QUI/appunti.sh" ;;
    @emoji)        menu_emoji;        exit 0 ;;
    @impostazioni) menu_impostazioni; exit 0 ;;
    @spegnimento)  exec "$QUI/menu-power.sh" ;;
esac

# --- e' un'applicazione? --------------------------------------------------------
if riga="$("$APP" --comando "$scelta" 2>/dev/null)"; then
    tipo="${riga%%|*}"
    comando="${riga#*|}"
    if [ "$tipo" = "terminale" ]; then
        lancia_term "$comando"
    else
        lancia "$comando"
    fi
    exit 0
fi

# --- allora e' testo grezzo -------------------------------------------------------
instrada_grezzo "$scelta"
