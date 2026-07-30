-- GENERATO DA MATUGEN — non modificare a mano.
-- Sorgente: ~/.config/matugen/templates/hypr-colori.lua
-- Incluso da hyprland.lua con `require("colori")`, per ultimo.
--
-- Hyprland vuole rgba(RRGGBBAA) senza cancelletto: da qui hex_stripped invece
-- di hex, con l'alpha attaccato in coda.

hl.config({
    general = {
        col = {
            -- Bordo attivo: sfumatura accento -> avviso, 45 gradi.
            active_border   = { colors = { "rgba({{colors.primary.default.hex_stripped}}ee)", "rgba({{colors.tertiary.default.hex_stripped}}ee)" }, angle = 45 },
            inactive_border = "rgba({{colors.outline.default.hex_stripped}}55)",
        },
    },

    -- Ombra intonata al fondo dello sfondo invece di un nero piatto: su sfondi
    -- chiari un nero puro sembra sporco.
    decoration = {
        shadow = {
            color = "rgba({{colors.surface.default.hex_stripped}}80)",
        },
    },
})
