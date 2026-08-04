# Hyprland — scorciatoie

`SUPER` è il tasto Windows. Tutto è fatto per non toccare il mouse.

## Base
| Tasti | Azione |
|---|---|
| `SUPER` + `Invio` | Terminale (Alacritty) |
| `SUPER` + `R` / `D` | Launcher applicazioni |
| `SUPER` + `E` | Gestore file (Thunar) |
| `SUPER` + `Q` | Chiudi finestra |
| `SUPER` + `V` | Storico appunti |
| `SUPER` + `W` | Cambia sfondo (immagini in `~/Git/wallpapers`) |
| `SUPER` + `Esc` | Blocca schermo |
| `SUPER` + `Shift` + `Q` | Menu spegnimento |
| `SUPER` + `Shift` + `E` | Esci da Hyprland |

## Muoversi fra le finestre
| Tasti | Azione |
|---|---|
| `SUPER` + `H J K L` o frecce | Sposta il focus |
| `SUPER` + `Shift` + `H J K L` | Sposta la finestra |
| `SUPER` + `Ctrl` + `H J K L` | Ridimensiona (si tiene premuto) |
| `SUPER` + `F` | Schermo intero |
| `SUPER` + `Shift` + `F` | Massimizza (barra visibile) |
| `SUPER` + `Shift` + `Spazio` | Rendi flottante — la valvola di sfogo dal tiling |
| `SUPER` + `T` | Ruota l'asse di divisione |
| `SUPER` + `P` | Pseudo-tile |

## Workspace
| Tasti | Azione |
|---|---|
| `SUPER` + `1`…`5` | Vai al workspace (cinque, fissi) |
| `SUPER` + `Shift` + `1`…`5` | Sposta la finestra lì |
| `SUPER` + `Tab` | Torna al workspace precedente |
| `SUPER` + rotella | Scorri i workspace |
| `SUPER` + `S` | Scratchpad (terminale a scomparsa) |
| `SUPER` + `Shift` + `S` | Manda la finestra nello scratchpad |

## Screenshot
| Tasti | Azione |
|---|---|
| `Stamp` | Area selezionata → appunti |
| `Shift` + `Stamp` | Schermo intero → `~/Pictures` |
| `Ctrl` + `Stamp` | Finestra → `~/Pictures` |
| `SUPER` + `Shift` + `P` | Contagocce colore |

## Notifiche
| Tasti | Azione |
|---|---|
| `SUPER` + `N` | Apri/chiudi il centro notifiche |
| `SUPER` + `Shift` + `N` | Chiudi tutte le notifiche |
| `SUPER` + `Ctrl` + `N` | Non disturbare on/off |

Nel pannello ci sono lo storico, l'interruttore Non disturbare e i controlli del
player se sta suonando qualcosa. Ci si arriva anche dalla campanella in barra.

## Tasti dedicati
Volume, luminosità e tasti multimediali funzionano già. Chiudendo il coperchio
lo schermo si blocca e si spegne.

---

## Cose da sapere

**GPU.** Il desktop gira sulla Intel, la RTX resta sospesa. Per usarla su un
programma: `prime-run <comando>`. Es. `prime-run steam`.

**Batteria.** Staccando l'alimentatore si spengono blur e ombre e i tempi di
standby si accorciano (blocco a 3 min, schermo off a 4, sospensione a 15).
Lo gestisce `scripts/power-watch.sh`. In corrente: 15 / 20 min e niente sospensione.

**Tema app GTK.** `nwg-look` per cambiarlo con l'interfaccia grafica.
I valori di partenza sono in `scripts/tema-gtk.sh`.

**Sfondo.** `SUPER` + `W` apre il selettore sulle immagini di `~/Git/wallpapers`:
la scelta si vede subito e resta al riavvio. Per aggiungerne, copia i file in
quella cartella — niente altro da fare. Varianti da terminale:
`scripts/sfondo.sh ~/percorso/img.jpg` (file preciso), `scripts/sfondo.sh --caso`
(una a caso), `SFONDI_DIR=~/altra/cartella scripts/sfondo.sh` (altra cartella).

**Dopo aver modificato un config:**
- `hyprland.lua` → `hyprctl reload`
- `waybar` → `killall -SIGUSR2 waybar`
- `swaync` → `swaync-client -rs` (stile) o `swaync-client -R` (config)
- `fuzzel` e `alacritty` → niente, rileggono da soli

**Controllare che il sistema sia a posto:** `./verifica.sh` dalla radice del repo.
