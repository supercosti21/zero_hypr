# Perché il config è fatto così

`config.json` non ha commenti perché il suo schema dichiara
`additionalProperties: false`: le chiavi `"//"` che molti usano come commento
non sono valide, e un editor con language server le segnala come errore. Le
motivazioni stanno quindi qui.

**Posizione.** In alto a destra, `control-center-margin-top: 54`. Il numero è
38 (altezza barra) + 8 (margine superiore della barra) + 8 di respiro: il
pannello sembra appeso alla campanella invece di coprirla.

**`layer-shell-cover-screen: false`.** Con `true` il pannello stende un velo
invisibile su tutto lo schermo: un click ovunque lo chiude, ma nel frattempo
intercetta gli eventi. Su un tiling puro dà la sensazione che il desktop sia
bloccato.

**`timeout-critical: 0`.** Le notifiche critiche non scompaiono da sole. È
l'unico caso in cui vale la pena essere insistenti.

**`ignore-gtk-theme: true`.** Usa solo `style.css`, non il tema GTK di sistema.
Serve perché i colori devono venire da matugen, non dal tema delle app.

**Niente `buttons-grid`.** I toggle di wi-fi e bluetooth sono già in barra:
duplicarli qui sarebbe lo stesso errore delle icone doppie nel tray.

**Ricaricare:** `swaync-client -R` per il config, `-rs` per il solo stile.
