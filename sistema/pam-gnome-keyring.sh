#!/usr/bin/env bash
#
# pam-gnome-keyring.sh — aggancia il portachiavi al login.
#
#   sudo ./sistema/pam-gnome-keyring.sh            applica
#   sudo ./sistema/pam-gnome-keyring.sh --prova    mostra il file risultante
#   sudo ./sistema/pam-gnome-keyring.sh --annulla  ripristina l'ultimo backup
#
# COSA RISOLVE
# Senza pam_gnome_keyring il portachiavi non viene sbloccato da nessuno. Il
# risultato pratico su questa macchina era un portachiavi con password VUOTA:
# i segreti stavano in un file la cui chiave e' derivata dal nulla, cioe'
# leggibili da chiunque legga la home. Con il modulo agganciato, il portachiavi
# "login" viene aperto usando la password di accesso, che non viene mai scritta
# su disco.
#
# DOVE
# /etc/pam.d/system-login, perche' e' il punto in cui convergono sia il login
# da tty (`login`) sia il greeter (`greetd` -> system-local-login ->
# system-login): un solo inserimento copre entrambi.
#
# PERCHE' `optional` E NON `required`
# Se il modulo fallisce o il pacchetto viene rimosso, `optional` viene ignorato
# e il login funziona comunque. Con `required` un portachiavi rotto
# significherebbe non poter piu' entrare nel sistema. Su un file PAM si
# sbaglia una volta sola.

set -euo pipefail

FILE=/etc/pam.d/system-login
MODULO=/usr/lib/security/pam_gnome_keyring.so
AZIONE="${1:-applica}"

[ "$(id -u)" = "0" ] || { echo "Serve root: sudo $0 $AZIONE" >&2; exit 1; }

# --- annulla -----------------------------------------------------------------
if [ "$AZIONE" = "--annulla" ]; then
    ultimo=$(ls -1t "$FILE".backup-* 2>/dev/null | head -1 || true)
    [ -n "$ultimo" ] || { echo "Nessun backup da ripristinare." >&2; exit 1; }
    cp -a "$ultimo" "$FILE"
    echo "Ripristinato da $ultimo"
    exit 0
fi

[ -f "$MODULO" ] || { echo "Manca $MODULO — installa gnome-keyring." >&2; exit 1; }
[ -f "$FILE" ]   || { echo "Manca $FILE — questo sistema non usa la catena PAM attesa." >&2; exit 1; }

# --- costruisce la versione nuova --------------------------------------------
NUOVO=$(python3 - "$FILE" <<'PY'
import sys, re

percorso = sys.argv[1]
righe = open(percorso).read().splitlines()

# Le tre righe da aggiungere, ognuna dopo il rispettivo "include system-auth".
#   auth     -> raccoglie la password mentre viene digitata
#   password -> se cambi la password di login, aggiorna anche il portachiavi
#               (senza questa, dopo un cambio password lo sblocco automatico
#                smette di funzionare e non e' ovvio il perche')
#   session  -> avvia il demone e sblocca davvero. auto_start serve se il
#               portachiavi "login" non esiste ancora: lo crea.
DA_AGGIUNGERE = [
    ("auth",     "auth       optional   pam_gnome_keyring.so"),
    ("password", "password   optional   pam_gnome_keyring.so"),
    ("session",  "session    optional   pam_gnome_keyring.so      auto_start"),
]

def presente(tipo):
    for r in righe:
        campi = r.split()
        if len(campi) >= 3 and campi[0] == tipo and "pam_gnome_keyring.so" in r:
            return True
    return False

for tipo, testo in DA_AGGIUNGERE:
    if presente(tipo):
        continue   # idempotente: rilanciarlo non duplica nulla

    # Si inserisce dopo l'ULTIMA riga di quel tipo, cosi' il modulo vede la
    # password gia' raccolta da system-auth e la sessione e' gia' impostata.
    ultimo = max((i for i, r in enumerate(righe)
                  if r.split() and r.split()[0] == tipo), default=None)
    if ultimo is None:
        righe.append(testo)
    else:
        righe.insert(ultimo + 1, testo)

print("\n".join(righe))
PY
)

if [ "$AZIONE" = "--prova" ]; then
    echo "--- $FILE risulterebbe cosi': ---"
    printf '%s\n' "$NUOVO"
    echo "--- (nessuna modifica scritta) ---"
    exit 0
fi

# --- scrive, con backup ------------------------------------------------------
backup="$FILE.backup-$(date +%Y%m%d-%H%M%S)"
cp -a "$FILE" "$backup"
printf '%s\n' "$NUOVO" > "$FILE"
chmod 644 "$FILE"

echo "Modificato $FILE (backup: $backup)"
echo
grep -n 'pam_gnome_keyring' "$FILE" | sed 's/^/  /'
cat <<'FINE'

Adesso: esci dalla sessione e rientra (SUPER+Shift+Q -> Esci).
Al rientro il portachiavi "login" viene creato e sbloccato con la tua
password di accesso.

Se qualcosa andasse storto al login: le righe sono `optional`, quindi
il login funziona comunque. Per tornare indietro:
  sudo ./sistema/pam-gnome-keyring.sh --annulla
FINE
