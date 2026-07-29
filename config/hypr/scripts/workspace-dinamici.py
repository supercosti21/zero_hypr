#!/usr/bin/env python3
"""
workspace-dinamici.py — workspace dinamici in stile COSMIC.

REGOLA: esistono sempre i workspace occupati piu' UNO vuoto in coda, con un
minimo di 2. Riempi il 2 -> appare il 3. Svuoti il 3 -> sparisce. Non si
gestiscono mai a mano.

COME: Hyprland tiene in vita un workspace vuoto solo se e' dichiarato
`persistent`. Questo demone ascolta gli eventi sul socket2 e ricalcola quali
workspace devono essere persistent, parlando direttamente col socket dei
comandi.

Perche' non un ciclo con `hyprctl`: ogni chiamata a hyprctl e' un fork+exec
(~3 ms e una manciata di MB). Qui non si lancia alcun processo esterno e non
c'e' polling: si dorme sulla socket e ci si sveglia solo sugli eventi che
possono cambiare il conteggio. A regime: zero CPU.
"""

import json
import os
import socket
import sys

MINIMO = 2       # quanti tenerne sempre, anche a scrivania vuota
MASSIMO = 10     # coerente con i bind SUPER+1..0

runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
firma = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
if not firma:
    sys.exit("HYPRLAND_INSTANCE_SIGNATURE assente: questo script gira dentro Hyprland.")

BASE = os.path.join(runtime, "hypr", firma)
SOCK_CMD = os.path.join(BASE, ".socket.sock")
SOCK_EVT = os.path.join(BASE, ".socket2.sock")

# Eventi che possono cambiare quanti workspace servono. Filtrarli qui evita di
# ricalcolare ad ogni movimento del focus o del mouse, che sono i piu' frequenti.
INTERESSANTI = (
    b"openwindow>>",
    b"closewindow>>",
    b"movewindow>>",
    b"movewindowv2>>",
    b"workspace>>",
    b"workspacev2>>",
    b"createworkspace>>",
    b"createworkspacev2>>",
    b"destroyworkspace>>",
    b"destroyworkspacev2>>",
)


def comando(testo):
    """Una richiesta sul socket dei comandi.

    La connessione e' usa-e-getta: e' il protocollo di Hyprland, non una scelta
    di implementazione. Il socket degli eventi invece resta aperto per sempre.
    """
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCK_CMD)
        s.sendall(testo.encode())
        pezzi = []
        while True:
            blocco = s.recv(8192)
            if not blocco:
                break
            pezzi.append(blocco)
    return b"".join(pezzi).decode(errors="replace")


def quanti_servono():
    """Occupati + 1, con il minimo garantito."""
    ws = json.loads(comando("j/workspaces"))

    # id <= 0 sono gli special workspace (qui: lo scratchpad SUPER+S).
    # Non fanno parte della sequenza numerata e non vanno contati.
    rilevanti = [w["id"] for w in ws if w["id"] > 0 and w.get("windows", 0) > 0]

    # Il workspace attivo va tenuto in vita anche se vuoto: altrimenti andando
    # su un workspace alto con SUPER+7 lo si vedrebbe sparire sotto i piedi.
    try:
        attivo = json.loads(comando("j/activeworkspace")).get("id", 1)
        if attivo > 0:
            rilevanti.append(attivo)
    except (json.JSONDecodeError, AttributeError):
        pass

    return max(MINIMO, (max(rilevanti) if rilevanti else 0) + 1)


def applica(quanti, stato):
    """Allinea i flag persistent, scrivendo solo cio' che e' cambiato."""
    quanti = min(quanti, MASSIMO)
    voluto = {i: (i <= quanti) for i in range(1, MASSIMO + 1)}

    diverso = [(i, v) for i, v in voluto.items() if stato.get(i) != v]
    if not diverso:
        return   # caso piu' comune: niente da fare, nessun I/O

    # Un solo BATCH = una sola connessione invece di N.
    comando("[[BATCH]]" + ";".join(
        "keyword workspace {},persistent:{}".format(i, "true" if v else "false")
        for i, v in diverso
    ))
    stato.update(voluto)


def main():
    stato = {}
    applica(quanti_servono(), stato)   # allinea subito, senza aspettare un evento

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ev:
        ev.connect(SOCK_EVT)
        resto = b""
        while True:
            dati = ev.recv(8192)
            if not dati:
                break               # Hyprland ha chiuso: la sessione sta finendo
            resto += dati

            # Un recv puo' contenere piu' eventi, o mezzo evento: si tiene da
            # parte l'ultimo pezzo incompleto.
            *righe, resto = resto.split(b"\n")

            if any(r.startswith(INTERESSANTI) for r in righe):
                applica(quanti_servono(), stato)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError, ConnectionError):
        pass
