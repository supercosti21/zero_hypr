#!/usr/bin/env python3
"""genera-predefinito.py — costruisce sfondi/predefinito.jpg.

Perche' generarlo invece di scaricare una foto: una foto vera pesa qualche
megabyte, ha una licenza da rispettare e un giorno l'URL da cui viene sparisce.
Questo file e' venti righe di matematica, sta in repo per sempre e chiunque puo'
rifarlo identico o cambiarlo.

    ./sfondi/genera-predefinito.py            riscrive sfondi/predefinito.jpg
    ./sfondi/genera-predefinito.py --dove X   scrive altrove

Serve Pillow, ma SOLO per rigenerare l'immagine: chi installa il desktop trova
il jpg gia' fatto in repo e non ha bisogno di niente.

COME E' FATTO E PERCHE'
Tre macchie di luce sfumate su un fondo quasi nero. Non e' una scelta estetica
soltanto: questo sfondo e' anche il materiale da cui matugen ricava l'INTERA
palette del desktop (barra, bordi, launcher, notifiche, sedici colori del
terminale), quindi deve avere

  · un accento saturo e riconoscibile — matugen viene lanciato con
    `--prefer saturation`, cioe' fra i colori candidati sceglie il piu' saturo.
    Un'immagine tutta grigia darebbe accenti slavati e un desktto smorto;
  · un fondo scuro e uniforme, perche' colori-terminale.py calcola i sedici
    colori ANSI risolvendo il contrasto CONTRO quel fondo: se il fondo fosse
    chiaro, il terminale verrebbe chiaro;
  · nessun dettaglio fine, cosi' regge la sfocatura di hyprlock senza diventare
    una poltiglia.

I colori di partenza sono gli stessi di config/hypr/colori.default.lua, cosi' il
primo avvio e' coerente anche nell'istante fra il login e il primo matugen.
"""

import argparse
import math
import pathlib
import random
import sys

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Serve Pillow per rigenerare lo sfondo:  pacman -S python-pillow\n"
             "(non serve per usare il desktop: il jpg e' gia' in repo)")

LARGHEZZA, ALTEZZA = 1920, 1080

# Fondo: lo stesso "surface" di colori.default.lua / swaync.
FONDO = (0x0b, 0x11, 0x11)

# Le macchie. (x, y in frazioni dello schermo, raggio in frazioni della
# diagonale, colore, intensita' massima).
#
# Piccole e poco intense di proposito: la maggior parte del quadro deve restare
# quasi nera. Un primo tentativo con macchie larghe e forti ha prodotto uno
# sfondo tutto azzurro — bello a vedersi, ma matugen ne avrebbe ricavato un
# tema CHIARO, e con esso una barra chiara e un terminale chiaro. Qui l'accento
# deve esserci ed essere saturo, non deve occupare lo schermo.
#
# Il teal e' primo e piu' intenso perche' e' l'accento che matugen deve
# pescare; gli altri due servono solo a non far sembrare l'immagine un
# gradiente lineare.
MACCHIE = [
    (0.22, 0.34, 0.30, (0x80, 0xd4, 0xd5), 0.42),   # teal, l'accento
    (0.80, 0.72, 0.26, (0x4a, 0x7c, 0xb8), 0.26),   # blu, profondita'
    (0.58, 0.12, 0.20, (0x2f, 0x8f, 0x86), 0.18),   # verde-acqua, transizione
]

# Granello finissimo. Senza, un gradiente cosi' ampio su otto bit mostra le
# bande — e in un jpg il compressore le accentua invece di nasconderle.
GRANA = 3


def curva(d):
    """Da distanza normalizzata (0 al centro, 1 al bordo) a intensita'.

    Coseno rialzato invece di una gaussiana o di un cono: arriva a zero con
    derivata zero, quindi la macchia non ha un bordo visibile — che e'
    esattamente il difetto che si nota su uno sfondo a schermo intero.
    """
    if d >= 1.0:
        return 0.0
    return 0.5 * (1.0 + math.cos(math.pi * d))


def genera():
    diagonale = math.hypot(LARGHEZZA, ALTEZZA)

    # Si disegna piccolo e si ingrandisce: le macchie sono sfumate per
    # costruzione, quindi il dettaglio non serve, e a un ottavo della
    # risoluzione il triplo ciclo costa un attimo invece di un minuto.
    sw, sh = LARGHEZZA // 8, ALTEZZA // 8
    piccola = Image.new("RGB", (sw, sh))
    px = piccola.load()

    macchie = [
        (cx * sw, cy * sh, r * diagonale / 8, colore, forza)
        for cx, cy, r, colore, forza in MACCHIE
    ]

    for y in range(sh):
        for x in range(sw):
            r, g, b = FONDO
            for mx, my, raggio, (cr, cg, cb), forza in macchie:
                peso = curva(math.hypot(x - mx, y - my) / raggio) * forza
                if peso <= 0.0:
                    continue
                # Somma e non fusione: dove due macchie si sovrappongono il
                # colore si schiarisce, come farebbero due luci vere.
                r += (cr - FONDO[0]) * peso
                g += (cg - FONDO[1]) * peso
                b += (cb - FONDO[2]) * peso
            px[x, y] = (min(255, int(r)), min(255, int(g)), min(255, int(b)))

    img = piccola.resize((LARGHEZZA, ALTEZZA), Image.LANCZOS)
    img = img.filter(ImageFilter.GaussianBlur(6))

    # Grana dopo la sfocatura, altrimenti la sfocatura se la mangerebbe.
    rnd = random.Random(20260804)   # seme fisso: rigenerarlo da' lo stesso file
    px = img.load()
    for y in range(ALTEZZA):
        for x in range(LARGHEZZA):
            r, g, b = px[x, y]
            n = rnd.randint(-GRANA, GRANA)
            px[x, y] = (
                min(255, max(0, r + n)),
                min(255, max(0, g + n)),
                min(255, max(0, b + n)),
            )

    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dove", default=None, help="dove scrivere il jpg")
    ap.add_argument("--qualita", type=int, default=88)
    args = ap.parse_args()

    dove = pathlib.Path(args.dove) if args.dove \
        else pathlib.Path(__file__).resolve().parent / "predefinito.jpg"

    img = genera()
    # optimize + progressive: qualche decina di KB in meno a parita' di resa.
    img.save(dove, "JPEG", quality=args.qualita, optimize=True, progressive=True)

    kb = dove.stat().st_size / 1024
    print(f"{dove}  {LARGHEZZA}x{ALTEZZA}  {kb:.0f} KB")


if __name__ == "__main__":
    main()
