--[[
    slips - what's stored on your Storage Slips, in the abyhub look.
    Ashita v4.

    /slips                      open / close the window
    /slips find <item>          print which slip an item goes on, and whether it's stored
    /slips refresh              rescan your bags
    /slips reset                put the window back in the middle at its default size

    Item pictures come from the game client itself (the same icons bgwiki shows), so every item
    has one and nothing has to be downloaded.
]]

addon.name    = 'slips'
addon.author  = 'Laudout'
addon.version = '2.0.0'
addon.desc    = 'Storage Slip viewer: every slip, every stored item with its icon, and gear ready to store.'

require('common')
local chat     = require('chat')
local imgui    = require('imgui')
local bit      = require('bit')

local T        = require('sliptheme')   -- abyhub's drawing helpers (blue framed theme)
local icons    = require('slipicons')   -- item icons from the game client
local slipdata = require('slipdata')

local HUD, ui, CORNERS_ALL = T.HUD, T.ui, T.CORNERS_ALL
local col, text, rtext, text_w, line_h, DL = T.col, T.text, T.rtext, T.text_w, T.line_h, T.DL
local hit, advance, fit, pill, pill_w = T.hit, T.advance, T.fit, T.pill, T.pill_w
local card_bg, bar, band, diamond = T.card_bg, T.bar, T.band, T.diamond
local seg_tabs, seg_width = T.seg_tabs, T.seg_width

local function msg(s) print(chat.header(addon.name):append(chat.message(s))) end

local function call(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

--------------------------------------------------------------------------------
-- Slip data
--------------------------------------------------------------------------------

local CONTAINERS = {
    { 0, 'Inventory' }, { 1, 'Mog Safe' }, { 2, 'Storage' }, { 4, 'Mog Locker' }, { 5, 'Satchel' },
    { 6, 'Sack' }, { 7, 'Case' }, { 8, 'Wardrobe' }, { 9, 'Mog Safe 2' }, { 10, 'Wardrobe 2' },
    { 11, 'Wardrobe 3' }, { 12, 'Wardrobe 4' }, { 13, 'Wardrobe 5' }, { 14, 'Wardrobe 6' },
    { 15, 'Wardrobe 7' }, { 16, 'Wardrobe 8' },
}

local slips, slip_by_id, item_to_slip = {}, {}, {}
for _, s in pairs(slipdata) do
    if type(s) == 'table' and s.item_id and s.items then
        local slip = { num = s.id, name = s.en, item_id = s.item_id, items = s.items }
        slips[#slips + 1] = slip
        slip_by_id[s.item_id] = slip
        for pos, iid in ipairs(s.items) do item_to_slip[iid] = { slip = slip, pos = pos } end
    end
end
table.sort(slips, function(a, b) return a.num < b.num end)

local name_cache = {}
local function item_name(id)
    local n = name_cache[id]
    if n then return n end
    n = icons.name(id)
    if type(n) ~= 'string' or n == '' then n = ('Item #%d'):format(id) end
    name_cache[id] = n
    return n
end

-- Short label for a slip: "Slip 07".
local function short(slip) return (slip.name:gsub('^Storage ', '')) end

--------------------------------------------------------------------------------
-- State + settings
--------------------------------------------------------------------------------

local state = {
    visible    = { false },
    search     = { '' },
    tab        = 1,
    show_empty = false,
    owned_only = true,
    open       = {},      -- slip num -> true/false (nil = default: open if you own it)
    owned      = {},      -- slip item id -> { where, stored = {[pos]=true}, count }
    ready      = {},      -- carried items that can go on a slip
    total      = 0,
    owned_n    = 0,
    last_scan  = -10,
    who        = nil,
}

local function settings_file() return ('%s/slips_settings.lua'):format(addon.path) end

local function save_settings()
    pcall(function()
        local f = io.open(settings_file(), 'w')
        if not f then return end
        local open = {}
        for k, v in pairs(state.open) do open[#open + 1] = ('[%d]=%s'):format(k, v and 'true' or 'false') end
        local sz = state.win_size
        f:write(('return { tab = %d, show_empty = %s, owned_only = %s, open = { %s }%s }\n'):format(
            state.tab, tostring(state.show_empty), tostring(state.owned_only), table.concat(open, ', '),
            sz and (', win_w = %d, win_h = %d'):format(sz[1], sz[2]) or ''))
        f:close()
    end)
end

local function load_settings()
    local ok, d = pcall(dofile, settings_file())
    if not ok or type(d) ~= 'table' then return end
    if tonumber(d.tab) and d.tab >= 1 and d.tab <= 2 then state.tab = d.tab end
    if d.show_empty ~= nil then state.show_empty = d.show_empty == true end
    if d.owned_only ~= nil then state.owned_only = d.owned_only == true end
    if type(d.open) == 'table' then
        for k, v in pairs(d.open) do if tonumber(k) then state.open[k] = v == true end end
    end
    if tonumber(d.win_w) and tonumber(d.win_h) then state.win_size = { d.win_w, d.win_h } end
end

--------------------------------------------------------------------------------
-- Reading the slips
--------------------------------------------------------------------------------

local function player_name()
    local ok, n = pcall(function()
        return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return nil
end

-- A slip's extdata is a bit field: bit n set = item n of that slip is stored.
-- Extra can arrive as a string or a byte array depending on the Ashita build.
local function extra_bytes(extra)
    local bytes = {}
    if extra == nil then return bytes end
    if type(extra) == 'string' then
        for i = 1, #extra do bytes[i] = extra:byte(i) end
        return bytes
    end
    for i = 1, 28 do
        local ok, v = pcall(function() return extra[i] end)
        if not ok or v == nil then break end
        bytes[i] = tonumber(v) or 0
    end
    return bytes
end

local function decode(slip, extra)
    local bytes, stored, n = extra_bytes(extra), {}, 0
    for pos = 1, #slip.items do
        local b = bytes[math.floor((pos - 1) / 8) + 1] or 0
        if bit.band(bit.rshift(b, (pos - 1) % 8), 1) == 1 then stored[pos] = true; n = n + 1 end
    end
    return stored, n
end

local function scan()
    state.last_scan = os.clock()
    local ok, inv = pcall(function() return AshitaCore:GetMemoryManager():GetInventory() end)
    if not ok or inv == nil then return end
    local owned, ready, total, owned_n = {}, {}, 0, 0
    for _, c in ipairs(CONTAINERS) do
        local max = tonumber(call(function() return inv:GetContainerCountMax(c[1]) end)) or 0
        for i = 0, max do
            local item = call(function() return inv:GetContainerItem(c[1], i) end)
            if item ~= nil and item.Id ~= 0 and item.Id ~= 65535 then
                local slip = slip_by_id[item.Id]
                if slip then
                    if not owned[item.Id] then owned_n = owned_n + 1 end
                    local stored, n = decode(slip, item.Extra)
                    owned[item.Id] = { where = c[2], stored = stored, count = n }
                    total = total + n
                elseif item_to_slip[item.Id] then
                    ready[#ready + 1] = { id = item.Id, where = c[2], slip = item_to_slip[item.Id].slip }
                end
            end
        end
    end
    table.sort(ready, function(a, b)
        if a.slip.num ~= b.slip.num then return a.slip.num < b.slip.num end
        return item_name(a.id) < item_name(b.id)
    end)
    state.owned, state.ready, state.total, state.owned_n = owned, ready, total, owned_n
    state.who = player_name()
end

local function is_open(slip)
    local o = state.open[slip.num]
    if o == nil then return state.owned[slip.item_id] ~= nil end
    return o
end

--------------------------------------------------------------------------------
-- Drawing bits
--------------------------------------------------------------------------------

-- Visible part of the window this frame, so cards scrolled out of view are skipped.
local vis = { top = 0, bottom = 1e9 }

local function item_tooltip(id, status, status_col)
    imgui.BeginTooltip()
    imgui.TextColored(HUD.accent2, item_name(id))
    local info = icons.info(id)
    if info and info.desc then
        imgui.PushTextWrapPos(320)
        imgui.TextColored(HUD.subtext, info.desc)
        imgui.PopTextWrapPos()
    end
    if status then imgui.TextColored(status_col or HUD.muted, status) end
    imgui.EndTooltip()
end

-- One item square. Falls back to a ringed dot if the client has no picture.
local function draw_icon(id, x, y, size, alpha, edge)
    if icons.draw(id, x, y, size, alpha, edge) then return end
    local dl = DL()
    dl:AddRectFilled({ x, y }, { x + size, y + size }, col(HUD.frame, 0.9 * (alpha or 1)), 4)
    diamond(x + size * 0.5, y + size * 0.5, size * 0.18, HUD.accent2, (alpha or 1) > 0.5)
end

local function chevron(cx, cy, open, c)
    local dl, s = DL(), 4
    if open then
        dl:AddLine({ cx - s, cy - 2 }, { cx, cy + 2 }, col(c), 1.6)
        dl:AddLine({ cx, cy + 2 }, { cx + s, cy - 2 }, col(c), 1.6)
    else
        dl:AddLine({ cx - 2, cy - s }, { cx + 2, cy }, col(c), 1.6)
        dl:AddLine({ cx + 2, cy }, { cx - 2, cy + s }, col(c), 1.6)
    end
end

-- Search box (same as abyhub's): magnifier, placeholder, x to clear.
local function search_box(x, y, w)
    local lh = line_h()
    local h = lh + 10
    local cx, cy = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, y })
    imgui.PushStyleColor(ImGuiCol_FrameBg, HUD.inset)
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered, HUD.inset)
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, HUD.inset)
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 28, 5 })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 6)
    imgui.PushItemWidth(w - 24)
    imgui.InputText('##slip_search', state.search, 64)
    local active = imgui.IsItemActive()
    imgui.PopItemWidth()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(3)
    imgui.SetCursorScreenPos({ cx, cy })
    local dl = DL()
    local q = state.search[1] or ''
    dl:AddRectFilled({ x + w - 26, y }, { x + w, y + h }, col(HUD.inset), 6)
    dl:AddRect({ x + 0.5, y + 0.5 }, { x + w - 0.5, y + h - 0.5 }, col(HUD.edge, active and 0.8 or 0.25), 6, CORNERS_ALL, 1)
    if active then T.chamfer_line(x - 1, y - 1, w + 2, h + 2, 7, col(HUD.edge, 0.12), 3) end
    local my = y + h * 0.5
    local mc = (active or q ~= '') and HUD.accent or HUD.muted
    dl:AddCircle({ x + 13, my - 1 }, 4.5, col(mc), 12, 1.4)
    dl:AddLine({ x + 16, my + 2 }, { x + 19.5, my + 5.5 }, col(mc), 1.6)
    if q == '' and not active then text(x + 28, y + 5, HUD.faint, 'Search every slip...') end
    if q ~= '' then
        local bx = x + w - 22
        local clicked, hov = hit('##slip_search_clear', bx, y + 3, 18, h - 6)
        local c = hov and HUD.text or HUD.muted
        dl:AddLine({ bx + 5, my - 4 }, { bx + 13, my + 4 }, col(c), 1.5)
        dl:AddLine({ bx + 13, my - 4 }, { bx + 5, my + 4 }, col(c), 1.5)
        if clicked then state.search[1] = '' end
    end
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

local function render_header()
    local lh = line_h()
    local nready = #state.ready
    local tabs = {
        { 1, 'SLIPS', ('%d/%d'):format(state.owned_n, #slips) },
        { 2, 'READY TO STORE', nready > 0 and tostring(nready) or nil, nready > 0 and HUD.owned or nil,
            nready > 0 and HUD.owned or nil },
    }
    band('slip_hdr', function(x, y, w)
        -- row 1: title, search, close
        local row_h = math.floor(lh * 1.5 + 6)
        T.title_text(x, y, row_h, 'STORAGE SLIPS', HUD.text)
        local tw = T.title_w('STORAGE SLIPS')
        local bs = lh + 6
        local bx = x + w - bs
        if T.close_button(bx, y + (row_h - bs) * 0.5, bs) then state.visible[1] = false end
        local sx = x + tw + 16
        local sw = math.min(420, bx - 14 - sx)
        if sw >= 150 then search_box(sx, y + (row_h - (lh + 10)) * 0.5, sw) end

        -- row 2: who + totals
        local iy = y + row_h + 2
        local who = state.who
        local ix = x
        if who then text(x, iy, HUD.text, who); ix = x + text_w(who) end
        local s = ('%s%d of %d slips  \194\183  %d items stored'):format(who and '  \194\183  ' or '',
            state.owned_n, #slips, state.total)
        text(ix, iy, HUD.muted, s)
        local info_w = ix + text_w(s) - x

        -- row 3: tabs, and the view switches on the right
        local ty = iy + lh + 10
        local tabs_w = seg_width(tabs, false)
        local picked, _, th = seg_tabs('slip_tab', tabs, state.tab, x, ty, HUD.accent, false)
        if picked and picked ~= state.tab then state.tab = picked; save_settings() end
        local need = tabs_w
        if state.tab == 1 then
            local l1, l2 = 'Owned only', 'Empty slots'
            local w1, w2 = T.toggle_w(l1), T.toggle_w(l2)
            local chip_y = ty + (th - (lh + 10)) * 0.5
            local c1 = T.toggle_chip('##slip_owned', l1, state.owned_only, x + w - w1, chip_y)
            local c2 = T.toggle_chip('##slip_empty', l2, state.show_empty, x + w - w1 - 12 - w2, chip_y)
            if c1 then state.owned_only = not state.owned_only; save_settings() end
            if c2 then state.show_empty = not state.show_empty; save_settings() end
            need = tabs_w + 24 + w1 + 12 + w2
        end
        ui.header_need = math.max(tw + 20 + 230 + bs, info_w, need) + 12
        return ty + th - y + 4
    end, { line = true })
end

--------------------------------------------------------------------------------
-- Slips tab: one card per slip, its items as an icon grid
--------------------------------------------------------------------------------

local CELL, ICON = 40, 32

local function slip_card(slip, w)
    local lh = line_h()
    local own = state.owned[slip.item_id]
    local open = is_open(slip)
    local n = #slip.items

    -- which squares to show
    local cells = {}
    if open then
        for pos, iid in ipairs(slip.items) do
            local stored = own ~= nil and own.stored[pos] == true
            if stored or state.show_empty then cells[#cells + 1] = { id = iid, stored = stored } end
        end
    end
    local cols = math.max(1, math.floor((w - 28 + (CELL - ICON)) / CELL))
    local hh = lh + 34
    local body = 0
    if open then
        body = (#cells > 0) and (math.ceil(#cells / cols) * CELL + 8) or (lh + 16)
    end
    local h = hh + body

    local x, y = imgui.GetCursorScreenPos()
    if y > vis.bottom or y + h < vis.top then advance(w, h); imgui.Dummy({ 0, 2 }); return end

    local count = own and own.count or 0
    local full = own ~= nil and count == n
    local accent = full and HUD.owned or (own and count > 0 and HUD.accent) or nil
    card_bg(x, y, w, h, accent, own and 0.6 or 0.3)
    local dl = DL()

    -- header (click to fold)
    local clicked, hov = hit(('##slip_hdr_%d'):format(slip.num), x, y, w, hh)
    if hov then dl:AddRectFilled({ x + 1, y + 1 }, { x + w - 1, y + hh }, col(HUD.sel_fill, 0.45), 6) end
    if clicked then state.open[slip.num] = not open; save_settings() end
    chevron(x + 16, y + 12 + lh * 0.5, open, hov and HUD.text or HUD.muted)
    draw_icon(slip.item_id, x + 28, y + 9, 22, own and 1 or 0.4)
    local tx = x + 60
    text(tx, y + 12, own and HUD.text or HUD.muted, slip.name)
    local sub = own and own.where or 'not owned'
    text(tx + text_w(slip.name) + 10, y + 12, own and HUD.muted or HUD.faint, sub)
    local right = ('%d / %d'):format(count, n)
    if full then
        local pw = pill_w('FULL')
        pill(x + w - 14 - pw, y + 12, 'FULL', HUD.owned, 0.08)
        rtext(x + w - 24 - pw, y + 12, HUD.subtext, right)
    else
        rtext(x + w - 14, y + 12, own and HUD.subtext or HUD.faint, right)
    end
    bar(tx, y + 18 + lh, w - (tx - x) - 14, 4, n > 0 and count / n or 0, full and HUD.owned or HUD.accent)

    -- body
    if open then
        local by = y + hh
        dl:AddRectFilled({ x + 10, by - 2 }, { x + w - 10, by - 1 }, col(HUD.edge, 0.10))
        if #cells == 0 then
            text(x + 16, by + 6, HUD.faint, own and 'Nothing stored on this slip yet.' or
                'You don\'t have this slip. Turn on Empty slots to see what it holds.')
        end
        for i, c in ipairs(cells) do
            local cx = x + 14 + ((i - 1) % cols) * CELL
            local cy = by + 4 + math.floor((i - 1) / cols) * CELL
            local _, ih = hit(('##slip_%d_%d'):format(slip.num, i), cx, cy, ICON, ICON)
            if cy + ICON >= vis.top and cy <= vis.bottom then
                draw_icon(c.id, cx, cy, ICON, c.stored and 1 or 0.22, ih and HUD.accent or (c.stored and HUD.edge or nil))
            end
            if ih then
                item_tooltip(c.id, c.stored and 'Stored on ' .. short(slip) or
                    (own and 'Not stored' or 'Slip not owned'), c.stored and HUD.owned or HUD.muted)
            end
        end
    end
    advance(w, h)
    imgui.Dummy({ 0, 2 })
end

local function render_slips()
    local w = T.avail_w()
    local shown = 0
    for _, slip in ipairs(slips) do
        if state.owned[slip.item_id] or not state.owned_only then
            slip_card(slip, w)
            shown = shown + 1
        end
    end
    if shown == 0 then
        local lh = line_h()
        local x, y = imgui.GetCursorScreenPos()
        card_bg(x, y, w, lh * 2 + 26, nil)
        text(x + 16, y + 11, HUD.text, 'No storage slips found in your bags.')
        text(x + 16, y + 15 + lh, HUD.muted, 'Turn off "Owned only" to browse every slip, or /slips refresh after zoning.')
        advance(w, lh * 2 + 26)
    end
end

--------------------------------------------------------------------------------
-- Row lists (Ready to store + search results)
--------------------------------------------------------------------------------

-- rows = { { id, label, sub, status, status_col }, ... }
local function list_card(key, title, right, rows, accent)
    local lh = line_h()
    local w = T.avail_w()
    local rh = math.max(lh + 12, 30)
    local hh = lh + 14
    local h = hh + #rows * rh + 8
    local x, y = imgui.GetCursorScreenPos()
    if y > vis.bottom or y + h < vis.top then advance(w, h); imgui.Dummy({ 0, 2 }); return end
    card_bg(x, y, w, h, accent, 0.4)
    local dl = DL()
    text(x + 14, y + 9, accent or HUD.accent, title)
    if right then rtext(x + w - 14, y + 9, HUD.faint, right) end
    dl:AddRectFilled({ x + 10, y + hh }, { x + w - 10, y + hh + 1 }, col(HUD.edge, 0.16))
    local ry = y + hh + 2
    for i, r in ipairs(rows) do
        if ry + rh >= vis.top and ry <= vis.bottom then
            local _, hov = hit(('##%s_%d'):format(key, i), x + 6, ry, w - 12, rh)
            if hov then
                dl:AddRectFilled({ x + 6, ry }, { x + w - 6, ry + rh }, col(HUD.sel_fill), 5)
                T.chamfer_line(x + 6.5, ry + 0.5, w - 13, rh - 1, 5, col(HUD.accent, 0.8), 1.2)
            end
            local cy = ry + rh * 0.5
            draw_icon(r.id, x + 14, cy - 11, 22, 1)
            local tx = x + 46
            local rt = x + w - 16
            local sw = 0
            if r.status then
                sw = pill_w(r.status) + 12
                pill(rt - pill_w(r.status), cy - lh * 0.5, r.status, r.status_col or HUD.muted, 0.08)
            end
            local label = fit(r.label, math.min(text_w(r.label), (rt - sw - tx) * 0.6) + 1)
            text(tx, cy - lh * 0.5, hov and HUD.text or HUD.subtext, label)
            if r.sub then
                local sx = tx + text_w(label) + 14
                text(sx, cy - lh * 0.5, HUD.faint, fit(r.sub, rt - sw - sx))
            end
            if hov then item_tooltip(r.id) end
        end
        ry = ry + rh
    end
    advance(w, h)
    imgui.Dummy({ 0, 2 })
end

local function empty_card(line1, line2)
    local lh = line_h()
    local w = T.avail_w()
    local x, y = imgui.GetCursorScreenPos()
    card_bg(x, y, w, lh * 2 + 26, nil)
    text(x + 16, y + 11, HUD.text, line1)
    text(x + 16, y + 15 + lh, HUD.muted, line2)
    advance(w, lh * 2 + 26)
end

local function render_ready()
    if #state.ready == 0 then
        empty_card('Nothing to store right now.',
            'Slip-storable gear in any of your bags shows up here, with the slip it goes on.')
        return
    end
    -- one card per slip, so it reads like a to-do list for the porter moogle
    local groups, order = {}, {}
    for _, r in ipairs(state.ready) do
        local g = groups[r.slip.num]
        if not g then g = { slip = r.slip, rows = {} }; groups[r.slip.num] = g; order[#order + 1] = g end
        g.rows[#g.rows + 1] = { id = r.id, label = item_name(r.id), sub = r.where }
    end
    for _, g in ipairs(order) do
        local own = state.owned[g.slip.item_id]
        local status = own and ('ON ' .. short(g.slip):upper()) or 'SLIP NOT OWNED'
        for _, row in ipairs(g.rows) do row.status, row.status_col = status, own and HUD.owned or HUD.warn end
        list_card('ready_' .. g.slip.num, g.slip.name, own and ('in ' .. own.where) or 'not owned', g.rows,
            own and HUD.owned or HUD.warn)
    end
end

local MAX_RESULTS = 200
local function render_search(q)
    local groups, total = {}, 0
    for _, slip in ipairs(slips) do
        local own = state.owned[slip.item_id]
        local rows = {}
        for pos, iid in ipairs(slip.items) do
            if total < MAX_RESULTS and item_name(iid):lower():find(q, 1, true) then
                local stored = own ~= nil and own.stored[pos] == true
                rows[#rows + 1] = {
                    id = iid, label = item_name(iid),
                    status = stored and 'STORED' or (own and 'NOT STORED' or 'SLIP NOT OWNED'),
                    status_col = stored and HUD.owned or (own and HUD.muted or HUD.warn),
                }
                total = total + 1
            end
        end
        if #rows > 0 then groups[#groups + 1] = { slip = slip, own = own, rows = rows } end
    end
    local lh = line_h()
    local w = T.avail_w()
    local x, y = imgui.GetCursorScreenPos()
    local s = ('%d%s result%s for '):format(total, total >= MAX_RESULTS and '+' or '', total == 1 and '' or 's')
    text(x + 2, y, HUD.muted, s)
    text(x + 2 + text_w(s), y, HUD.text, '"' .. q .. '"')
    advance(w, lh + 4)
    if total == 0 then
        empty_card('Nothing found.', 'No slip-storable item matches that name.')
        return
    end
    for _, g in ipairs(groups) do
        list_card('sr_' .. g.slip.num, g.slip.name, g.own and g.own.where or 'not owned', g.rows,
            g.own and HUD.accent or nil)
    end
end

--------------------------------------------------------------------------------
-- Window (placement, size and dragging work like abyhub's)
--------------------------------------------------------------------------------

local NO_DOCK = ImGuiWindowFlags_NoDocking or 0

local function main_viewport()
    local ok, vp = pcall(imgui.GetMainViewport)
    if ok and vp then
        local ok2, r = pcall(function() return { vp.Pos.x, vp.Pos.y, vp.Size.x, vp.Size.y, vp.ID } end)
        if ok2 and r and tonumber(r[3]) and r[3] > 0 then return r end
    end
    local io_ok, io = pcall(imgui.GetIO)
    local w = (io_ok and io and io.DisplaySize and io.DisplaySize.x) or 1920
    local h = (io_ok and io and io.DisplaySize and io.DisplaySize.y) or 1080
    return { 0, 0, w, h, nil }
end

local function place_window(st, w, h)
    local vp = main_viewport()
    if vp[5] ~= nil and type(imgui.SetNextWindowViewport) == 'function' then pcall(imgui.SetNextWindowViewport, vp[5]) end
    if st.pos then
        st.pos[1] = math.max(vp[1], math.min(st.pos[1], vp[1] + vp[3] - w))
        st.pos[2] = math.max(vp[2], math.min(st.pos[2], vp[2] + vp[4] - h))
        imgui.SetNextWindowPos({ st.pos[1], st.pos[2] }, ImGuiCond_Always)
    end
end

local function drag_window(st)
    local wx, wy = call(imgui.GetWindowPos)
    if not st.pos and tonumber(wx) then st.pos = { wx, wy } end
    local mx, my = call(imgui.GetMousePos)
    if not tonumber(mx) or not tonumber(my) then return end
    if st.drag then
        if call(imgui.IsMouseDown, 0) then
            st.pos = { st.drag[3] + (mx - st.drag[1]), st.drag[4] + (my - st.drag[2]) }
        else
            st.drag = nil
        end
    elseif call(imgui.IsMouseClicked, 0) and call(imgui.IsWindowHovered) and not call(imgui.IsAnyItemHovered) then
        st.drag = { mx, my, st.pos and st.pos[1] or wx, st.pos and st.pos[2] or wy }
    end
end

local win = { content_h = nil, reset = false }
local MIN_CW = 520

ashita.events.register('d3d_present', 'slips_present_cb', function()
    if not state.visible[1] then return end
    if os.clock() - state.last_scan > 1.0 then scan() end

    T.push_style()
    local font_pushed = T.push_font()

    local io_ok, io = pcall(imgui.GetIO)
    local sh = (io_ok and io and io.DisplaySize and io.DisplaySize.y) or 1080
    local PAD_X, PAD_Y, SCROLL_W = 14, 12, 12
    local min_cw = math.max(MIN_CW, (ui.header_need or 0)) + ui.inset * 2
    local min_w = min_cw + PAD_X * 2 + SCROLL_W
    local fit_w = math.max(min_cw, 640) + PAD_X * 2 + SCROLL_W
    local fit_h = math.min(math.max(win.content_h or 520, 420) + PAD_Y * 2, math.floor(sh * 0.8))
    local vp = main_viewport()
    if win.reset or not win.size then
        local sz = (not win.reset) and state.win_size or nil
        win.size = sz and { sz[1], sz[2] } or { fit_w, fit_h }
        win.set_size = true
        if win.reset or not win.pos then
            win.pos = { vp[1] + (vp[3] - win.size[1]) * 0.5, vp[2] + (vp[4] - win.size[2]) * 0.4 }
        end
        win.reset, win.drag = false, nil
    end
    local px, py = win.pos[1], win.pos[2]
    local max_w = math.max(min_w, vp[1] + vp[3] - px)
    local max_h = math.max(200, vp[2] + vp[4] - py)
    if type(imgui.SetNextWindowSizeConstraints) == 'function' then
        imgui.SetNextWindowSizeConstraints({ math.min(min_w, max_w), 200 }, { max_w, max_h })
    end
    if win.set_size then
        imgui.SetNextWindowSize({ math.min(win.size[1], max_w), math.min(win.size[2], max_h) }, ImGuiCond_Always)
        win.set_size = false
    end
    place_window(win, win.size[1], win.size[2])
    if win.content_h and type(imgui.SetNextWindowContentSize) == 'function' then
        imgui.SetNextWindowContentSize({ 0, win.content_h })
    end
    if type(imgui.SetNextWindowDockID) == 'function' then pcall(imgui.SetNextWindowDockID, 0, ImGuiCond_Always) end

    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoMove, NO_DOCK)
    if imgui.Begin('Storage Slips##slips', state.visible, flags) then
        pcall(imgui.SetScrollX, 0)
        local _, top = imgui.GetCursorScreenPos()
        local wx, wy = imgui.GetWindowPos()
        local ww, wh = imgui.GetWindowSize()
        vis.top, vis.bottom = (tonumber(wy) or 0), (tonumber(wy) or 0) + (tonumber(wh) or 1e9)
        if tonumber(ww) and tonumber(wh) then
            if not state.win_size or math.abs(state.win_size[1] - ww) > 0.5 or math.abs(state.win_size[2] - wh) > 0.5 then
                state.win_size = { math.floor(ww), math.floor(wh) }
                win.size = { ww, wh }
                win.size_dirty = os.clock()
            end
        end
        if win.size_dirty and os.clock() - win.size_dirty > 1.0 and not call(imgui.IsMouseDown, 0) then
            win.size_dirty = nil
            save_settings()
        end
        local scrolling = (win.content_h or 0) > (tonumber(wh) or 0) - PAD_Y * 2
        local cw = math.max(min_cw, (tonumber(ww) or fit_w) - PAD_X * 2 - (scrolling and SCROLL_W or 0))

        T.begin_content(cw)
        render_header()
        local q = (state.search[1] or ''):lower():match('^%s*(.-)%s*$')
        if q ~= '' then
            render_search(q)
        elseif state.tab == 2 then
            render_ready()
        else
            render_slips()
        end
        T.end_content()

        local _, bottom = imgui.GetCursorScreenPos()
        win.content_h = math.max(60, bottom - top)
        local max_scroll = math.max(0, win.content_h - ((tonumber(wh) or 0) - PAD_Y * 2))
        local sy = tonumber(call(imgui.GetScrollY)) or 0
        if sy > max_scroll + 0.5 then pcall(imgui.SetScrollY, max_scroll) end
        drag_window(win)
    end
    imgui.End()
    T.pop_font(font_pushed)
    T.pop_style()
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function find(q)
    q = (q or ''):lower()
    if q == '' then msg('Usage: /slips find <item name>'); return end
    scan()
    local hits = 0
    for _, slip in ipairs(slips) do
        local own = state.owned[slip.item_id]
        for pos, iid in ipairs(slip.items) do
            if item_name(iid):lower():find(q, 1, true) then
                hits = hits + 1
                if hits <= 20 then
                    local st = (own == nil) and 'slip not owned'
                        or (own.stored[pos] and ('STORED (slip in %s)'):format(own.where) or 'not stored')
                    msg(('%s -> %s: %s'):format(item_name(iid), slip.name, st))
                end
            end
        end
    end
    if hits == 0 then msg(('No slip-storable item matches "%s".'):format(q))
    elseif hits > 20 then msg(('...and %d more. Try a longer name.'):format(hits - 20)) end
end

ashita.events.register('command', 'slips_command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/slips' then return end
    e.blocked = true
    local sub = (args[2] or ''):lower()
    if sub == '' or sub == 'show' or sub == 'toggle' then
        state.visible[1] = not state.visible[1]
        if state.visible[1] then scan() end
    elseif sub == 'find' then
        find(table.concat(args, ' ', 3))
    elseif sub == 'refresh' then
        scan()
        msg(('Rescanned: %d of %d slips, %d items stored.'):format(state.owned_n, #slips, state.total))
    elseif sub == 'reset' then
        state.win_size = nil
        win.size, win.reset = nil, true
        state.visible[1] = true
        save_settings()
    else
        msg('/slips  |  /slips find <item>  |  /slips refresh  |  /slips reset')
    end
end)

ashita.events.register('load', 'slips_load_cb', function()
    T.load_font()
    load_settings()
    print(chat.header(addon.name):append(chat.success(
        ('v%s loaded - storage slip viewer. /slips to open.'):format(addon.version))))
end)
