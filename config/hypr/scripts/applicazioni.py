#!/usr/bin/env python3
"""applicazioni.py — l'elenco delle applicazioni, pronto per fuzzel --dmenu.

    applicazioni.py            stampa l'elenco (formato dmenu con icone)
    applicazioni.py --usata N  segna che la voce N e' stata scelta
    applicazioni.py --leggibile  stampa in chiaro, per guardarci dentro

Sola libreria standard, come colori-terminale.py. Niente pip, niente
dipendenze: su questa macchina python c'e' comunque perche' serve ai colori.

PERCHE' ESISTE
fuzzel sa gia' elencare le applicazioni da solo, ed e' bravo. Ma in quella
modalita' legge le voci da dentro se stesso e non accetta niente dallo standard
input: o mostra le app, o mostra la lista che gli dai tu — mai le due cose
insieme. Siccome menu.sh vuole app E azioni di sistema nella stessa finestra
(un tasto solo, come da richiesta), l'elenco delle app va costruito qui.

Il costo e' questo file. Il guadagno e' che SUPER+R apre una cosa sola, dove
scrivi "fire" e apri il browser oppure ">" e ti ritrovi in un altro mondo,
senza dover ricordare due scorciatoie diverse.

Chi vuole il launcher nativo ce l'ha ancora su SUPER+D, che non passa di qui.

NIENTE CACHE, ed e' una scelta misurata: con 306 file .desktop (un sistema
vissuto ne ha meno) questo script impiega 33 ms, di cui 10 sono l'avvio di
python. Una cache ne risparmierebbe una ventina — impercettibili — in cambio
della logica per invalidarla, che e' proprio il genere di cosa che poi sbaglia:
installi un programma e non compare nel menu finche' non capisci che c'e' una
cache da buttare. Venti millisecondi non valgono quel rischio.

IL FORMATO DMENU CON ICONE
fuzzel implementa il protocollo esteso di rofi: dopo il testo della voce, un
byte NUL, poi "icon", poi 0x1f, poi il nome dell'icona.
    Firefox\\0icon\\x1ffirefox
Il nome dell'icona lo risolve il tema in uso (Papirus-Dark), quindi le icone
seguono il tema come tutto il resto.

LE TRAPPOLE DEI FILE .desktop, che sono il motivo per cui questo file e' lungo
piu' di venti righe:
  · NoDisplay=true    -> la voce esiste ma non va mostrata (sono le voci di
                         servizio: gestori MIME, pezzi di altri programmi);
  · Hidden=true       -> l'utente l'ha cancellata; vale come "non esiste";
  · TryExec=          -> mostra la voce solo se QUEL programma c'e' davvero.
                         Serve ai pacchetti che installano .desktop per
                         programmi opzionali;
  · %f %u %F %U %i %c %k -> segnaposto per file e URL da passare al programma.
                         Vanno TOLTI, altrimenti la shell prova ad aprire un
                         file che si chiama "%U";
  · Terminal=true     -> va lanciato dentro un terminale, se no non si vede
                         niente e sembra che non abbia fatto nulla;
  · precedenza        -> ~/.local/share/applications vince su /usr/share, cosi'
                         una voce personalizzata sostituisce quella di sistema
                         invece di comparire due volte.
"""

import os
import pathlib
import shutil
import sys

# In ordine di precedenza CRESCENTE: chi viene dopo sovrascrive.
def cartelle_applicazioni():
    dati = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    casa = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    percorsi = [pathlib.Path(d) / "applications" for d in dati.split(":") if d]
    percorsi.append(pathlib.Path(casa) / "applications")
    return percorsi


def cache_percorso():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return pathlib.Path(base) / "zero_hypr"


SEGNAPOSTO = ("%f", "%F", "%u", "%U", "%i", "%c", "%k", "%v", "%m")


def pulisci_exec(riga):
    """Toglie i segnaposto dalla riga Exec e normalizza gli spazi."""
    pezzi = [p for p in riga.split() if p not in SEGNAPOSTO]
    # %-qualcosa attaccato a un'altra parola (raro ma esiste): via anche quello.
    pezzi = [p for p in pezzi if not (len(p) == 2 and p.startswith("%"))]
    return " ".join(pezzi)


def leggi_desktop(percorso):
    """Legge un .desktop e restituisce un dizionario, o None se va ignorato.

    Si legge SOLO il gruppo [Desktop Entry]: i gruppi "Desktop Action" in fondo
    descrivono le azioni del menu contestuale (per esempio "Apri una nuova
    finestra in incognito") e hanno le loro righe Name ed Exec. Senza questo
    controllo si finisce con tre voci "Firefox" nell'elenco.
    """
    dentro = False
    campi = {}
    try:
        testo = percorso.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    for riga in testo.splitlines():
        riga = riga.strip()
        if riga.startswith("["):
            if dentro:
                break                      # e' cominciato un altro gruppo
            dentro = riga == "[Desktop Entry]"
            continue
        if not dentro or "=" not in riga or riga.startswith("#"):
            continue
        chiave, _, valore = riga.partition("=")
        chiave = chiave.strip()
        # Le chiavi tradotte (Name[it]) si ignorano: la lingua di sistema qui e'
        # inglese di proposito, e mescolare le due darebbe un elenco meta' e
        # meta'. La chiave senza parentesi e' sempre quella inglese.
        if "[" not in chiave:
            campi.setdefault(chiave, valore.strip())

    if campi.get("Type", "Application") != "Application":
        return None
    if campi.get("NoDisplay", "").lower() == "true":
        return None
    if campi.get("Hidden", "").lower() == "true":
        return None

    nome = campi.get("Name")
    comando = campi.get("Exec")
    if not nome or not comando:
        return None

    # TryExec: se quel programma non c'e', la voce non va mostrata.
    prova = campi.get("TryExec")
    if prova and not shutil.which(prova):
        return None

    return {
        "nome": nome,
        "exec": pulisci_exec(comando),
        "icona": campi.get("Icon", ""),
        "terminale": campi.get("Terminal", "").lower() == "true",
        "path": campi.get("Path", ""),
    }


def raccogli():
    """Tutte le applicazioni visibili, indicizzate per id (nome del file)."""
    trovate = {}
    for cartella in cartelle_applicazioni():
        if not cartella.is_dir():
            continue
        for f in sorted(cartella.rglob("*.desktop")):
            # L'id e' il percorso relativo alla cartella, come vuole la
            # specifica: cosi' kde/foo.desktop e foo.desktop restano distinti.
            try:
                ident = str(f.relative_to(cartella))
            except ValueError:
                ident = f.name
            voce = leggi_desktop(f)
            if voce is None:
                # Una voce nascosta in una cartella a precedenza piu' alta deve
                # nascondere anche quella di sistema, non lasciarla riemergere.
                trovate.pop(ident, None)
                continue
            trovate[ident] = voce
    return trovate


def leggi_frequenza():
    """Quante volte ogni voce e' stata scelta. Formato: 'conteggio nome'."""
    f = cache_percorso() / "frequenza"
    conteggi = {}
    try:
        for riga in f.read_text(encoding="utf-8").splitlines():
            n, _, nome = riga.partition(" ")
            if nome:
                conteggi[nome] = int(n)
    except (OSError, ValueError):
        pass
    return conteggi


def segna_usata(nome):
    """Incrementa il contatore di una voce.

    Serve perche' l'ordinamento per frequenza di fuzzel (sort-result) vale solo
    nella sua modalita' launcher: in dmenu l'ordine e' quello che gli dai tu.
    Senza questo, ogni apertura ripartirebbe da un elenco alfabetico e le tre
    app che usi davvero starebbero sparse in mezzo alle altre.
    """
    cartella = cache_percorso()
    cartella.mkdir(parents=True, exist_ok=True)
    conteggi = leggi_frequenza()
    conteggi[nome] = conteggi.get(nome, 0) + 1

    # Scrittura atomica: se la sessione muore a meta' non resta un file di
    # frequenze troncato. Stesso accorgimento di colori-terminale.py.
    dest = cartella / "frequenza"
    tmp = dest.with_suffix(".nuovo")
    tmp.write_text(
        "".join(f"{n} {v}\n" for v, n in sorted(conteggi.items(), key=lambda x: -x[1])),
        encoding="utf-8",
    )
    tmp.replace(dest)


def elenco_ordinato():
    voci = list(raccogli().values())
    conteggi = leggi_frequenza()
    # Prima le piu' usate, poi in ordine alfabetico senza badare a maiuscole.
    voci.sort(key=lambda v: (-conteggi.get(v["nome"], 0), v["nome"].lower()))
    return voci


def main():
    args = sys.argv[1:]

    if args and args[0] == "--usata":
        if len(args) < 2:
            sys.exit("uso: applicazioni.py --usata <nome>")
        segna_usata(" ".join(args[1:]))
        return

    if args and args[0] == "--comando":
        # Dal nome scelto nel menu al comando da lanciare. Stampa una riga
        #     terminale|<comando>     oppure     diretto|<comando>
        # e non esegue niente: ad avviare i programmi ci pensa menu.sh con
        # `hyprctl dispatch exec`, che li stacca da questo processo. Se li
        # lanciasse python, resterebbero figli di uno script che sta per
        # morire, e certi programmi se ne accorgono male.
        if len(args) < 2:
            sys.exit("uso: applicazioni.py --comando <nome>")
        cercato = " ".join(args[1:])
        for v in raccogli().values():
            if v["nome"] == cercato:
                segna_usata(cercato)
                tipo = "terminale" if v["terminale"] else "diretto"
                comando = v["exec"]
                if v["path"]:
                    # Alcuni programmi (gli script, soprattutto) non partono se
                    # non li lanci dalla loro cartella.
                    comando = f"cd {v['path']!r} && {comando}"
                print(f"{tipo}|{comando}")
                return
        sys.exit(1)                        # nessuna app con quel nome

    leggibile = "--leggibile" in args
    voci = elenco_ordinato()

    out = sys.stdout
    for v in voci:
        if leggibile:
            out.write(f"{v['nome']}\t{v['exec']}\t{v['icona']}"
                      f"\t{'terminale' if v['terminale'] else ''}\n")
        else:
            # Il protocollo icone di rofi, che fuzzel implementa.
            if v["icona"]:
                out.write(f"{v['nome']}\0icon\x1f{v['icona']}\n")
            else:
                out.write(f"{v['nome']}\n")


if __name__ == "__main__":
    main()
