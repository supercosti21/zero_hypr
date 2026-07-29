# zero_hypr

Configurazione Hyprland scritta da zero — niente preset, niente framework di
dotfile. Ogni file è commentato riga per riga: lo scopo è capirlo, non solo
usarlo.

Gira su **Acer Nitro ANV15-51** (i9-13900H + Iris Xe / RTX 4060 Max-Q) con
**CachyOS**, accanto a COSMIC: la sessione si sceglie dal greeter, niente è stato
disinstallato. Tutti i pacchetti vengono dai repo ufficiali, **zero AUR**.

Priorità del setup, in ordine: **sviluppo**, **batteria**, **estetica**. Non è
un setup da gaming e non è una vetrina di effetti.

---

## Com'è organizzato

I file **non** vengono copiati in `~/.config`: ci sono dei **symlink**. Così
modificare un config e fare `git diff` sono la stessa operazione, e non si
rischia di lavorare mezz'ora sulla copia sbagliata.

```
config/hypr/         →  ~/.config/hypr          compositore, script, scorciatoie
config/waybar/       →  ~/.config/waybar        la barra
config/fuzzel/       →  ~/.config/fuzzel        launcher
config/mako/         →  ~/.config/mako          notifiche
config/xdg-desktop-portal/ → ~/.config/xdg-desktop-portal
sistema/udev/                                   regole per /etc (a mano, con sudo)
```

### Installazione su una macchina nuova

```bash
git clone git@github.com:supercosti21/zero_hypr.git ~/Git/zero_hypr
cd ~/Git/zero_hypr
./installa.sh --prova     # dice cosa farebbe
./installa.sh             # crea i symlink
```

`installa.sh` non cancella niente: se trova già una cartella in `~/.config` la
sposta in `<nome>.pre-git` e collega la nuova.

### Dipendenze

```bash
sudo pacman -S --needed \
  hyprland hyprpaper hyprlock hypridle hyprpolkitagent hyprshot hyprpicker \
  waybar fuzzel mako swaync matugen \
  alacritty ttf-meslo-nerd \
  networkmanager brightnessctl playerctl wireplumber \
  cliphist wl-clipboard udiskie jq python
```

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

Il demone lo avvia `scripts/notifiche.sh`, non un `exec-once` secco: swaync e
mako sono entrambi demoni di `org.freedesktop.Notifications` e si escludono a
vicenda. Lo script prende swaync se c'e' e ripiega su mako, cosi' non si resta
mai senza notifiche per un pacchetto mancante.

### Colori dallo sfondo

`matugen` estrae una palette Material You dallo sfondo e rigenera i file di
colore di barra, notifiche, launcher, bordi finestre e terminale. Succede ad
ogni `SUPER`+`W`.

I file rigenerati (`colori.css`, `colori.conf`, …) sono in `.gitignore`:
cambierebbero ad ogni cambio sfondo e riempirebbero la storia di rumore. In repo
stanno i `*.default.*`, che `installa.sh` copia come punto di partenza.

I fogli di stile **non contengono colori**: solo forme, spazi e stati, con nomi
semantici (`@sfondo`, `@accento`, `@testo_tenue`). È il motivo per cui lo stesso
CSS funziona con qualsiasi sfondo, chiaro o scuro.

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

**Non si può annidare Hyprland dentro COSMIC per provarlo**: `cosmic-comp` fa
fallire il backend con `Invalid binding of wl_compositor version 6`. Però il
config viene parsato *prima* del crash, quindi `Hyprland -c <file>` resta un
validatore di sintassi utile.

**Gli apostrofi negli script.** I commenti italiani dentro un programma `awk`
racchiuso fra apici singoli (`awk '...'`) chiudono la stringa a metà: `puo'`
rompe lo script senza che `bash -n` se ne accorga.

---

## Scorciatoie

L'elenco completo e aggiornato è in
[`config/hypr/SCORCIATOIE.md`](config/hypr/SCORCIATOIE.md). Le essenziali:

| tasti | azione |
|---|---|
| `SUPER`+`Invio` | terminale |
| `SUPER`+`R` | launcher |
| `SUPER`+`W` | cambia sfondo (e con esso tutti i colori) |
| `SUPER`+`V` | storico appunti |
| `SUPER`+`S` | scratchpad |
| `SUPER`+`Shift`+`Q` | menu spegnimento |
