-- slips theme (shared with abyhub): drawing helpers. Flat navy panels, rounded corners, a
-- periwinkle accent and thin borders (the VanaCore look).
-- Used by slips.lua.
local imgui = require('imgui')

-- Base palette (VanaCore).
local C = {
    bg       = { 0.086, 0.098, 0.145, 1.00 },
    side     = { 0.067, 0.078, 0.118, 1.00 },
    card     = { 0.125, 0.145, 0.222, 1.00 },
    frame    = { 0.176, 0.196, 0.271, 1.00 },
    frame_hi = { 0.220, 0.243, 0.333, 1.00 },
    border   = { 0.560, 0.620, 1.000, 0.12 },
    line     = { 0.700, 0.750, 1.000, 0.08 },
    accent   = { 0.490, 0.557, 1.000, 1.00 },
    text     = { 0.910, 0.922, 0.957, 1.00 },
    muted    = { 0.545, 0.576, 0.667, 1.00 },
}

-- Names the rest of the addon uses.
local HUD = {
    accent      = C.accent,                      -- periwinkle: links, headings, selection
    accent2     = { 0.66, 0.71, 1.00, 1.00 },
    lavender    = { 0.78, 0.81, 1.00, 1.00 },
    text        = C.text,
    subtext     = { 0.72, 0.75, 0.84, 1.00 },
    muted       = C.muted,
    faint       = { 0.36, 0.39, 0.48, 1.00 },
    owned       = { 0.45, 0.90, 0.60, 1.00 },
    warn        = { 1.00, 0.68, 0.30, 1.00 },
    bad         = { 1.00, 0.45, 0.45, 1.00 },
    gold        = { 0.94, 0.77, 0.42, 1.00 },
    yellow      = { 1.00, 0.86, 0.45, 1.00 },
    red         = { 1.00, 0.45, 0.45, 1.00 },
    blue        = { 0.45, 0.66, 1.00, 1.00 },
    purple      = { 0.72, 0.56, 1.00, 1.00 },
    edge        = { 0.56, 0.62, 1.00, 1.00 },    -- border colour (drawn at low alpha)
    edge_hi     = C.accent,
    glow        = C.accent,
    window_bg   = C.bg,
    header_bg   = C.side,
    card        = C.card,
    inset       = C.side,
    frame       = C.frame,
    sel_fill    = C.frame_hi,
    card_line   = C.border,
    row_line    = C.line,
    track       = { 1.00, 1.00, 1.00, 0.06 },
}

local ui = { h = {} }   -- shared layout state (panel heights, content width)

local CORNERS_ALL = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All or 15

local function rgba(c, a) return { c[1], c[2], c[3], a or c[4] } end
local function col(c, a) return imgui.GetColorU32(rgba(c, a)) end
local function pulse(speed) return (math.sin(os.clock() * (speed or 3.0)) + 1.0) * 0.5 end
local function line_h() return tonumber(imgui.GetTextLineHeight()) or 13 end
local function text_w(s) return tonumber((imgui.CalcTextSize(s))) or 0 end
local function DL() return imgui.GetWindowDrawList() end

local function text(x, y, c, s, scale)
    local dl = DL()
    if scale and scale ~= 1 and type(imgui.GetFont) == 'function' and type(imgui.GetFontSize) == 'function' then
        local ok = pcall(function() dl:AddText(imgui.GetFont(), imgui.GetFontSize() * scale, { x, y }, col(c), s) end)
        if ok then return end
    end
    dl:AddText({ x, y }, col(c), s)
end

-- Right-aligned text ending at x.
local function rtext(x, y, c, s) text(x - text_w(s), y, c, s) end

-- Shorten s with a trailing '.' until it fits in w.
local function fit(s, w)
    if text_w(s) <= w then return s end
    while #s > 2 and text_w(s .. '.') > w do s = s:sub(1, -2) end
    return s .. '.'
end

-- Status dot. glow > 0 adds a faint ring (used for "in progress" states).
local function dot(cx, cy, r, c, glow)
    local dl = DL()
    if glow and glow > 0 then
        dl:AddCircleFilled({ cx, cy }, r * 1.9, col(c, 0.12 * glow), 20)
    end
    dl:AddCircleFilled({ cx, cy }, r, col(c), 16)
end

-- Marker (kept as `diamond` for the callers): filled = solid dot, otherwise a ring.
local function diamond(cx, cy, r, c, filled, glow)
    local dl = DL()
    local rr = r * 0.8
    if glow and glow > 0 then
        dl:AddCircleFilled({ cx, cy }, rr * 1.8, col(c, 0.12 * glow), 20)
    end
    if filled then
        dl:AddCircleFilled({ cx, cy }, rr, col(c), 16)
    else
        dl:AddCircle({ cx, cy }, rr - 0.5, col(c, 0.85), 16, 1.3)
    end
end

-- Rounded box helpers (the old chamfer names stay so nothing else has to change).
-- k is the corner radius; c is an already-converted colour.
local function chamfer_fill(x, y, w, h, k, c)
    DL():AddRectFilled({ x, y }, { x + w, y + h }, c, k, CORNERS_ALL)
end

local function chamfer_line(x, y, w, h, k, c, t)
    DL():AddRect({ x, y }, { x + w, y + h }, c, k, CORNERS_ALL, t or 1)
end

-- opts: k (corner radius-ish), fill (colour or false), edge (border colour), alpha (border strength)
local function frame(x, y, w, h, opts)
    opts = opts or {}
    local r = (opts.k or 6) + 1
    if opts.fill ~= false then chamfer_fill(x, y, w, h, r, col(opts.fill or HUD.card)) end
    local e = opts.edge or HUD.edge
    local a = opts.alpha or 0.85
    -- default border is a faint periwinkle hairline; a coloured edge reads a little stronger
    local ba = (e == HUD.edge) and (0.14 * a / 0.85) or (0.45 * a)
    chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, r, col(e, ba), 1)
end

-- Tag (status pill): small rounded tinted box.
local function pill_w(s) return text_w(s) + 18 end

local function pill(x, y, s, c, fill)
    local w, h = pill_w(s), line_h() + 6
    local top = y - 3
    local dl = DL()
    dl:AddRectFilled({ x, top }, { x + w, top + h }, col(c, (fill or 0.10) + 0.04), h * 0.5)
    dl:AddRect({ x + 0.5, top + 0.5 }, { x + w - 0.5, top + h - 0.5 }, col(c, 0.30), h * 0.5, CORNERS_ALL, 1)
    text(x + 9, y, c, s)
    return w
end

local function bar(x, y, w, h, frac, c)
    local dl = DL()
    frac = math.max(0, math.min(1, frac))
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(HUD.track), h * 0.5)
    if frac > 0 then
        dl:AddRectFilled({ x, y }, { x + math.max(h, w * frac), y + h }, col(c, 0.9), h * 0.5)
    end
end

-- Card: flat fill, thin border; an accent tints the border (e.g. green when complete).
local function card_bg(x, y, w, h, accent, strength)
    local s = strength or 1
    chamfer_fill(x, y, w, h, 6, col(HUD.card))
    if accent then
        chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, 6, col(accent, 0.20 + 0.25 * s), 1)
    else
        chamfer_line(x + 0.5, y + 0.5, w - 1, h - 1, 6, col(C.border), 1)
    end
end

-- Card title: title, muted subtitle, optional right text.
local function card_title(x, y, w, c, title, sub, right, right_col)
    text(x, y, c, title)
    if sub then text(x + text_w(title) + 10, y, HUD.muted, sub) end
    if right then text(x + w - text_w(right), y, right_col or HUD.faint, right) end
end

-- Hairline. (c / a kept for callers; it's always a quiet line now.)
local function rule(x, y, w, c, a)
    DL():AddRectFilled({ x, y }, { x + w, y + 1 }, col(C.line, 0.10 + 0.06 * (a or 0.6)))
end

-- Clip drawing to a box. Ashita's renderer goes blank for the rest of the frame
-- if it's handed an empty clip rectangle, which is what ImGui produces when the
-- box is scrolled completely out of view. So only clip when the box is actually
-- inside the window; off-screen boxes are hidden by the window's own clipping.
-- Returns true if a clip rect was pushed (pass it to pop_clip).
local CLIP_MARGIN = 8
local function push_clip(x1, y1, x2, y2)
    local wx, wy = imgui.GetWindowPos()
    local ww, wh = imgui.GetWindowSize()
    wx, wy, ww, wh = tonumber(wx), tonumber(wy), tonumber(ww), tonumber(wh)
    if not (wx and wy and ww and wh) then return false end
    local ix1, iy1 = math.max(x1, wx + CLIP_MARGIN), math.max(y1, wy + CLIP_MARGIN)
    local ix2, iy2 = math.min(x2, wx + ww - CLIP_MARGIN), math.min(y2, wy + wh - CLIP_MARGIN)
    if ix2 - ix1 < 1 or iy2 - iy1 < 1 then return false end
    DL():PushClipRect({ x1, y1 }, { x2, y2 }, true)
    return true
end

local function pop_clip(pushed)
    if pushed then DL():PopClipRect() end
end

local function hit(id, x, y, w, h)
    local cx, cy = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, y })
    local clicked = imgui.InvisibleButton(id, { w, h })
    local hov = imgui.IsItemHovered()
    if hov then imgui.SetMouseCursor(ImGuiMouseCursor_Hand) end
    imgui.SetCursorScreenPos({ cx, cy })
    return clicked, hov
end

local function advance(w, h) imgui.Dummy({ w, h }) end

ui.cw = ui.cw or 760
ui.left_x = ui.left_x or 0
ui.inset = 4   -- keeps panel edges off the window's clip line
local function avail_w()
    local cx = imgui.GetCursorScreenPos()
    return ui.cw - (cx - ui.left_x) - ui.inset
end

-- Start a window's content: reserve the full width, then step in by ui.inset.
local function begin_content(cw)
    local x, y = imgui.GetCursorScreenPos()
    ui.left_x, ui.cw = x, cw
    imgui.Dummy({ cw, 0 })
    imgui.SetCursorScreenPos({ x + ui.inset, y + ui.inset })
end

local function end_content()
    imgui.Dummy({ 0, ui.inset })
end

-- Segmented control. items = { { key, label, badge, badge_col, light }, ... }
-- A dark rounded track; the selected segment is lifted (lighter fill, white text),
-- the rest are muted. opts.width stretches it to that width.
local SEG_PAD = 3   -- track padding around the segments
local function seg_item_w(t, pad) return text_w(t[2]) + (t[3] and (text_w(t[3]) + 8) or 0) + (t[5] and 14 or 0) + pad * 2 end

local function seg_tabs(id, items, active, x, y, color, small, opts)
    opts = opts or {}
    local dl = DL()
    local lh = line_h()
    local ih = lh + (small and 6 or 8)          -- segment height
    local th = ih + SEG_PAD * 2                  -- track height
    local pad = small and 10 or 13
    local natural = 0
    for _, t in ipairs(items) do natural = natural + seg_item_w(t, pad) end
    local extra = 0
    if opts.width then
        extra = math.max(0, (opts.width - SEG_PAD * 2 - natural) / #items)
    end
    local total = natural + extra * #items + SEG_PAD * 2
    dl:AddRectFilled({ x, y }, { x + total, y + th }, col(C.side), 8)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + total - 0.5, y + th - 0.5 }, col(C.border), 8, CORNERS_ALL, 1)

    local tx = x + SEG_PAD
    local sy = y + SEG_PAD
    local clicked_key = nil
    for i, t in ipairs(items) do
        local key, label, badge = t[1], t[2], t[3]
        local on = active == key
        local tw = seg_item_w(t, pad) + extra
        local clicked, hov = hit(('##%s_%s'):format(id, tostring(key)), tx, sy, tw, ih)
        if clicked then clicked_key = key end
        if on then
            dl:AddRectFilled({ tx, sy }, { tx + tw, sy + ih }, col(C.frame_hi), 6)
            dl:AddRect({ tx + 0.5, sy + 0.5 }, { tx + tw - 0.5, sy + ih - 0.5 }, col(C.border, 0.18), 6, CORNERS_ALL, 1)
        elseif hov then
            dl:AddRectFilled({ tx, sy }, { tx + tw, sy + ih }, col(C.frame, 0.55), 6)
        end
        local light = t[5]
        local cw = text_w(label) + (badge and (text_w(badge) + 8) or 0) + (light and 14 or 0)
        local lx = tx + (tw - cw) * 0.5
        local ty = sy + (ih - lh) * 0.5
        if light then
            dot(lx + 4, ty + lh * 0.5, 3.5, light, 0.4 + pulse(2) * 0.6)
            lx = lx + 14
        end
        text(lx, ty, on and { 1, 1, 1, 1 } or (hov and HUD.text or HUD.muted), label)
        if badge then
            text(lx + text_w(label) + 8, ty, t[4] or (on and HUD.accent2 or HUD.faint), badge)
        end
        tx = tx + tw
    end
    return clicked_key, total, th
end

local function seg_width(items, small)
    local pad = small and 10 or 13
    local w = 0
    for _, t in ipairs(items) do w = w + seg_item_w(t, pad) end
    return w + SEG_PAD * 2
end

-- Pill switch with a label to its right. Returns clicked, width.
local function toggle_w(label) return 34 + 8 + text_w(label) + 6 end

local function toggle_chip(id, label, on, x, y, c)
    local dl = DL()
    local lh = line_h()
    local h = lh + 10
    local sw, sh = 34, 18
    local w = toggle_w(label)
    local clicked, hov = hit(id, x, y, w, h)
    local sx, sy = x, y + (h - sh) * 0.5
    dl:AddRectFilled({ sx, sy }, { sx + sw, sy + sh }, on and col(c or C.accent) or col(C.frame, hov and 1 or 0.9), sh * 0.5)
    if not on then
        dl:AddRect({ sx + 0.5, sy + 0.5 }, { sx + sw - 0.5, sy + sh - 0.5 }, col(C.border), sh * 0.5, CORNERS_ALL, 1)
    end
    local kr = sh * 0.5 - 3
    local kx = on and (sx + sw - sh * 0.5) or (sx + sh * 0.5)
    dl:AddCircleFilled({ kx, sy + sh * 0.5 }, kr, on and col({ 1, 1, 1, 1 }) or col(HUD.muted), 16)
    text(sx + sw + 8, y + (h - lh) * 0.5, on and HUD.text or (hov and HUD.subtext or HUD.muted), label)
    return clicked, w
end

-- Panel wrapper: card sized from last frame's measurement.
local function panel(id, accent, draw_fn, strength)
    local x, y = imgui.GetCursorScreenPos()
    local w = avail_w()
    local h = ui.h[id] or 120
    card_bg(x, y, w, h, accent, strength or 0.9)
    local content_h = draw_fn(x + 14, y + 11, w - 28)
    ui.h[id] = content_h + 22
    advance(w, h)
    imgui.Dummy({ 0, 2 })
end

-- Row of controls on the window background; draw_fn(x, y, w) returns its height.
-- opts.line draws a hairline under it (the header uses this).
local function band(id, draw_fn, opts)
    local x, y = imgui.GetCursorScreenPos()
    local w = avail_w()
    local h = ui.h[id] or 40
    local ch = draw_fn(x + 2, y + 4, w - 4)
    ui.h[id] = ch + 8
    if opts and opts.line then
        DL():AddRectFilled({ x - ui.inset, y + h + 2 }, { x + w + ui.inset, y + h + 3 }, col(C.line))
        advance(w, h + 6)
    else
        advance(w, h)
    end
    imgui.Dummy({ 0, 2 })
end

-- Two-tone title: first word in the text colour, the rest in the accent (VanaCore style).
local TITLE_SCALE = 1.5
local function title_w(s)
    return text_w(s) * TITLE_SCALE
end

local function title_text(x, y, h, s, c)
    local lh = line_h()
    local ty = y + (h - lh * TITLE_SCALE) * 0.5
    local first, rest = s:match('^(%S+)%s+(.*)$')
    if not first then text(x, ty, c or HUD.text, s, TITLE_SCALE); return end
    text(x, ty, c or HUD.text, first, TITLE_SCALE)
    text(x + text_w(first .. ' ') * TITLE_SCALE, ty, HUD.accent, rest, TITLE_SCALE)
end

-- No logo in this style (kept so callers don't break).
local function logo() end

-- Ghost "X" close button. Returns true when clicked.
local function close_button(x, y, s)
    local dl = DL()
    local clicked, hov = hit('##slip_close', x, y, s, s)
    if hov then dl:AddRectFilled({ x, y }, { x + s, y + s }, col({ 1, 1, 1, 0.06 }), 5) end
    local m, c = s * 0.32, hov and HUD.text or HUD.muted
    dl:AddLine({ x + m, y + m }, { x + s - m, y + s - m }, col(c), 1.4)
    dl:AddLine({ x + s - m, y + m }, { x + m, y + s - m }, col(c), 1.4)
    return clicked
end

-- ImGui draws the window itself now (rounded, thin border).
local function draw_window_frame() end

-- Rounded pill with a small dot (job / clock). Returns clicked, hovered, width.
local function dot_pill(id, x, y, label, c, label2, c2, glowing)
    local dl = DL()
    local lh = line_h()
    local w = text_w(label) + (label2 and (text_w(label2) + 8) or 0) + 32
    local h = lh + 8
    local clicked, hov = false, false
    if id then clicked, hov = hit(id, x, y, w, h) end
    dl:AddRectFilled({ x, y }, { x + w, y + h }, col(C.frame, hov and 1 or 0.7), h * 0.5)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + w - 0.5, y + h - 0.5 }, col(C.border), h * 0.5, CORNERS_ALL, 1)
    dot(x + 13, y + h * 0.5, 3, c, glowing and (0.3 + pulse(2) * 0.5) or 0)
    text(x + 22, y + (h - lh) * 0.5, label2 and HUD.text or c, label)
    if label2 then text(x + 22 + text_w(label) + 8, y + (h - lh) * 0.5, c2 or c, label2) end
    return clicked, hov, w
end

local function dot_pill_w(label, label2)
    return text_w(label) + (label2 and (text_w(label2) + 8) or 0) + 32
end

-- Segoe UI 17 (the font VanaCore uses). Windows ships it, so nothing is
-- bundled; if it can't be loaded the game's ImGui font is kept.
local font = nil
local function load_font()
    font = nil
    if type(imgui.AddFontFromFileTTF) ~= 'function' then return end
    local dir = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\'
    for _, name in ipairs({ 'segoeui.ttf', 'SegUIVar.ttf' }) do
        local f = io.open(dir .. name, 'rb')
        if f then
            f:close()
            local ok, fnt = pcall(imgui.AddFontFromFileTTF, dir .. name, 17)
            if ok and fnt then font = fnt; return end
        end
    end
end

-- Push the font; newer ImGui (fonts with LegacySize) wants a size. Returns true if pushed.
local function push_font()
    if font == nil then return false end
    local ok
    if font.LegacySize ~= nil then ok = pcall(imgui.PushFont, font, 17) else ok = pcall(imgui.PushFont, font) end
    return ok and true or false
end

local function pop_font(pushed)
    if pushed then imgui.PopFont() end
end

-- Pushed only when the ImGui build has the slot, and counted so pops always match.
local pushed_c, pushed_v = {}, {}
local function pc(idx, c) if idx ~= nil then imgui.PushStyleColor(idx, c); pushed_c[#pushed_c] = pushed_c[#pushed_c] + 1 end end
local function pv(idx, v) if idx ~= nil then imgui.PushStyleVar(idx, v); pushed_v[#pushed_v] = pushed_v[#pushed_v] + 1 end end

local function push_style()
    pushed_c[#pushed_c + 1], pushed_v[#pushed_v + 1] = 0, 0
    pc(ImGuiCol_WindowBg, C.bg)
    pc(ImGuiCol_Border, C.border)
    pc(ImGuiCol_Text, HUD.text)
    pc(ImGuiCol_PopupBg, { 0.075, 0.079, 0.092, 0.99 })
    pc(ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 })
    pc(ImGuiCol_ScrollbarGrab, { 1, 1, 1, 0.08 })
    pc(ImGuiCol_ScrollbarGrabHovered, { 1, 1, 1, 0.16 })
    pc(ImGuiCol_ScrollbarGrabActive, { 1, 1, 1, 0.22 })
    pc(ImGuiCol_ResizeGrip, { 1, 1, 1, 0.06 })
    pc(ImGuiCol_ResizeGripHovered, rgba(C.accent, 0.55))
    pc(ImGuiCol_ResizeGripActive, rgba(C.accent, 0.85))
    pc(ImGuiCol_Button, { 1, 1, 1, 0.035 })
    pc(ImGuiCol_ButtonHovered, rgba(C.accent, 0.25))
    pc(ImGuiCol_ButtonActive, rgba(C.accent, 0.40))
    pc(ImGuiCol_Separator, C.line)
    pv(ImGuiStyleVar_WindowRounding, 8.0)
    pv(ImGuiStyleVar_WindowBorderSize, 1.0)
    pv(ImGuiStyleVar_WindowPadding, { 14, 12 })
    pv(ImGuiStyleVar_ItemSpacing, { 8, 6 })
    pv(ImGuiStyleVar_ScrollbarSize, 6.0)
    pv(ImGuiStyleVar_ScrollbarRounding, 6.0)
    pv(ImGuiStyleVar_ChildRounding, 6.0)
    pv(ImGuiStyleVar_FrameRounding, 5.0)
    pv(ImGuiStyleVar_PopupRounding, 6.0)
end

local function pop_style()
    local nv, nc = table.remove(pushed_v) or 0, table.remove(pushed_c) or 0
    if nv > 0 then imgui.PopStyleVar(nv) end
    if nc > 0 then imgui.PopStyleColor(nc) end
end

return {
    HUD = HUD, C = C, ui = ui, CORNERS_ALL = CORNERS_ALL,
    rgba = rgba, col = col, pulse = pulse, line_h = line_h, text_w = text_w, DL = DL,
    text = text, rtext = rtext, fit = fit, dot = dot, diamond = diamond,
    chamfer_fill = chamfer_fill, chamfer_line = chamfer_line, frame = frame,
    pill_w = pill_w, pill = pill, bar = bar, card_bg = card_bg, card_title = card_title, rule = rule,
    push_clip = push_clip, pop_clip = pop_clip,
    hit = hit, advance = advance, avail_w = avail_w, begin_content = begin_content, end_content = end_content,
    seg_tabs = seg_tabs, seg_width = seg_width, toggle_chip = toggle_chip, toggle_w = toggle_w, panel = panel, band = band,
    title_w = title_w, title_text = title_text, logo = logo, close_button = close_button,
    draw_window_frame = draw_window_frame, dot_pill = dot_pill, dot_pill_w = dot_pill_w,
    load_font = load_font, push_font = push_font, pop_font = pop_font,
    push_style = push_style, pop_style = pop_style,
}
