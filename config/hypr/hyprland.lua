--------------------------------------------------------------------------------
--  Hyprland — Acer Nitro ANV15-51 (i9-13900H + Iris Xe / RTX 4060 Max-Q)
--  Impostazione: tiling puro, tastiera-first, orientato a sviluppo e batteria.
--  COSMIC resta installato: si sceglie la sessione dal greeter al login.
--
--  FORMATO: Lua. Il vecchio hyprland.conf resta accanto come riferimento ma
--  NON viene piu' letto: quando esiste un .lua, Hyprland ignora il .conf.
--  Per tornare indietro basta rinominare questo file.
--------------------------------------------------------------------------------

local home    = os.getenv("HOME")
local scripts = home .. "/.config/hypr/scripts"


--------------------------------------------------------------------------------
--  MONITOR
--------------------------------------------------------------------------------
-- eDP-1 e' il pannello interno: 1920x1080, 180 Hz, scala 1 (a 15" FHD non serve).
-- "bitdepth,8" e' il default; VRR si abilita piu' sotto in misc.vrr.
hl.monitor({
    output   = "eDP-1",
    mode     = "1920x1080@180",
    position = "0x0",
    scale    = "1",
})

-- Qualsiasi monitor esterno collegato in futuro: risoluzione preferita, a destra.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "1",
})


--------------------------------------------------------------------------------
--  GPU IBRIDA  —  la parte piu' importante di questo file
--------------------------------------------------------------------------------
-- Il pannello eDP-1 e' cablato alla Intel Iris Xe. Facciamo comporre il desktop
-- alla iGPU: la RTX 4060 resta sospesa (runtime PM "auto") e non brucia 10-15 W
-- per disegnare una barra e un terminale.
--
-- Elenchiamo COMUNQUE entrambe le schede, Intel per prima. La prima e' il device
-- di rendering primario; tenere anche la NVIDIA in lista serve a non perdere le
-- uscite video eventualmente cablate alla dGPU (tipicamente l'HDMI sui Nitro).
--
-- Non si usa /dev/dri/cardN perche' la numerazione cambia da un boot all'altro,
-- ma nemmeno /dev/dri/by-path/: aquamarine separa questa lista con ":", e i nomi
-- by-path contengono gia' i due punti dell'indirizzo PCI (pci-0000:00:02.0-card),
-- quindi verrebbero spezzati -> "Found no gpus to use, cannot continue".
-- Si usano invece due symlink stabili e senza due punti, creati dalla regola
-- udev /etc/udev/rules.d/72-gpu.rules.
hl.env("AQ_DRM_DEVICES", "/dev/dri/igpu:/dev/dri/dgpu")

-- Per far girare un singolo programma sulla RTX: prefissalo con `prime-run`.
--   prime-run blender          prime-run steam         prime-run glxinfo -B
-- Funziona a prescindere da AQ_DRM_DEVICES: l'offload avviene a livello di
-- applicazione (GLVND / Vulkan), non di compositor.


--------------------------------------------------------------------------------
--  VARIABILI D'AMBIENTE
--------------------------------------------------------------------------------
-- --- Cursore ---
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- --- Toolkit ---
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("SDL_VIDEODRIVER", "wayland")

-- --- Electron / Chromium: Brave e Trae ---
-- Senza questo girano su XWayland: font sfocati, piu' CPU, niente scroll fluido.
-- Con "auto" usano Wayland nativo.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- --- Java (Trae/IDE che usano AWT) ---
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")


--------------------------------------------------------------------------------
--  AVVIO AUTOMATICO
--  L'equivalente Lua di exec-once: l'evento "hyprland.start" scatta una volta
--  sola all'avvio del compositore e NON si ripete a ogni `hyprctl reload`.
--------------------------------------------------------------------------------
hl.on("hyprland.start", function()
    -- Agente polkit: e' cio' che fa comparire il popup grafico per la password
    -- root. Senza, pkexec e le richieste di privilegi falliscono in silenzio.
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

    -- Tema delle app GTK: senza settings-daemon va applicato a mano ad ogni avvio.
    hl.exec_cmd(scripts .. "/tema-gtk.sh")

    -- Sfondo, barra, notifiche
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("waybar")
    -- swaync se installato (ha il pannello con lo storico), altrimenti mako.
    -- I due sono entrambi demoni di org.freedesktop.Notifications e si escludono:
    -- lo script sceglie, cosi' non si resta mai senza notifiche.
    hl.exec_cmd(scripts .. "/notifiche.sh")

    -- Storico appunti (SUPER+V). Due watcher: testo e immagini.
    hl.exec_cmd("wl-paste --type text  --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Automount delle chiavette USB. Senza --tray: gira headless e monta,
    -- senza piantare un'icona in una tray che non esiste piu'.
    hl.exec_cmd("udiskie")

    -- NOTA: qui NON ci sono piu' nm-applet e blueman-applet. Piantavano nella
    -- tray le stesse icone di rete e bluetooth che stanno gia' in waybar, e si
    -- vedevano doppie. nm-applet serviva come "secret agent" di NetworkManager
    -- (la finestrella della password wi-fi): quel compito ora lo fa
    -- scripts/wifi.sh, che chiede la password in fuzzel e la passa a nmcli.

    -- Gestione idle/sospensione, tarata su AC vs batteria (vedi lo script)
    hl.exec_cmd(scripts .. "/power-watch.sh")
end)


--------------------------------------------------------------------------------
--  ASPETTO
--------------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,

        -- I colori dei bordi NON stanno qui: arrivano da colori.lua, rigenerato
        -- dallo sfondo da matugen. Il `require` sta in fondo al file, dopo questo
        -- blocco: vince l'ultima assegnazione, quindi va incluso DOPO o i valori
        -- generati verrebbero sovrascritti da questi.

        layout = "dwindle",

        -- Trascinare il bordo per ridimensionare, anche col mouse.
        resize_on_border = true,

        -- Serve ai giochi in fullscreen per il tearing controllato (vedi window rule).
        allow_tearing = false,
    },

    decoration = {
        rounding = 8,

        -- Finestre completamente opache: e' la scelta piu' leggibile e la piu'
        -- economica in GPU. La trasparenza la teniamo solo su barra e launcher.
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 2,
            color        = "rgba(00000055)",
        },

        -- Il blur costa solo dove c'e' davvero trasparenza. Con le finestre opache
        -- qui sopra, in pratica lavora unicamente su waybar e fuzzel: effetto
        -- "vetro" moderno a costo quasi nullo per la batteria.
        blur = {
            enabled           = true,
            size              = 6,
            passes            = 2,
            new_optimizations = true,
            xray              = true,
            ignore_opacity    = true,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Curve rapide: l'obiettivo e' che il desktop sembri istantaneo, non che faccia
-- le acrobazie. Nessuna animazione supera i 200 ms.
hl.curve("rapido",   { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0} } })
hl.curve("elastico", { type = "bezier", points = { {0.2,  1.0}, {0.2, 1.0} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 3, bezier = "rapido",   style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "rapido",   style = "popin 85%" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "elastico" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "rapido" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "elastico", style = "slidefade 15%" })
hl.animation({ leaf = "layers",     enabled = true, speed = 3, bezier = "rapido",   style = "fade" })


--------------------------------------------------------------------------------
--  COMPORTAMENTO / RISPARMIO ENERGETICO
--------------------------------------------------------------------------------
hl.config({
    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,

        -- NOTA sul VFR (il compositore smette di ridisegnare quando sullo schermo
        -- non cambia nulla — il singolo risparmio piu' grosso su portatile):
        -- non si configura qui. L'opzione si chiama debug.vfr ed e' GIA' attiva
        -- per default; va toccata solo per fare debug. Quindi: niente da scrivere,
        -- il risparmio c'e' comunque.  Verifica con:  hyprctl getoption debug:vfr

        -- VRR: il pannello adatta il refresh al contenuto invece di stare fisso a
        -- 180 Hz. 1 = sempre attivo. Se dovessi notare sfarfallii, metti 2
        -- (solo a schermo intero) oppure 0.
        vrr = 1,

        -- Non spostare il focus quando una finestra chiede attenzione da sola.
        focus_on_activate = false,

        -- Niente sfondo di default se hyprpaper non parte.
        force_default_wallpaper = 0,
    },

    ecosystem = {
        -- Non controllare le news di Hyprland ad ogni avvio.
        no_update_news  = true,
        no_donation_nag = true,
    },

    dwindle = {
        -- Il riquadro conserva il suo orientamento anche quando le finestre attorno
        -- cambiano: il layout non si riorganizza sotto le mani mentre si lavora.
        preserve_split = true,
        smart_split    = false,

        -- Il pseudotiling non ha un interruttore globale: si applica per singola
        -- finestra col dispatcher pseudo (qui legato a SUPER+P).
    },
})


--------------------------------------------------------------------------------
--  INPUT
--------------------------------------------------------------------------------
hl.config({
    input = {
        kb_layout = "it",

        follow_mouse = 1,
        -- Il focus segue il mouse ma senza portare la finestra in primo piano da
        -- sola: evita cambi di focus accidentali mentre si scrive.
        mouse_refocus = false,

        sensitivity = 0,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            tap_to_click         = true,
            clickfinger_behavior = true,
            scroll_factor        = 0.4,
        },
    },

    binds = {
        -- SUPER+TAB alterna fra il workspace corrente e il precedente invece di
        -- scorrerli tutti in fila: e' quasi sempre cio' che si vuole davvero.
        allow_workspace_cycles = true,
    },
})

-- Swipe a tre dita per cambiare workspace.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })


--------------------------------------------------------------------------------
--  WORKSPACE
--  Cinque, fissi, sempre presenti. `persistent` li tiene in vita anche da vuoti:
--  la barra mostra sempre 1-5 e le posizioni non ballano, quindi SUPER+3 porta
--  sempre nello stesso posto.
--
--  Dichiararli QUI e non a runtime non e' un dettaglio: `hyprctl reload` azzera
--  i keyword impostati a runtime, mentre cio' che sta nel file viene riapplicato
--  ad ogni ricarica. Con i workspace creati da uno script esterno, ogni cambio
--  sfondo (che fa un reload) li faceva sparire.
--------------------------------------------------------------------------------
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end


--------------------------------------------------------------------------------
--  SCORCIATOIE
--------------------------------------------------------------------------------
local mod  = "SUPER"
local term = "alacritty"
local file = "cosmic-files"
local menu = "fuzzel"

-- --- Essenziali ---
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(term))
hl.bind(mod .. " + Q",      hl.dsp.window.close())
hl.bind(mod .. " + E",      hl.dsp.exec_cmd(file))
hl.bind(mod .. " + R",      hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + D",      hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
-- Menu spegnimento/sospensione/logout (lo stesso del pulsante in waybar)
hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd(scripts .. "/menu-power.sh"))

-- --- Notifiche (centro notifiche swaync) ---
-- SUPER+N apre/chiude il pannello: storico, Non disturbare, controlli musica.
-- E' lo stesso pannello della campanella in waybar.
hl.bind(mod .. " + N",         hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -C -sw"))
hl.bind(mod .. " + CTRL + N",  hl.dsp.exec_cmd("swaync-client -d -sw"))

-- Storico appunti: SUPER+V apre la cronologia in fuzzel e reincolla.
hl.bind(mod .. " + V", hl.dsp.exec_cmd(
    "cliphist list | fuzzel --dmenu --prompt='appunti> ' | cliphist decode | wl-copy"))

-- --- Sfondo ---
-- SUPER+W: selettore delle immagini in ~/Git/wallpapers. Applica subito e
-- riscrive hyprpaper.conf, quindi la scelta resta anche al riavvio.
hl.bind(mod .. " + W", hl.dsp.exec_cmd(scripts .. "/sfondo.sh"))

-- --- Stato finestra ---
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
-- Valvola di sfogo dal tiling: rende flottante la finestra sotto focus.
hl.bind(mod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
-- Ruota l'asse di divisione del riquadro corrente (orizzontale <-> verticale).
-- Non e' un dispatcher ma un messaggio al layout dwindle.
hl.bind(mod .. " + T", hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + C", hl.dsp.window.center())

-- --- Focus (vim-style e frecce) ---
local direzioni = {
    { "H", "left" }, { "L", "right" }, { "K", "up" }, { "J", "down" },
    { "left", "left" }, { "right", "right" }, { "up", "up" }, { "down", "down" },
}
for _, d in ipairs(direzioni) do
    local tasto, dir = d[1], d[2]
    hl.bind(mod .. " + " .. tasto,           hl.dsp.focus({ direction = dir }))
    -- --- Spostare la finestra ---
    hl.bind(mod .. " + SHIFT + " .. tasto,   hl.dsp.window.move({ direction = dir }))
end

-- --- Ridimensionare (bind ripetibile: si tiene premuto) ---
local passi = {
    { "H", -40, 0 }, { "L", 40, 0 }, { "K", 0, -40 }, { "J", 0, 40 },
    { "left", -40, 0 }, { "right", 40, 0 }, { "up", 0, -40 }, { "down", 0, 40 },
}
for _, p in ipairs(passi) do
    hl.bind(mod .. " + CTRL + " .. p[1],
        hl.dsp.window.resize({ x = p[2], y = p[3], relative = true }),
        { repeating = true })
end

-- --- Workspace ---
-- SUPER+1..9 -> workspace 1..9, SUPER+0 -> workspace 10.
-- Con SHIFT la finestra ci va senza portarci il focus (follow = false, cioe'
-- quello che prima era movetoworkspacesilent).
for i = 1, 10 do
    local tasto = i % 10
    hl.bind(mod .. " + " .. tasto,           hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. tasto,   hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Ultimo workspace usato / scorrimento con la rotella
hl.bind(mod .. " + Tab",        hl.dsp.focus({ workspace = "previous" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- --- Scratchpad: terminale a scomparsa, il pane per lo sviluppo ---
-- SUPER+S lo apre/chiude sopra qualsiasi workspace.
hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- --- Mouse ---
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())

-- --- Screenshot (hyprshot) ---
-- Stamp = area selezionata, SHIFT+Stamp = schermo intero, CTRL+Stamp = finestra.
hl.bind("Print",         hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m output -o " .. home .. "/Pictures"))
hl.bind("CTRL + Print",  hl.dsp.exec_cmd("hyprshot -m window -o " .. home .. "/Pictures"))
-- Contagocce: copia il colore sotto il puntatore in esadecimale.
hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprpicker -a"))

-- --- Tasti multimediali ---
-- locked = funziona anche a schermo bloccato; repeating = si puo' tenere premuto.
local premibile = { locked = true, repeating = true }
local bloccato  = { locked = true }

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), premibile)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        premibile)
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       bloccato)
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     bloccato)
hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"),                             bloccato)
hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),                                   bloccato)
hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),                               bloccato)

-- --- Luminosita' schermo ---
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), premibile)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), premibile)

-- --- Chiusura del coperchio: blocca e spegne il pannello ---
hl.bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("hyprlock & hyprctl dispatch dpms off"), bloccato)
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms on"),             bloccato)


--------------------------------------------------------------------------------
--  REGOLE FINESTRE
--  Volutamente poche: il layout e' tiling puro. Qui stanno solo le cose che
--  come riquadro affiancato non hanno alcun senso (dialoghi e pannelli).
--
--  SINTASSI Lua: i criteri di ricerca stanno nella tabella `match`, le proprieta'
--  da applicare sono campi normali della stessa tabella. Il campo `name` e'
--  facoltativo ma utile: da' alla regola un'identita' stabile, cosi' un reload
--  la aggiorna invece di accumularne un'altra copia.
--------------------------------------------------------------------------------
local flottanti = {
    { "pavucontrol",                "^(pavucontrol)$" },
    { "blueman",                    "^(blueman-manager)$" },
    { "nm-connection-editor",       "^(nm-connection-editor)$" },
    { "nwg-look",                   "^(nwg-look)$" },
    { "pavucontrol-qt",             "^(org.pulseaudio.pavucontrol)$" },
    { "portal-gtk",                 "^(xdg-desktop-portal-gtk)$" },
}
for _, f in ipairs(flottanti) do
    hl.window_rule({ name = "float-" .. f[1], match = { class = f[2] }, float = true })
end

-- Finestre di scelta file, in italiano e in inglese
hl.window_rule({
    name  = "float-dialoghi-file",
    match = { title = "^(Apri|Salva|Seleziona|Open|Save|Choose).*" },
    float = true,
})

hl.window_rule({
    name  = "float-steam-pannelli",
    match = { class = "^(steam)$", title = "^(Friends List|Steam Settings)$" },
    float = true,
})

-- I dialoghi modali restano finestre a se'
hl.window_rule({
    name  = "float-modali",
    match = { title = "^(Conferma|Confirm|Warning|Errore|Error)$" },
    float = true,
})

-- Picture-in-picture del browser: flottante, sempre in cima, angolo in basso a dx
hl.window_rule({
    name  = "pip",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
    size  = "480 270",
    move  = "100%-500 100%-290",
})

-- Impedisci lo spegnimento schermo mentre un video e' a tutto schermo
hl.window_rule({
    name         = "idle-inhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})

-- Il terminale dello scratchpad parte gia' dimensionato
hl.window_rule({
    name  = "scratchpad-dimensione",
    match = { class = "^(Alacritty)$", workspace = "special:magic" },
    size  = "70% 60%",
})


--------------------------------------------------------------------------------
--  REGOLE LAYER
--  Barra, launcher e notifiche prendono il blur: e' li' che si vede l'effetto
--  vetro. I namespace sono quelli reali dei tre programmi (verificati con
--  `hyprctl layers`): waybar, launcher = fuzzel, e i DUE di swaync (il pannello
--  e le notifiche a comparsa sono superfici distinte).
--
--  "ignorezero" non esiste piu': era la scorciatoia per "non sfocare i pixel
--  completamente trasparenti", che ora si scrive ignore_alpha con una soglia.
--  0 = stesso comportamento di prima. Se il bordo della barra dovesse sbavare,
--  alza a 0.1.
--------------------------------------------------------------------------------
for _, ns in ipairs({ "waybar", "launcher", "swaync-control-center", "swaync-notification-window" }) do
    hl.layer_rule({
        name         = "blur-" .. ns,
        match        = { namespace = ns },
        blur         = true,
        ignore_alpha = 0,
    })
end


--------------------------------------------------------------------------------
--  COLORI
--  Rigenerato da matugen ad ogni cambio sfondo (SUPER+W). Va incluso PER ULTIMO:
--  vince l'ultima assegnazione, quindi da qui sovrascrive i bordi e l'ombra
--  impostati piu' sopra.
--  Il file e' tracciato da Hyprland: quando matugen lo riscrive, il reload lo
--  rilegge da solo.
--------------------------------------------------------------------------------
require("colori")
