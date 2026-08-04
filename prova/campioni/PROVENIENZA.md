# Da dove vengono questi campioni

Sono l'output di comandi che su questa macchina di sviluppo non ci sono. Servono
a provare i parser di `menu.sh` e `bluetooth.sh` senza il portatile.

**Il rischio va detto subito**: un campione sbagliato dà un test verde e un
desktop rotto. Sono riproduzioni fedeli al formato documentato, non catture da
una macchina vera. Il primo giro sul portatile va fatto guardando l'output reale
di questi comandi e confrontandolo con i file qui dentro.

Per rifarli dal vero, sul portatile:

```bash
wpctl status                    > prova/campioni/wpctl-status.txt
powerprofilesctl list           > prova/campioni/powerprofilesctl-list.txt
bluetoothctl devices            > prova/campioni/bluetoothctl-devices.txt
bluetoothctl devices Connected  > prova/campioni/bluetoothctl-devices-connessi.txt
bluetoothctl devices Paired     > prova/campioni/bluetoothctl-devices-accoppiati.txt
hyprctl clients -j              > prova/campioni/hyprctl-clients.json
```

Se un file cambia, `./prova/parser.sh` dirà subito se il parser regge il formato
nuovo. È il motivo per cui i valori attesi stanno nel test e non qui.

---

## `wpctl-status*.txt` — WirePlumber 0.5

Struttura ad albero con caratteri di box. Quello che conta per il parser:

- la sezione utile comincia con `├─ Sinks:` e **finisce al `├─` successivo**;
- ogni uscita è `<id>. <nome>  [vol: <n>]`, con l'id seguito da un punto;
- l'uscita predefinita ha un `*` **prima dell'id**, non da qualche altra parte
  nella riga.

I quattro file coprono: due o più uscite con una attiva; una sola uscita e
nessun asterisco (capita appena dopo l'avvio); la sezione presente ma vuota;
e — il caso cattivo — un dispositivo con un asterisco **dentro il nome**, che un
parser distratto scambierebbe per quello attivo.

Formato verificato contro il manuale di `wpctl(1)` e contro esempi della
ArchWiki e del forum di Arch.

## `powerprofilesctl-list*.txt` — power-profiles-daemon

**È multi-riga**, ed è la cosa che ha fatto sbagliare la prima versione del
parser: sotto ogni profilo ci sono righe indentate `Driver:` e `Degraded:`, che
un filtro poco attento raccoglie come se fossero profili anche loro.

- il nome del profilo sta a inizio riga, eventualmente preceduto da `* ` se è
  quello attivo;
- le righe di dettaglio sono **indentate**;
- i profili sono e restano tre: `performance`, `balanced`, `power-saver`. È un
  enum del demone, non una lista aperta.

Il secondo file ha un `Degraded:` con un valore vero (`high-operating-temperature`),
perché è il caso in cui la riga di dettaglio somiglia di più a un nome di profilo.

## `bluetoothctl-devices*.txt` — bluez

Una riga per dispositivo: `Device <MAC> <nome>`. Il nome può contenere spazi, e
prende tutto il resto della riga.

Tre file perché `bluetooth.sh` interroga tre elenchi separati — tutti, connessi,
accoppiati — e li incrocia per decidere quale pallino mettere accanto a cosa.

## `hyprctl-clients.json` — Hyprland

I campi che il parser usa: `address`, `mapped`, `class`, `title`,
`workspace.name`.

Contiene apposta una finestra con `mapped: false` (esiste ma non è a schermo:
non deve comparire) e una nello scratchpad, `workspace.name` = `special:magic`
(quella invece deve comparire, altrimenti non ci si può tornare).

La finestra non mappata ha un **titolo non vuoto**, e non è un dettaglio: nella
prima versione ce l'aveva vuoto, quindi a escluderla era il filtro sul titolo e
non quello su `mapped`. La prova passava senza provare quello che diceva di
provare — se ne è accorta la controprova, togliendo il filtro `mapped` e
vedendo che il test restava verde.
