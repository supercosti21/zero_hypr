#!/usr/bin/env python3
"""
colori-terminale.py — costruisce la palette del terminale a partire dalla
palette Material You di matugen, con il contrasto garantito per costruzione.

PERCHE' ESISTE. Il terminale prendeva i 16 colori ANSI dalla palette "base16"
di matugen. Sembra la scelta giusta — e' l'unico blocco di 16 colori che
matugen produce — ma base16 li ricava come *scala tonale della stessa tinta*
dello sfondo: base00..base07 sono i passi dal fondo al testo, base08..base0f
sono accenti derivati dalla stessa sorgente. Su uno sfondo monocromatico
(quello che ha fatto scoprire la cosa: un'immagine tutta verde-petrolio) il
risultato misurato era

    nero 1.10   verde 1.13   giallo 1.37   blu 1.02   magenta 1.00   ciano 1.06

cioe' rapporti di contrasto fra 1.0 e 1.4 su un minimo leggibile di 4.5:
fastfetch, `ls`, i prompt e i diff di git scrivevano nero su nero. Non era un
caso sfortunato: base16 non ha nessun vincolo di contrasto, quindi prima o poi
ricapita con qualunque sfondo poco variegato.

COSA FA INVECE. Le sei tinte ANSI (rosso, verde, giallo, blu, magenta, ciano)
partono dai loro angoli di tinta canonici in OKLCh, non dallo sfondo: rosso
resta rosso, e i `git diff` restano leggibili. Della palette dello sfondo si
prende solo l'accento, che *inclina* le tinte di pochi gradi (al massimo 16):
abbastanza perche' la palette sembri intonata all'immagine, troppo poco perche'
un colore possa diventare un altro.

Poi, per ogni colore, la luminosita' non e' scelta a occhio: si cerca la L piu'
bassa che raggiunge il rapporto di contrasto richiesto contro lo sfondo
effettivo. "Piu' bassa" perche' in OKLCh la croma disponibile cala salendo di
luminosita': fermarsi appena raggiunta la soglia da' il colore piu' vivo che
resta leggibile, invece di uno slavato.

Le soglie sono una scala: normali 5.2, brillanti 7.5. Cosi' il contrasto e'
sempre sopra il minimo AA (4.5) e "brillante" e' davvero piu' chiaro di
"normale", che e' l'altra meta' dell'usabilita': un tema in cui i due si
somigliano rende indistinguibili tutti i programmi che usano la coppia.

I colori che invece arrivano da matugen e vanno benissimo (testo, cursore,
selezione: Material You garantisce il contrasto sulle coppie on_*) NON vengono
reinventati: si verificano, e solo se una coppia e' sotto soglia si sposta la
sua luminosita' lasciando tinta e saturazione dov'erano.

USO
    matugen --quiet -j hex image FOTO | colori-terminale.py
    ... | colori-terminale.py --prova --tabella     controlla senza scrivere
    colori-terminale.py --json palette.json --out /dev/stdout

Lo chiama ~/.config/hypr/scripts/sfondo.sh (SUPER+W) subito dopo matugen.
Nessuna dipendenza oltre alla libreria standard: la matematica del colore e'
cinquanta righe e non vale un pacchetto in piu' da installare a mano.
"""

import argparse
import json
import math
import sys
from pathlib import Path

# ------------------------------------------------------------------ le soglie
# Rapporti di contrasto WCAG contro lo sfondo del terminale. Sono l'unica cosa
# da toccare per rendere la palette piu' o meno spinta.
#
#   4.5 = minimo AA per il testo normale.  7.0 = AAA.
#
# Il nero ANSI (indice 0) sta di proposito sotto: quando si usa e' quasi
# sempre come fondo di un blocco, non come testo. 3.0 lo tiene comunque
# distinguibile dallo sfondo invece di farlo sparire.
CONTRASTO = {
    "nero": 3.0,
    "nero_brillante": 4.6,
    "normale": 5.2,
    "brillante": 7.5,
    "bianco": 10.0,
    "bianco_brillante": 13.5,
    "attenuato": 4.6,   # testo con SGR 2 (dim): lo usano fastfetch, systemd, git
    "testo": 10.0,
    "testo_attenuato": 6.5,    # sopra il minimo AA: e' testo, non decorazione
    "testo_brillante": 17.0,   # oltre il massimo raggiungibile: va al bianco
    "cursore": 4.5,
    "selezione": 7.0,   # testo dentro la selezione, contro il fondo selezione
}

# Sopra la soglia della famiglia, ogni tinta ha un suo margine in piu'. Non e'
# decorazione: se tutti e sei i colori stanno esattamente sulla soglia hanno per
# costruzione la stessa luminanza, e allora si distinguono SOLO per tinta. Chi
# ha un deficit di visione dei colori (rosso/verde: una persona su dodici fra i
# maschi) non li distingue piu', e in bianco e nero — screenshot, stampa, foto
# di uno schermo — nemmeno gli altri.
#
# I valori seguono l'ordine di luminosita' che i temi ANSI hanno da sempre
# (giallo il piu' chiaro, blu e rosso i piu' scuri): oltre ad aiutare, e'
# quello che l'occhio si aspetta.
BONUS = {
    "red": 0.0,
    "green": 1.2,
    "yellow": 2.0,
    "blue": 0.0,
    "magenta": 0.4,
    "cyan": 0.8,
}

# Croma (saturazione OKLCh) per famiglia. Valori alti danno colori piu' vivi ma
# vengono tagliati dal gamut sRGB alle luminosita' che servono per il
# contrasto: questi sono quelli che sopravvivono quasi sempre interi.
CROMA = {
    "normale": 0.130,
    "brillante": 0.160,
    "attenuato": 0.080,
    # I quattro grigi: croma minima, non zero. Un grigio con un filo della
    # tinta dell'accento sta insieme al resto; un grigio neutro puro stacca.
    "grigio": 0.020,
    "grigio_chiaro": 0.010,
}

# Angoli di tinta OKLCh dei sei colori ANSI. Sono le tinte dei primari e
# secondari sRGB, cioe' quello che un programma si aspetta quando chiede
# "rosso": non vanno derivate dallo sfondo, o `git diff` diventa illeggibile.
TINTE = {
    "red": 29.2,
    "green": 142.5,
    "yellow": 100.0,   # 109.8 e' il giallo sRGB puro; qui e' tirato verso
                       # l'ambra, che a parita' di contrasto resta piu' caldo
                       # e non si confonde col verde.
    "blue": 264.0,
    "magenta": 328.4,
    "cyan": 195.0,
}

# Quanto l'accento dello sfondo puo' inclinare le tinte sopra.
FORZA_TINTA = 0.14      # frazione della distanza dall'accento
TETTO_TINTA = 8.0       # gradi, comunque non oltre

# Ma non tutte le tinte reggono la stessa inclinazione. Rosso e giallo portano
# un significato — errore, riga cancellata, avviso — e vanno riconosciuti in un
# decimo di secondo: a 16 gradi verso un accento freddo il rosso diventava
# terracotta (#c4734d) e il giallo virava all'oliva. Su quelle due
# l'inclinazione vale meta'; le altre quattro non hanno lo stesso problema.
PESO_TINTA = {
    "red": 0.5,
    "yellow": 0.5,
    "green": 1.0,
    "blue": 1.0,
    "magenta": 1.0,
    "cyan": 1.0,
}


# ------------------------------------------------------- conversioni di colore
def da_hex(testo):
    t = testo.strip().lstrip("#")
    if len(t) == 8:                      # RRGGBBAA: l'alpha qui non serve
        t = t[:6]
    return tuple(int(t[i:i + 2], 16) / 255 for i in (0, 2, 4))


def a_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c * 255))) for c in rgb)


def _lineare(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gamma(c):
    # Deve funzionare anche fuori da [0,1] e restare monotona: e' cosi' che si
    # riconosce un colore OKLCh che esce dal gamut sRGB (canali < 0 o > 1)
    # invece di scoprirlo dopo averlo tagliato.
    if c < 0:
        return -_gamma(-c)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def luminanza(rgb):
    """Luminanza relativa WCAG."""
    r, g, b = (_lineare(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrasto(a, b):
    """Rapporto di contrasto WCAG fra due colori: da 1 (uguali) a 21."""
    x, y = luminanza(a), luminanza(b)
    if x < y:
        x, y = y, x
    return (x + 0.05) / (y + 0.05)


def rgb_a_oklch(rgb):
    r, g, b = (_lineare(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    A = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    B = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360


def _oklch_grezzo(L, C, h):
    hr = math.radians(h)
    A, B = C * math.cos(hr), C * math.sin(hr)
    l_ = L + 0.3963377774 * A + 0.2158037573 * B
    m_ = L - 0.1055613458 * A - 0.0638541728 * B
    s_ = L - 0.0894841775 * A - 1.2914855480 * B
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    return (
        _gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        _gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        _gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
    )


def oklch_a_rgb(L, C, h):
    """OKLCh -> sRGB. Fuori dal gamut si abbassa la croma, non si tagliano i
    canali: tagliare sposta la tinta (un blu troppo saturo diventa viola)."""
    if C > 0 and not all(-1e-4 <= c <= 1 + 1e-4 for c in _oklch_grezzo(L, C, h)):
        basso, alto = 0.0, C
        for _ in range(20):
            mezzo = (basso + alto) / 2
            if all(-1e-4 <= c <= 1 + 1e-4 for c in _oklch_grezzo(L, mezzo, h)):
                basso = mezzo
            else:
                alto = mezzo
        C = basso
    return tuple(max(0.0, min(1.0, c)) for c in _oklch_grezzo(L, C, h))


# ------------------------------------------------------- il motore: cerca la L
PASSI_L = 512


def _per_contrasto(C, h, fondo, bersaglio, L_ideale):
    """Colore di tinta h e croma C che stacca da `fondo` di almeno
    `bersaglio`, con la luminosita' piu' vicina possibile a L_ideale.

    La ricerca e' una scansione su tutta la scala di luminosita' invece di una
    bisezione: dopo il rientro nel gamut il contrasto non e' perfettamente
    monotono in L, e su 512 passi la scansione costa comunque niente (sono 16
    colori, una volta per cambio sfondo). Se nessuna luminosita' raggiunge la
    soglia — sfondo di mezzo tono, dove nemmeno il bianco basterebbe — si
    prende il massimo contrasto ottenibile: meglio il meglio possibile che un
    colore scelto a caso.
    """
    migliore, migliore_k, scelto, scarto = None, -1.0, None, 9.9
    for i in range(PASSI_L + 1):
        L = i / PASSI_L
        colore = oklch_a_rgb(L, C, h)
        k = contrasto(colore, fondo)
        if k > migliore_k:
            migliore, migliore_k = colore, k
        if k >= bersaglio and abs(L - L_ideale) < scarto:
            scelto, scarto = colore, abs(L - L_ideale)
    return scelto if scelto is not None else migliore


def costruisci(tinta, croma, fondo, bersaglio):
    """Colore nuovo: tinta e croma le decidiamo noi, la luminosita' la decide
    il contrasto. L_ideale = quella del fondo, cosi' fra tutte le luminosita'
    che vanno bene si prende la prima utile e il colore resta vivo."""
    return _per_contrasto(croma, tinta, fondo, bersaglio, rgb_a_oklch(fondo)[0])


def correggi(colore, fondo, bersaglio):
    """Colore che arriva da matugen: si tiene com'e' se il contrasto basta,
    altrimenti si sposta solo la luminosita', il meno possibile. Tinta e
    saturazione restano quelle della palette dello sfondo."""
    if contrasto(colore, fondo) >= bersaglio:
        return colore
    L, C, h = rgb_a_oklch(colore)
    return _per_contrasto(C, h, fondo, bersaglio, L)


def verso(colore, fondo, bersaglio):
    """Come correggi(), ma punta al contrasto invece di accontentarsi: sposta
    la luminosita' fino al rapporto richiesto anche quando quello di partenza
    era piu' alto. Serve per le varianti attenuata e brillante del testo, che
    con correggi() sarebbero venute identiche al testo normale (che di
    contrasto ne ha di solito 14) e quindi indistinguibili."""
    L, C, h = rgb_a_oklch(colore)
    scelto, scarto = colore, 99.0
    for i in range(PASSI_L + 1):
        L_prova = i / PASSI_L
        prova = oklch_a_rgb(L_prova, C, h)
        d = abs(contrasto(prova, fondo) - bersaglio)
        if d < scarto:
            scelto, scarto = prova, d
    return scelto


def distingui(colore, fondo, minimo=1.5):
    """Per i fondi (selezione, barra di ricerca): non devono essere leggibili,
    devono solo vedersi come blocco distinto dallo sfondo."""
    return correggi(colore, fondo, minimo)


def inclina(tinta, accento_h, forza, peso=1.0):
    """Tira una tinta canonica verso l'accento dello sfondo, con un tetto: e'
    quello che rende la palette intonata all'immagine senza che il rosso
    diventi arancione e il verde ciano."""
    delta = ((accento_h - tinta + 180) % 360) - 180
    tetto = TETTO_TINTA * peso
    delta = max(-tetto, min(tetto, delta * forza * peso))
    return (tinta + delta) % 360


# --------------------------------------------------------------- la palette
def leggi_palette(dati):
    """Estrae i ruoli che servono dal json di matugen (`matugen -j hex`).
    Il json ha ogni colore in tre varianti (dark/light/default): si usa
    `default`, che e' la modalita' con cui matugen ha girato."""
    colori = dati.get("colors", {})

    def ruolo(nome, ripiego):
        voce = colori.get(nome)
        if not voce:
            return da_hex(ripiego)
        return da_hex(voce.get("default", voce.get("dark", {})).get("color", ripiego))

    return {
        "fondo": ruolo("surface", "#101010"),
        "testo": ruolo("on_surface", "#e6e6e6"),
        "accento": ruolo("primary", "#8ab4f8"),
        "su_accento": ruolo("on_primary", "#101010"),
        "selezione": ruolo("surface_container_highest", "#303030"),
        "contenitore": ruolo("surface_container_high", "#262626"),
        "avviso": ruolo("tertiary", "#f0c674"),
        "errore": ruolo("error", "#ff6f60"),
    }


def genera(dati):
    p = leggi_palette(dati)
    fondo = p["fondo"]

    # Se lo sfondo e' quasi in bianco e nero l'accento non ha una tinta
    # sensata: inclinare le tinte verso il rumore le sballerebbe. In quel caso
    # si tengono le tinte canoniche pulite.
    L_acc, C_acc, h_acc = rgb_a_oklch(p["accento"])
    forza = FORZA_TINTA if C_acc >= 0.02 else 0.0
    tinte = {nome: inclina(t, h_acc, forza, PESO_TINTA[nome])
             for nome, t in TINTE.items()}
    h_grigio = h_acc if forza else rgb_a_oklch(fondo)[2]

    def sei(famiglia):
        # Sugli attenuati il bonus vale meta': devono restare attenuati.
        peso = 0.5 if famiglia == "attenuato" else 1.0
        return {
            nome: costruisci(tinte[nome], CROMA[famiglia], fondo,
                             CONTRASTO[famiglia] + BONUS[nome] * peso)
            for nome in TINTE
        }

    normale = sei("normale")
    brillante = sei("brillante")
    attenuato = sei("attenuato")

    normale["black"] = costruisci(h_grigio, CROMA["grigio"], fondo,
                                 CONTRASTO["nero"])
    normale["white"] = costruisci(h_grigio, CROMA["grigio_chiaro"], fondo,
                                  CONTRASTO["bianco"])
    brillante["black"] = costruisci(h_grigio, CROMA["grigio"], fondo,
                                    CONTRASTO["nero_brillante"])
    brillante["white"] = costruisci(h_grigio, CROMA["grigio_chiaro"], fondo,
                                    CONTRASTO["bianco_brillante"])
    attenuato["black"] = normale["black"]
    attenuato["white"] = costruisci(h_grigio, CROMA["grigio_chiaro"], fondo,
                                    CONTRASTO["attenuato"])

    testo = correggi(p["testo"], fondo, CONTRASTO["testo"])

    # Cursore: due vincoli, non uno. Deve vedersi sullo sfondo (altrimenti si
    # perde nel prompt) e il carattere sotto deve restare leggibile *dentro* il
    # cursore, che e' il caso che si dimentica sempre.
    cursore = correggi(p["accento"], fondo, CONTRASTO["cursore"])
    testo_cursore = correggi(p["su_accento"], cursore, CONTRASTO["selezione"])

    # Selezione, ricerca, barra dei messaggi, suggerimenti dei link: ogni
    # coppia fondo/testo passa dallo stesso controllo. Sono i posti dove un
    # tema generato di solito si rompe, perche' nessuno li guarda.
    sel_fondo = distingui(p["selezione"], fondo)
    sel_testo = correggi(p["testo"], sel_fondo, CONTRASTO["selezione"])

    ric_fondo = distingui(p["contenitore"], fondo)
    ric_testo = correggi(p["testo"], ric_fondo, CONTRASTO["selezione"])
    fuoco_fondo = correggi(p["avviso"], fondo, CONTRASTO["cursore"])
    fuoco_testo = correggi(fondo, fuoco_fondo, CONTRASTO["selezione"])

    barra_fondo = distingui(p["contenitore"], fondo)
    barra_testo = correggi(p["testo"], barra_fondo, CONTRASTO["selezione"])

    sugg_fondo = correggi(p["avviso"], fondo, CONTRASTO["cursore"])
    sugg_testo = correggi(fondo, sugg_fondo, CONTRASTO["selezione"])
    sugg2_fondo = distingui(p["selezione"], fondo)
    sugg2_testo = correggi(p["testo"], sugg2_fondo, CONTRASTO["selezione"])

    return {
        "fondo": fondo,
        "testo": testo,
        # Attenuato e brillante devono *distinguersi* dal testo normale, non
        # solo essere leggibili: qui si punta al contrasto, non si accetta.
        "testo_attenuato": verso(p["testo"], fondo, CONTRASTO["testo_attenuato"]),
        "testo_brillante": verso(p["testo"], fondo, CONTRASTO["testo_brillante"]),
        "cursore": cursore,
        "testo_cursore": testo_cursore,
        "sel_fondo": sel_fondo,
        "sel_testo": sel_testo,
        "ric_fondo": ric_fondo,
        "ric_testo": ric_testo,
        "fuoco_fondo": fuoco_fondo,
        "fuoco_testo": fuoco_testo,
        "barra_fondo": barra_fondo,
        "barra_testo": barra_testo,
        "sugg_fondo": sugg_fondo,
        "sugg_testo": sugg_testo,
        "sugg2_fondo": sugg2_fondo,
        "sugg2_testo": sugg2_testo,
        "normale": normale,
        "brillante": brillante,
        "attenuato": attenuato,
    }


# ------------------------------------------------------------------- il file
ORDINE = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

INTESTAZIONE = """\
# GENERATO — non modificare a mano.
# Sorgente: ~/.config/hypr/scripts/colori-terminale.py, che gira dopo matugen
# ad ogni cambio sfondo (SUPER+W). Alacritty rilegge la config al salvataggio:
# le finestre aperte cambiano colore senza riaprirle.
#
# I 16 colori ANSI non arrivano dalla palette base16 di matugen (che e' una
# scala tonale di una sola tinta e su sfondi monocromatici dava contrasti da
# 1.0, cioe' testo invisibile): sono costruiti dalle tinte ANSI canoniche,
# inclinate di pochi gradi verso l'accento dello sfondo, con la luminosita'
# risolta per raggiungere un contrasto minimo garantito su QUESTO sfondo.
#
# Contrasto WCAG misurato contro il fondo {fondo} — minimo leggibile 4.5:
{tabella}
"""


def riga_tabella(nomi, colori, fondo):
    pezzi = []
    for nome in nomi:
        k = contrasto(colori[nome], fondo)
        pezzi.append(f"{nome[:3]} {k:4.1f}")
    return "  ".join(pezzi)


def rendi(c):
    fondo = c["fondo"]
    tabella = "\n".join(
        "#   " + etichetta.ljust(10) + riga_tabella(ORDINE, c[chiave], fondo)
        for etichetta, chiave in (
            ("normali", "normale"),
            ("brillanti", "brillante"),
            ("attenuati", "attenuato"),
        )
    )
    tabella += (
        f"\n#   testo     {contrasto(c['testo'], fondo):4.1f}"
        f"   cursore {contrasto(c['cursore'], fondo):4.1f}"
        f"   selezione {contrasto(c['sel_testo'], c['sel_fondo']):4.1f}"
        f"   ricerca {contrasto(c['ric_testo'], c['ric_fondo']):4.1f}"
    )

    fuori = [INTESTAZIONE.format(fondo=a_hex(fondo), tabella=tabella)]
    agg = fuori.append

    agg("[colors.primary]")
    agg(f'background       = "{a_hex(fondo)}"')
    agg(f'foreground       = "{a_hex(c["testo"])}"')
    # dim_foreground/bright_foreground: senza questi due Alacritty ricava il
    # testo attenuato scurendo il primo piano di un fattore fisso, che su un
    # fondo scuro lo porta sotto soglia. Meglio dirglielo noi.
    agg(f'dim_foreground   = "{a_hex(c["testo_attenuato"])}"')
    agg(f'bright_foreground = "{a_hex(c["testo_brillante"])}"')
    agg("")
    agg("[colors.cursor]")
    agg(f'text   = "{a_hex(c["testo_cursore"])}"')
    agg(f'cursor = "{a_hex(c["cursore"])}"')
    agg("")
    agg("[colors.vi_mode_cursor]")
    agg(f'text   = "{a_hex(c["testo_cursore"])}"')
    agg(f'cursor = "{a_hex(c["cursore"])}"')
    agg("")
    agg("[colors.selection]")
    agg(f'text       = "{a_hex(c["sel_testo"])}"')
    agg(f'background = "{a_hex(c["sel_fondo"])}"')
    agg("")
    agg("[colors.search.matches]")
    agg(f'foreground = "{a_hex(c["ric_testo"])}"')
    agg(f'background = "{a_hex(c["ric_fondo"])}"')
    agg("")
    agg("[colors.search.focused_match]")
    agg(f'foreground = "{a_hex(c["fuoco_testo"])}"')
    agg(f'background = "{a_hex(c["fuoco_fondo"])}"')
    agg("")
    agg("[colors.footer_bar]")
    agg(f'foreground = "{a_hex(c["barra_testo"])}"')
    agg(f'background = "{a_hex(c["barra_fondo"])}"')
    agg("")
    agg("[colors.hints.start]")
    agg(f'foreground = "{a_hex(c["sugg_testo"])}"')
    agg(f'background = "{a_hex(c["sugg_fondo"])}"')
    agg("")
    agg("[colors.hints.end]")
    agg(f'foreground = "{a_hex(c["sugg2_testo"])}"')
    agg(f'background = "{a_hex(c["sugg2_fondo"])}"')

    for titolo, chiave in (("normal", "normale"), ("bright", "brillante"),
                           ("dim", "attenuato")):
        agg("")
        agg(f"[colors.{titolo}]")
        for nome in ORDINE:
            agg(f'{nome:<7} = "{a_hex(c[chiave][nome])}"')

    return "\n".join(fuori) + "\n"


def tabella_testo(c):
    """Report leggibile per --tabella: serve a controllare a mano che dopo un
    cambio sfondo nessuna coppia sia finita sotto soglia."""
    fondo = c["fondo"]
    righe = [f"fondo {a_hex(fondo)}", ""]
    for etichetta, chiave, soglia in (
        ("normale  ", "normale", CONTRASTO["normale"]),
        ("brillante", "brillante", CONTRASTO["brillante"]),
        ("attenuato", "attenuato", CONTRASTO["attenuato"]),
    ):
        for nome in ORDINE:
            colore = c[chiave][nome]
            k = contrasto(colore, fondo)
            atteso = soglia + BONUS.get(nome, 0.0) * (0.5 if chiave == "attenuato" else 1.0)
            if nome == "black":
                atteso = CONTRASTO["nero_brillante"] if chiave == "brillante" else CONTRASTO["nero"]
            elif nome == "white":
                atteso = {"normale": CONTRASTO["bianco"],
                          "brillante": CONTRASTO["bianco_brillante"],
                          "attenuato": CONTRASTO["attenuato"]}[chiave]
            righe.append(f"{etichetta} {nome:<8} {a_hex(colore)}  {k:5.2f}"
                         f"  {'ok' if k + 0.05 >= atteso else 'SOTTO SOGLIA'}")
        righe.append("")
    for etichetta, testo, sfondo in (
        ("testo", c["testo"], fondo),
        ("testo attenuato", c["testo_attenuato"], fondo),
        ("cursore", c["cursore"], fondo),
        ("testo nel cursore", c["testo_cursore"], c["cursore"]),
        ("selezione", c["sel_testo"], c["sel_fondo"]),
        ("ricerca", c["ric_testo"], c["ric_fondo"]),
        ("ricerca a fuoco", c["fuoco_testo"], c["fuoco_fondo"]),
        ("barra messaggi", c["barra_testo"], c["barra_fondo"]),
        ("suggerimento", c["sugg_testo"], c["sugg_fondo"]),
    ):
        righe.append(f"{etichetta:<18} {contrasto(testo, sfondo):5.2f}")
    return "\n".join(righe)


def main():
    ap = argparse.ArgumentParser(
        description="Palette del terminale a contrasto garantito dalla "
                    "palette Material You di matugen.")
    ap.add_argument("--json", metavar="FILE",
                    help="json di matugen (`matugen -j hex`); default: stdin")
    ap.add_argument("--out", metavar="FILE",
                    default=str(Path.home() / ".config/alacritty/colori.toml"),
                    help="file da scrivere (default: ~/.config/alacritty/colori.toml)")
    ap.add_argument("--tabella", action="store_true",
                    help="stampa i contrasti ottenuti, per controllo")
    ap.add_argument("--prova", action="store_true",
                    help="calcola e riporta, senza scrivere niente")
    args = ap.parse_args()

    try:
        grezzo = Path(args.json).read_text() if args.json else sys.stdin.read()
        dati = json.loads(grezzo)
    except (OSError, ValueError) as e:
        sys.exit(f"colori-terminale: palette non leggibile: {e}")

    colori = genera(dati)
    testo = rendi(colori)

    # Scrittura atomica: Alacritty guarda il file e lo rilegge appena cambia.
    # Scrivendo in place lo si becca a meta' e il terminale si lamenta di un
    # TOML troncato; con il rename il file passa da vecchio a nuovo di colpo.
    destinazione = Path(args.out)
    if args.prova:
        pass
    elif destinazione.name == "stdout" or str(destinazione) == "/dev/stdout":
        sys.stdout.write(testo)
    else:
        destinazione.parent.mkdir(parents=True, exist_ok=True)
        temporaneo = destinazione.with_name(destinazione.name + ".nuovo")
        temporaneo.write_text(testo)
        temporaneo.replace(destinazione)

    if args.tabella:
        print(tabella_testo(colori))


if __name__ == "__main__":
    main()
