-- Seme di partenza per config/hypr/colori.lua, copiato da installa.sh al primo
-- avvio. Il file vero e' in .gitignore: matugen lo riscrive ad ogni SUPER+W.
--
-- Questo seme NON e' decorativo: hyprland.lua fa `require("colori")` e, se il
-- file manca, la config non parte proprio. Su una macchina nuova matugen non
-- ha ancora girato, quindi senza questo seme il primo avvio fallisce.
--
-- Hyprland vuole rgba(RRGGBBAA) senza cancelletto.

hl.config({
    general = {
        col = {
            -- Bordo attivo: sfumatura accento -> avviso, 45 gradi.
            active_border   = { colors = { "rgba(80d4d5ee)", "rgba(b3c8e9ee)" }, angle = 45 },
            inactive_border = "rgba(89939255)",
        },
    },

    -- Ombra intonata al fondo dello sfondo invece di un nero piatto: su sfondi
    -- chiari un nero puro sembra sporco.
    decoration = {
        shadow = {
            color = "rgba(0e151480)",
        },
    },
})
