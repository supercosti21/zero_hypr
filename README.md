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
| sinistra | numero dei workspace (dinamici) |
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

### Workspace dinamici

Stile COSMIC: esistono i workspace occupati **più uno vuoto in coda**, minimo
due. Riempi il 2 → appare il 3. Svuoti il 3 → sparisce. Non si gestiscono mai a
mano.

Lo fa `config/hypr/scripts/workspace-dinamici.py`: ascolta gli eventi sul socket
di Hyprland e ricalcola quali workspace devono essere `persistent`. Non lancia
`hyprctl` (ogni chiamata è un fork+exec) e non fa polling: dorme sulla socket e
si sveglia solo sugli eventi che possono cambiare il conteggio. A regime, zero
CPU.

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
