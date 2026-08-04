# zero_hypr

Configurazione Hyprland scritta da zero — niente preset, niente framework di
dotfile. Ogni file è commentato riga per riga: lo scopo è capirlo, non solo
usarlo.

Gira su **Acer Nitro ANV15-51** (i9-13900H + Iris Xe / RTX 4060 Max-Q) con
**CachyOS**: installazione pulita, GRUB e `ly`, niente altro desktop accanto.
Tutti i pacchetti vengono dai repo ufficiali, **zero AUR**.

Priorità del setup, in ordine: **sviluppo**, **batteria**, **estetica**. Non è
un setup da gaming e non è una vetrina di effetti.

---

## Installazione su una macchina nuova

Si installa CachyOS normalmente dal suo installatore, poi:

```bash
git clone git@github.com:supercosti21/zero_hypr.git ~/Git/zero_hypr
cd ~/Git/zero_hypr
./installa-tutto.sh --prova     # dice tutto quello che farebbe, senza toccare niente
./installa-tutto.sh             # lo fa (chiede la password sudo una volta sola)
systemctl reboot
```

`--prova` non chiede la password: un dry-run non scrive niente, e pretendere
sudo per vedere l'anteprima vorrebbe dire che nessuno la guarda.

Lo script si lancia **da utente normale, mai con sudo**. Se girasse tutto come
root, i symlink e i file di colore finirebbero di proprietà di root dentro
`~/.config`: il desktop partirebbe lo stesso, ma `matugen` non potrebbe più
riscrivere la palette al cambio sfondo, e fallirebbe in silenzio. I passi che
servono root sono script separati in `sistema/`, invocati uno per uno.

I dieci passi, in un ordine che non è casuale: bonifica, pacchetti, GPU NVIDIA,
udev ed energia, servizi, portachiavi, collegamenti, ritocchi, schermata di
accesso, verifica. I pacchetti prima dei collegamenti, altrimenti si seminano
file di colore per programmi che non ci sono; il greeter per **ultimo**, perché
è l'unica cosa che può impedire il login al prossimo avvio — se qualcosa va
storto prima, la schermata di accesso non è mai stata toccata.

Un passo che va male non ferma gli altri: finisce in un elenco alla fine.
Fermarsi a metà lascerebbe una macchina in uno stato peggiore di quella di
partenza.

Per sapere com'è messo il sistema, in qualunque momento:

```bash
./verifica.sh          # tutto
./verifica.sh --breve  # solo ciò che non va
```

Non ripara niente, di proposito: uno strumento che diagnostica e insieme
aggiusta è uno di cui non ti puoi fidare quando le cose vanno male.

**Se al riavvio non compare nessuna schermata di accesso:** `Ctrl`+`Alt`+`F3`
apre un login testuale. Da lì `sudo ./sistema/greeter-ly.sh --annulla` e
`systemctl reboot` rimettono quella di prima.

### Dipendenze

Stanno in [`pacchetti/base.txt`](pacchetti/base.txt), un pacchetto per riga con
scritto accanto perché c'è. Non sono duplicate qui apposta: due elenchi nello
stesso repo prima o poi divergono, e quello sbagliato è sempre quello che leggi.

I driver NVIDIA stanno a parte in [`pacchetti/nvidia.txt`](pacchetti/nvidia.txt)
perché non sono incondizionati — vedi la sezione GPU ibrida.

---

## Com'è organizzato

I file **non** vengono copiati in `~/.config`: ci sono dei **symlink**. Così
modificare un config e fare `git diff` sono la stessa operazione, e non si
rischia di lavorare mezz'ora sulla copia sbagliata.

```
installa-tutto.sh          l'unico comando: fa tutto, chiama gli altri
installa.sh                solo i symlink (è il passo 7 di installa-tutto.sh)
verifica.sh                com'è messo il sistema, in sola lettura
comune.sh                  funzioni condivise, si include con source

config/hypr/         →  ~/.config/hypr          compositore, script, scorciatoie
config/waybar/       →  ~/.config/waybar        la barra
config/fuzzel/       →  ~/.config/fuzzel        launcher
config/swaync/       →  ~/.config/swaync        notifiche e pannello
config/matugen/      →  ~/.config/matugen       i colori dallo sfondo
config/alacritty/    →  ~/.config/alacritty     terminale
config/xdg-desktop-portal/ → ~/.config/xdg-desktop-portal

pacchetti/                 gli elenchi dei pacchetti
sistema/                   quello che tocca /etc, un pezzo per script
sfondi/                    lo sfondo di riserva, e il codice che lo genera
prova/                     i controlli che si possono fare senza il portatile
```

`installa.sh` non cancella niente: se trova già una cartella in `~/.config` la
sposta in `<nome>.pre-git` (numerandola, se serve) e collega la nuova.

---

## Il launcher è anche il centro di controllo

`SUPER`+`R` apre una finestra sola con dentro le **applicazioni** e le **azioni
di sistema**. Per aprire un programma si scrivono due lettere e Invio, come
sempre. Scrivendo invece un prefisso succede altro: `> comando` lo esegue,
`$ comando` lo apre in un terminale, `= 2+2*3` calcola e copia il risultato,
`g testo` cerca su Google (`w` Wikipedia, `y` YouTube, `arch` la wiki di Arch).
Le nove voci di sistema, in fondo: rete, bluetooth, uscita audio, elenco
finestre, sfondo, appunti, emoji, impostazioni, spegnimento.

**Come fa a funzionare in una finestra sola.** In modalità dmenu, se il testo
digitato non corrisponde a nessuna voce, fuzzel lo stampa così com'è sullo
standard output. Quindi non serve un secondo passaggio per i prefissi: si scrive
`= 3*7` nella stessa finestra dove si scriverebbe `firefox`, e
[`scripts/menu.sh`](config/hypr/scripts/menu.sh) capisce da sé cosa gli è stato
chiesto. Un secondo passaggio si vede solo entrando in un sottomenù, dove è
naturale.

**Perché serve `applicazioni.py`.** fuzzel sa elencare le applicazioni da solo
ed è bravo, ma in quella modalità legge le voci da dentro sé stesso e non
accetta niente dallo standard input: o le app, o la lista che gli dai tu, mai le
due insieme. Per avere un tasto solo, l'elenco va costruito fuori. Le icone si
mantengono col protocollo esteso di rofi (`nome\0icon\x1ficona`), che fuzzel
implementa.

Niente cache, ed è una misura non un'opinione: con 306 file `.desktop` lo script
impiega 33 ms, di cui 10 sono l'avvio di python. Una cache ne risparmierebbe
venti — impercettibili — in cambio della logica per invalidarla, che è proprio
la cosa che poi sbaglia: installi un programma e non compare nel menù.

`SUPER`+`D` resta **fuzzel puro**, il launcher nativo: non passa da nessuno
script e non dipende da niente di nuovo. Su un tasto che si preme cento volte al
giorno, avere una via di scorta non è pignoleria.

Cinque delle nove voci di sistema chiamano script che esistevano già: `menu.sh`
è un centralino, non una riscrittura.

---

## GPU ibrida

I driver NVIDIA su CachyOS li gestisce **`chwd`**, che l'installatore ha già
eseguito: sceglie il profilo giusto per la scheda, tira dentro gli headers del
kernel in uso e configura da solo il PRIME offload. Per questo
`sistema/gpu-nvidia.sh` **verifica invece di installare**: metterci sopra
pacchetti a mano è il modo migliore per litigare con chwd.

Quello che invece non faceva nessuno è il controllo. Le tre cose che, se
mancano, danno sintomi che non si collegano alla causa:

- **modesetting spento** → Wayland con NVIDIA non parte;
- **servizi sospendi/riprendi assenti** → sessione a pezzi dopo aver chiuso il
  coperchio, e `hyprland.lua` lega proprio `Lid Switch`;
- **moduli dkms compilati per un altro kernel** → la scheda "sparisce" dopo un
  aggiornamento, e sembra un guasto. Non lo è: serve solo riavviare.

**Il bootloader non si tocca mai.** Un'installazione CachyOS può usare
systemd-boot, GRUB o limine: tre percorsi diversi, ognuno capace di produrre una
macchina che non avvia. Dai driver 560 in poi il modesetting è attivo di default
grazie allo snippet modprobe.d del pacchetto, quindi lo script guarda e, se
manca, stampa il rimedio da applicare consapevolmente.

### I dieci watt che vale la pena misurare

`sistema/modprobe.d/nvidia-risparmio.conf` permette alla discreta di spegnersi
del tutto (D3cold) e non solo di andare in idle. Fra sospesa e spenta ci sono
grosso modo dieci watt.

Ma vale **solo se nessuno tiene aperto un file descriptor DRM** verso di lei — e
`hyprland.lua` la elenca in `AQ_DRM_DEVICES`, dove aquamarine la apre all'avvio
e non la lascia più. Il commento nel config diceva che «resta sospesa»: era
un'assunzione, non una misura.

Quindi non si cambia niente al buio. `./verifica.sh` stampa:

```
/sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```

Se dice `active` mentre nessun programma sta usando la GPU, togliere
`:/dev/dri/dgpu` dalla riga `AQ_DRM_DEVICES` vale quei dieci watt. Si perde
l'uscita HDMI, che è cablata sulla discreta e serve solo con un monitor esterno
collegato. Dato che «batteria» è la priorità numero due, è probabilmente la
misura di maggior valore di tutto il setup, e costa una riga di output.

---

## La barra

Una pillola sola, flottante. In barra sta **solo** ciò che si guarda di
sfuggita; tutto il resto è nel tooltip o dietro un click.

| dove | cosa |
|---|---|
| sinistra | numero dei workspace (cinque, fissi) |
| centro | titolo della finestra col focus |
| destra | wi-fi · bluetooth · batteria · data e ora · notifiche · spegni |

Niente CPU, RAM o temperatura: sono numeri che non si guardano mai davvero e
costano un risveglio del compositore ogni pochi secondi — su un portatile è
l'opposto di "ottimizzato". Se servono: `SUPER`+`Invio` e `btop`.

**Niente tray**, per scelta: `nm-applet` e `blueman-applet` ci piantavano
esattamente le stesse icone di rete e bluetooth già presenti in barra, e si
vedevano doppie. Il compito utile di `nm-applet` (chiedere la password wi-fi)
è passato a `config/hypr/scripts/wifi.sh`, che la chiede in fuzzel — mascherata —
e la passa a `nmcli`.

### Workspace

Cinque, fissi, sempre presenti (`persistent:true` in `hyprland.conf`). La barra
mostra sempre `1 2 3 4 5` e le posizioni non ballano: `SUPER`+`3` porta sempre
nello stesso posto.

C'era una prima versione con workspace dinamici in stile COSMIC (occupati + uno
vuoto in coda), gestiti da un demone sul socket di Hyprland. Funzionava, ma
`hyprctl reload` **azzera i keyword impostati a runtime**: ogni cambio sfondo —
che fa un reload — faceva sparire il workspace in coda finché non si apriva una
finestra. Dichiararli nel file li rende immuni, perché il config viene
riapplicato ad ogni ricarica. Meno codice e un bug in meno.

### Notifiche

`swaync` fa sia le notifiche a comparsa sia il **pannello** con lo storico
(`SUPER`+`N` o la campanella in barra): dentro ci sono le notifiche passate,
l'interruttore Non disturbare e i controlli del player.

I colori vengono da `colori.css`, lo stesso meccanismo della barra e con gli
stessi nomi semantici — quindi barra e notifiche sono intonate per costruzione,
non per coincidenza. L'urgenza si legge da una barra colorata a sinistra invece
che da un fondo colorato: resta leggibile e non urla.

`config.json` non ha commenti perche' il suo schema dichiara
`additionalProperties: false`, quindi le chiavi `"//"` che molti usano come
commento non sono valide. Le motivazioni stanno in
[`config/swaync/NOTE.md`](config/swaync/NOTE.md).

Il demone lo avvia `scripts/notifiche.sh` e non un `exec-once` secco: se swaync
mancasse si resterebbe senza notifiche in silenzio, e lo script invece lo dice.

**Un demone solo.** `org.freedesktop.Notifications` è un nome D-Bus unico: due
demoni non possono tenerlo insieme, vince chi arriva primo. È il motivo per cui
`mako` è stato tolto dal repo e viene **disinstallato** da
`sistema/bonifica.sh` — non basta non avviarlo, perché mako è attivabile via
D-Bus e la prima notifica che arriva prima che swaync sia su lo risveglia da
sola. Da quel momento le notifiche finiscono in un demone senza pannello e con i
colori sbagliati, mentre swaync sembra rotto.

### Volume e luminosità

I tasti dedicati passano da `scripts/osd.sh`, che oltre a cambiare il valore lo
**mostra**. Prima chiamavano `wpctl` e `brightnessctl` e basta: funzionava, ma
senza nessun riscontro a schermo non si capisce se sei arrivato a zero, se il
tasto non va o se stai regolando l'uscita sbagliata.

Il riquadro è una notifica di swaync, non `swayosd`. swayosd disegna qualcosa di
più bello, ma è un demone in più sempre acceso con un suo foglio di stile che
sfuggirebbe a matugen: sarebbe l'unico pezzo del desktop a non seguire lo
sfondo. Il dettaglio che rende la cosa usabile è
`x-canonical-private-synchronous`, l'hint che dice al demone di **sostituire**
la notifica precedente invece di impilarne una nuova: senza, tenendo premuto il
tasto del volume se ne accumulano venti.

### Colori dallo sfondo

`matugen` estrae una palette Material You dallo sfondo e rigenera i file di
colore di barra, notifiche, launcher, bordi finestre e terminale. Succede ad
ogni `SUPER`+`W`.

I file rigenerati (`colori.css`, `colori.lua`, …) sono in `.gitignore`:
cambierebbero ad ogni cambio sfondo e riempirebbero la storia di rumore. In repo
stanno i `*.default.*`, che `installa.sh` copia come punto di partenza.

I fogli di stile **non contengono colori**: solo forme, spazi e stati, con nomi
semantici (`@sfondo`, `@accento`, `@testo_tenue`). È il motivo per cui lo stesso
CSS funziona con qualsiasi sfondo, chiaro o scuro.

#### Il terminale è l'eccezione: contrasto calcolato, non copiato

Per barra, bordi e launcher basta copiare i ruoli Material You: sono definiti in
coppie (`surface`/`on_surface`, `primary`/`on_primary`) e il contrasto lo
garantisce lo standard. Per i 16 colori ANSI del terminale non c'è nessun ruolo:
l'unico blocco da 16 che matugen produce è `base16`, che però è la **scala
tonale di una sola tinta**, quella dello sfondo. Su un'immagine poco variegata
tutti e 16 finiscono a un passo dal fondo — contrasti misurati:

| | nero | verde | giallo | blu | magenta | ciano |
|---|---|---|---|---|---|---|
| base16 | 1.10 | 1.13 | 1.37 | **1.02** | **1.00** | 1.06 |

Con 4.5 come minimo leggibile: fastfetch, `ls`, i prompt e i diff di `git`
scrivevano nero su nero. Non era uno sfondo sfortunato — `base16` non ha alcun
vincolo di contrasto, quindi ricapita.

Quei 16 colori li costruisce
[`config/hypr/scripts/colori-terminale.py`](config/hypr/scripts/colori-terminale.py),
che `sfondo.sh` chiama subito dopo matugen passandogli la palette in json:

- le **tinte** partono dagli angoli ANSI canonici in OKLCh, non dallo sfondo:
  rosso resta rosso. Dello sfondo si prende solo l'accento, che le inclina di
  pochi gradi (max 8, e la metà su rosso e giallo, che portano un significato);
- la **luminosità** non è scelta a occhio: si cerca la più bassa che raggiunge il
  contrasto richiesto su *quel* fondo. La più bassa perché in OKLCh la croma
  disponibile cala salendo, quindi fermarsi appena superata la soglia dà il
  colore più vivo fra quelli leggibili;
- le soglie sono una scala — normali 5.2, brillanti 7.5 — così «brillante» è
  davvero più chiaro di «normale» invece di somigliargli;
- ogni tinta ha un margine in più sopra la soglia (giallo il più chiaro, blu il
  più scuro, come nei temi ANSI di sempre). Serve a chi non distingue
  rosso/verde, e in bianco e nero a tutti: senza, i sei colori avrebbero per
  costruzione la stessa luminanza e si distinguerebbero *solo* per tinta;
- passano dallo stesso controllo anche le coppie che di solito nessuno guarda:
  testo dentro la selezione, testo dentro il cursore, barra di ricerca,
  suggerimenti dei link, testo attenuato (`SGR 2`).

Il file generato si porta dietro la tabella dei contrasti ottenuti, in testa.
Per vederla senza cambiare niente:

```bash
matugen --quiet -j hex image ~/Git/wallpapers/foto.jpg \
  | ~/.config/hypr/scripts/colori-terminale.py --prova --tabella
```

---

## Segreti e portachiavi

`gnome-keyring` fa da Secret Service (`org.freedesktop.secrets`) per tutte le
app: Brave, Trae, credenziali git, VPN. Non c'è un password manager separato,
per scelta.

**Sblocco al login.** `sistema/pam-gnome-keyring.sh` aggancia
`pam_gnome_keyring` a `/etc/pam.d/system-login`, che è il punto dove convergono
il login da tty e il greeter: un solo inserimento copre entrambi. Le righe sono
`optional` di proposito — se il modulo si rompe il login funziona comunque, cosa
che con `required` non sarebbe vera.

```bash
sudo ./sistema/pam-gnome-keyring.sh --prova    # mostra il risultato
sudo ./sistema/pam-gnome-keyring.sh            # applica (backup automatico)
sudo ./sistema/pam-gnome-keyring.sh --annulla  # torna indietro
```

Senza questo il portachiavi non viene sbloccato da nessuno, e il sintomo non è
un errore ma il contrario: viene creato con **password vuota**, quindi tutto
funziona… con i segreti cifrati da una chiave derivata dal nulla. È lo stato in
cui si trovava questa macchina.

**Le app Electron non trovano il portachiavi da sole.** Chromium sceglie il
backend guardando `XDG_CURRENT_DESKTOP`: `Hyprland` non è nella lista che
conosce, quindi ripiega sul negozio "basic" (un file con chiave fissa) e mostra
messaggi tipo *"An OS keyring couldn't be identified"*. Il portachiavi funziona
benissimo — semplicemente non viene cercato. Si corregge per applicazione:

* Trae (fork di VSCode): `config/Trae/argv.json` con
  `"password-store": "gnome-libsecret"`.
* App Chromium avviate a mano: `--password-store=gnome-libsecret`.

Mettere `GNOME` in `XDG_CURRENT_DESKTOP` risolverebbe in un colpo, ma quella
variabile decide anche quali portali xdg vengono usati e quali autostart
partono: si sistemerebbe il portachiavi rompendo i dialoghi Apri/Salva.

---

## Trappole già pagate

Roba che non sta nella documentazione e che è costata tempo. È qui per non
riscoprirla.

**`windowrule` / `layerrule` sono cambiate in Hyprland 0.56.** La forma vecchia
produce 23 errori di config. Adesso:

```ini
windowrule = <prop> <valore>, match:<criterio> <valore>
```

Tre regole: ogni proprietà vuole un valore esplicito (`float true`, non `float`);
i criteri vanno col prefisso `match:` e si separano **con la virgola**; i nomi
composti sono in snake_case (`idle_inhibit`, `no_blur`, `initial_class`). Nelle
`layerrule` `ignorezero` non esiste più: si scrive `ignore_alpha 0`.

Per verificare qualsiasi dubbio senza riavviare:
`hyprctl keyword windowrule "<regola>"` risponde `ok` oppure `invalid field ...`.

**Opzioni rimosse in 0.56:** `misc:vfr` → ora è `debug:vfr`, già `true` di
default. `dwindle:pseudotile` → non ha più un interruttore globale, il
pseudotiling si applica per finestra col dispatcher `pseudo`.

**L'edizione Hyprland di CachyOS porta un rice concorrente.**
`cachyos-hyprland-settings` installa `mako`, `wofi`, `wlogout`, una `waybar`
sua, `swaylock-effects`, `polkit-kde-agent`, `network-manager-applet`,
`kvantum`, un tema Nord e un tema cursore. Quasi tutto è innocuo per un motivo
preciso: **non lo avvia nessuno**. `hyprland.lua` lancia `hyprpolkitagent` e non
`polkit-kde-agent`; qui il tray non c'è, quindi `nm-applet` resta fermo; i
config in `~/.config` li sposta da parte `installa.sh`.

L'eccezione è `mako`, ed è il caso da capire: **è attivabile via D-Bus**. Non
basta tenerlo fuori dall'autostart, perché la prima notifica che arriva prima
che swaync sia su lo risveglia da sola, e da quel momento
`org.freedesktop.Notifications` è suo. Va disinstallato, e lo fa
`sistema/bonifica.sh`. Il resto si lascia dov'è: rimuovere
`cachyos-hyprland-settings` può portarsi via a cascata pacchetti che servono, e
lasciare inerte ciò che è inerte costa zero.

**`tema-gtk.sh` moriva alla prima riga senza dire niente.** Ha `set -e` e
comincia con `gsettings`: senza `gsettings-desktop-schemas` e `dconf` gli schemi
`org.gnome.desktop.*` non esistono, la prima chiamata fallisce e lo script
aborta a metà. Risultato: niente tema, niente icone, niente cursore, niente
font, e **nessun messaggio**. Adesso controlla e dice cosa manca. Era il pezzo
più insidioso di tutta l'installazione, perché il sintomo — «il desktop è
grigio» — non porta da nessuna parte.

**Il greeter non si cerca per nome.** Prima si disabilitava
`cosmic-greeter.service` scritto a mano; su un'installazione dove quel servizio
non esiste (l'edizione Hyprland usa SDDM) lo script falliva senza aver fatto
niente. Il modo giusto è leggere dove punta il symlink
`/etc/systemd/system/display-manager.service`, che indica il display manager in
uso qualunque esso sia.

**Un `ly@ttyN` può restare abilitato senza il pacchetto `ly`.** È un
collegamento verso un unit inesistente, innocuo finché non installi ly — a quel
punto diventa vivo e al riavvio partono **due** schermate di accesso, con in più
il guaio che tty2 è proprio il terminale di scorta a cui si ricorre se quella su
tty1 non parte. `systemctl enable` non se ne lamenta, perché il modello può
legittimamente stare su più terminali: va controllato a mano.

**`KERNEL=="ACAD"` nelle regole udev lega il repo a un modello.** `ACAD` è il
nome che il firmware di *questo* Acer dà all'alimentatore; altrove è `AC`,
`ADP0`, `ADP1`. Filtrare per `ENV{POWER_SUPPLY_TYPE}=="Mains"` costa uguale e
funziona ovunque.

**hyprpaper 0.8 vuole un blocco, e falla in silenzio.** Le righe piatte
`preload = img` + `wallpaper = eDP-1,img` non danno **nessun** errore ma vengono
ignorate: nel log compare solo `Monitor eDP-1 has no target` e lo sfondo resta
nero. La forma valida:

```ini
wallpaper {
    monitor =          # vuoto = tutti i monitor
    path = /percorso/immagine.jpg
}
```

Attenzione all'asimmetria: via IPC il monitor **va nominato**
(`hyprctl hyprpaper wallpaper "eDP-1,/img"`), perché la forma `,/img` viene
accettata e ignorata in silenzio. Nel file di config invece il campo vuoto
funziona. Il comando IPC `preload` non esiste più.

**GPU ibrida: `AQ_DRM_DEVICES` separa le schede con `:`**, quindi i path di
`/dev/dri/by-path/` **non sono usabili** — contengono già i due punti
dell'indirizzo PCI (`pci-0000:00:02.0-card`), vengono spezzati e Hyprland aborta
all'avvio con `Found no gpus to use`. Nemmeno `/dev/dri/cardN` va bene: la
numerazione cambia fra i boot. Soluzione: la regola udev in
`sistema/udev/72-gpu.rules` crea `/dev/dri/igpu` e `/dev/dri/dgpu`, nomi stabili
e senza due punti.

**GTK3 non ha la pseudo-classe `:empty`** e waybar **muore** all'avvio se la
trova nel CSS.

**waybar formatta le date ignorando il locale** se non glielo si chiede
esplicitamente: serve il flag `L` (`{:L%a %d}`). Qui non serve, perché la lingua
di sistema è inglese di proposito — solo la tastiera è italiana
(`input:kb_layout = it`).

**Annidare Hyprland dentro un altro compositore per provarlo non funziona
sempre**: sotto `cosmic-comp`, per dirne uno, il backend fallisce con
`Invalid binding of wl_compositor version 6`. Però il config viene parsato
*prima* del crash, quindi `Hyprland -c <file>` resta un validatore di sintassi
utile. Per il solo `hyprland.lua` c'è di meglio: `luac -p`, che non ha bisogno
di nessun compositore ed è già dentro `./prova/statici.sh`.

**Gli apostrofi negli script.** I commenti italiani dentro un programma `awk`
racchiuso fra apici singoli (`awk '...'`) chiudono la stringa a metà: `puo'`
rompe lo script senza che `bash -n` se ne accorga. Ci si casca ancora: è
successo scrivendo il selettore di emoji della palette, anni dopo aver scritto
questa riga.

---

## Scelte, e perché

**Niente GNU Stow, symlink scritti a mano.** Non è ostinazione: stow collega la
*cartella* solo finché la destinazione non esiste. Appena qualcosa crea una
`~/.config/hypr` vera, stow "srotola" in symlink per file — e a quel punto
matugen che scrive `~/.config/hypr/colori.lua` crea un **file vero** accanto ai
symlink, divergendo dal repo in silenzio. La premessa «modificare un config e
fare `git diff` sono la stessa cosa» morirebbe senza un rumore. In più stow dà
errore sui file esistenti invece di spostarli da parte, e `--adopt` fa
l'opposto di quel che serve (tira il file estraneo *dentro* il repo,
sovrascrivendo il tuo).

**Niente TLP.** Litiga con `power-profiles-daemon`, che questo setup usa già:
la regola udev e il selettore nella palette lo danno per scontato. Due gestori
di alimentazione che si contendono gli stessi parametri sono peggio di nessuno
dei due.

**Nessun browser imposto.** Le ricerche della palette passano da `xdg-open`, che
userà quello che deciderai di installare. Un browser è la cosa più personale di
un desktop: sceglierlo al posto tuo sarebbe l'unica decisione di questo repo
presa senza un motivo tecnico.

**Il profilo in corrente è `balanced`, non `performance`.** Su un i9-13900H
`performance` vuol dire ventole sempre accese per compilare tre file, e la
priorità dichiarata qui è sviluppo, batteria, estetica — in quest'ordine.
`balanced` lascia comunque salire le frequenze quando serve davvero.

**Thunar e non Nautilus.** `tema-gtk.sh` imposta `adw-gtk3`, che è un tema
**GTK3**; Nautilus è GTK4/libadwaita e lo ignorerebbe, restando l'unica finestra
fuori tono di tutto il desktop. Thunar lo eredita, e pesa molto meno.

**Lo sfondo di riserva è generato, non scaricato.** Una foto vera pesa qualche
megabyte, ha una licenza da rispettare e un giorno l'URL da cui viene sparisce.
[`sfondi/genera-predefinito.py`](sfondi/genera-predefinito.py) è venti righe di
matematica con un seme fisso: sta in repo per sempre e chiunque può rifarla
identica. Le macchie sono piccole e poco intense di proposito — un primo
tentativo con macchie larghe dava uno sfondo tutto azzurro, bello ma da cui
matugen avrebbe ricavato un tema *chiaro*, e con esso barra chiara e terminale
chiaro.

**Dopo l'installazione il clone risulta "sporco".** `sfondo.sh` riscrive la riga
`path` di `hyprpaper.conf` e `hyprlock.conf`, che sono file tracciati. Non è un
bug: è il prezzo di avere la scelta dello sfondo dentro il repo invece che in
uno stato separato.

---

## Provare senza il portatile

```bash
./prova/statici.sh     # sintassi shell/python/lua, shellcheck, udev, e le prove
```

Le prove vere sono tre, e ognuna copre codice che a mano non si riesce a
controllare:

- [`prova/incrocio.sh`](prova/incrocio.sh) — ogni comando invocato dai config
  arriva da un pacchetto in elenco? I due file non li tiene allineati nessuno, e
  il sintomo di una dimenticanza arriva mesi dopo come «quel tasto non fa
  niente». Ha già trovato `playerctl`.
- [`prova/power-profile.sh`](prova/power-profile.sh) — il binario del profilo
  energetico contro un `/sys` finto. Gira da udev, dove nessuno guarda: se
  sbaglia, il sintomo è «il portatile dura meno di prima», mesi dopo, senza log.
- [`prova/menu.sh`](prova/menu.sh) — l'instradamento della palette e le trappole
  dei `.desktop`, con fuzzel e hyprctl finti. Include una prova che tenta di
  uscire dal recinto della calcolatrice.

Per i nomi dei pacchetti serve `pacman`:

```bash
./prova/pacchetti.sh                                       # su Arch/CachyOS
docker build -f prova/Containerfile -t zh-prova . && docker run --rm zh-prova
```

**Cosa non è verificabile senza il portatile**, e va detto invece di lasciarlo
credere: la compilazione dei moduli dkms, `chwd`, l'abilitazione di `ly@tty1`,
la sessione Hyprland e come si vede il desktop. In breve — il container prova i
**nomi** e la disposizione dei file, una macchina virtuale prova l'**avvio** e
la sessione, solo il portatile prova **NVIDIA e batteria**.

---

## Scorciatoie

L'elenco completo e aggiornato è in
[`config/hypr/SCORCIATOIE.md`](config/hypr/SCORCIATOIE.md). Le essenziali:

| tasti | azione |
|---|---|
| `SUPER`+`Invio` | terminale |
| `SUPER`+`R` | palette: app, sistema, ricerche, comandi |
| `SUPER`+`D` | launcher applicazioni, fuzzel puro |
| `SUPER`+`W` | cambia sfondo (e con esso tutti i colori) |
| `SUPER`+`V` | storico appunti |
| `SUPER`+`S` | scratchpad |
| `SUPER`+`Stamp` | schermata da annotare (satty) |
| `SUPER`+`Shift`+`Q` | menu spegnimento |
