addon.author = 'Fyayu & Sprort'
addon.name = 'PlayerNotes'
addon.version = '3.0.0'
addon.desc = 'Keep rated notes on other players, shown automatically whenever you target them.'

require('common')
local imgui = require('imgui')
local settings = require('settings')

-- Default settings
local defaultConfig = {
    notes = {},         -- quick notes (shown on the targeting overlay)
    details = {},       -- detailed notes (shown only in the config window)
    ratings = {},
    linkshells = {},
    created = {},
    updated = {},
    lastseen = {},
    visible = true,
    hide_without_target = false,
    overlay_alpha = 0.8,
    config_alpha = 0.9,
}
local config = settings.load(defaultConfig)

-- Variables
local target_name, selected_player = "", ""
local advanced_note, advanced_detail, new_player_name, new_linkshell = { "" }, { "" }, { "" }, { "" }
local advanced_rating = 0
local editing = false
local display_note, display_rating, display_linkshell = "", 0, ""
local show_advanced_window = false

-- Overlay quick-edit state
local quick_note = { "" }
local quick_note_target = ""
local show_quick_edit = false

-- Advanced window state
local filter_text = { "" }
local sort_key = "name"          -- name | rating | linkshell | lastseen
local sort_asc = true
local pending_delete = ""
local prev_target = ""

-- Helper Functions
local function save_config()
    settings.save()
end

-- Ashita's imgui.Text/TextColored/TextWrapped are printf-style: a literal '%'
-- in user-entered text would be treated as a format specifier. Escape it.
local function esc(str)
    return (tostring(str):gsub('%%', '%%%%'))
end

-- FFXI names are always first-letter-uppercase, rest-lowercase (that's the form
-- the game returns when you target someone). Normalise manual entry to match, so
-- targeting a player you typed in lowercase still shows their notes.
local function normalize_name(name)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return "" end
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

local function fmt_datetime(ts)
    if not ts then return "-" end
    return os.date('%Y-%m-%d %H:%M', ts)
end

local function time_ago(ts)
    if not ts then return "-" end
    local d = os.time() - ts
    if d < 60 then return "just now" end
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

local rating_colors = {
    [1] = {1.0, 0.0, 0.0, 1.0},
    [2] = {1.0, 0.5, 0.0, 1.0},
    [3] = {1.0, 1.0, 0.0, 1.0},
    [4] = {0.5, 1.0, 0.0, 1.0},
    [5] = {0.0, 1.0, 0.0, 1.0},
}

local function get_rating_color(rating)
    return rating_colors[rating] or {0.6, 0.6, 0.6, 1.0}
end

-- Draw one filled 5-point star centered at (cx, cy) via a triangle fan. Font-
-- independent, so it never depends on glyph coverage in the imgui atlas.
local function draw_star(dl, cx, cy, radius, inner, col)
    local pts = {}
    for i = 0, 9 do
        local ang = -math.pi / 2 + i * (math.pi / 5)
        local r = (i % 2 == 0) and radius or inner
        pts[i + 1] = { cx + math.cos(ang) * r, cy + math.sin(ang) * r }
    end
    local center = { cx, cy }
    for i = 1, 10 do
        dl:AddTriangleFilled(center, pts[i], pts[(i % 10) + 1], col)
    end
end

-- Draw a 5-star rating: `rating` stars in the rating colour, the rest dimmed,
-- each with a dark outline so they stay legible on any background.
local function render_stars(rating, color)
    rating = math.max(0, math.min(5, rating or 0))
    local size = imgui.GetFontSize()
    local radius = size * 0.50
    local inner = radius * 0.45
    local gap = size * 0.22
    local step = radius * 2 + gap

    local dl = imgui.GetWindowDrawList()
    local ox, oy = imgui.GetCursorScreenPos()
    local cy = oy + size * 0.5
    local fill = imgui.GetColorU32(color)
    local empty = imgui.GetColorU32({0.30, 0.30, 0.32, 1.0})
    local outline = imgui.GetColorU32({0.0, 0.0, 0.0, 0.85})

    for s = 0, 4 do
        local cx = ox + radius + s * step
        draw_star(dl, cx, cy, radius * 1.18, inner * 1.18, outline)
        draw_star(dl, cx, cy, radius, inner, (s < rating) and fill or empty)
    end

    -- Reserve layout width (5 stars) and the line height on the cursor.
    imgui.Dummy({5 * step - gap, size})
end

-- Stamp created/updated times for a tracked player.
local function touch_updated(name)
    local now = os.time()
    config.created[name] = config.created[name] or now
    config.updated[name] = now
end

local function add_or_update_note_for_player(name, note, linkshell)
    if name == "" then return end
    config.notes[name] = note or ""
    config.linkshells[name] = linkshell or ""
    touch_updated(name)
    save_config()
end

local function update_rating_for_player(name, rating)
    if name == "" then return end
    config.ratings[name] = rating
    touch_updated(name)
    save_config()
end

-- Full save from the config editor (quick note, detailed note, linkshell, rating).
local function save_player(name, quick, detail, linkshell, rating)
    if name == "" then return end
    config.notes[name] = quick or ""
    config.details[name] = detail or ""
    config.linkshells[name] = linkshell or ""
    config.ratings[name] = rating or 0
    touch_updated(name)
    save_config()
end

local function delete_player_notes(name)
    if name == "" then return end
    config.notes[name], config.details[name], config.ratings[name], config.linkshells[name] = nil, nil, nil, nil
    config.created[name], config.updated[name], config.lastseen[name] = nil, nil, nil
    save_config()
end

local function get_player_data(name)
    return config.notes[name] or "", config.ratings[name] or 0, config.linkshells[name] or "No linkshell info"
end

-- Neutral gray button styling to match Ashita's default chrome. Pushed right
-- after Begin() and popped right before End() so it covers a whole window.
local function push_button_theme()
    imgui.PushStyleColor(ImGuiCol_Button, {0.26, 0.26, 0.28, 1.0})
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.36, 0.36, 0.38, 1.0})
    imgui.PushStyleColor(ImGuiCol_ButtonActive, {0.46, 0.46, 0.48, 1.0})
end

local function pop_button_theme()
    imgui.PopStyleColor(3)
end

-- One-time migration: older versions stored a note as a single-element table
-- ({ [1] = "text" }). Flatten those to plain strings.
local function migrate_config()
    local changed = false
    for name, note in pairs(config.notes) do
        if type(note) == 'table' then
            config.notes[name] = note[1] or ""
            changed = true
        end
    end
    if changed then save_config() end
end
migrate_config()

-- Command handler
local function print_help()
    print('[PlayerNotes] Commands:')
    print('  /pnotes           - toggle the overlay on/off')
    print('  /pnotes on|off    - force the overlay on or off')
    print('  /pnotes config    - toggle the advanced management window')
    print('  /pnotes help      - show this help')
end

ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/pnotes' and cmd ~= '/playernotes' then return end

    e.blocked = true
    local sub = (#args >= 2) and args[2]:lower() or ""
    if sub == "on" or sub == "off" or sub == "" then
        if sub == "on" then
            config.visible = true
        elseif sub == "off" then
            config.visible = false
        else
            config.visible = not config.visible
        end
        save_config()
        -- Always confirm: a silent toggle looks like the addon broke.
        print('[PlayerNotes] Overlay ' .. (config.visible and 'shown' or 'hidden (/pnotes on to restore)'))
    elseif sub == "config" or sub == "edit" then
        show_advanced_window = not show_advanced_window
    elseif sub == "help" then
        print_help()
    else
        print('[PlayerNotes] Unknown option "' .. sub .. '".')
        print_help()
    end
end)

-- Display Functions
-- How much bigger the targeted player's name is drawn than normal text.
local NAME_SCALE = 1.5

-- Inner content width of the overlay, computed once per frame in present_cb.
-- Centering uses this rather than GetContentRegionAvail(): the overlay is an
-- auto-resizing window, so measuring its available region while positioning
-- content inside it is circular and can collapse the window.
local overlay_content_w = 0

local function apply_font_scale(scale)
    if imgui.SetWindowFontScale then
        imgui.SetWindowFontScale(scale)
    else
        imgui.PushFont(imgui.GetFont(), imgui.GetFontSize() * scale)
    end
end

local function unapply_font_scale()
    if imgui.SetWindowFontScale then
        imgui.SetWindowFontScale(1.0)
    else
        imgui.PopFont()
    end
end

-- Set the cursor so an item of width `item_w` is centered in `content_w`.
local function center_next(content_w, item_w)
    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, (content_w - item_w) * 0.5))
end

local function render_target_info()
    local content_w = overlay_content_w

    -- Player name: larger font, centered (the "Target:" label is implied).
    apply_font_scale(NAME_SCALE)
    center_next(content_w, imgui.CalcTextSize(target_name))
    imgui.TextColored({0.5, 1.0, 0.5, 1.0}, esc(target_name))
    unapply_font_scale()

    -- Star rating: centered on its own line beneath the name.
    center_next(content_w, imgui.GetFontSize() * 5.88)
    render_stars(display_rating, get_rating_color(display_rating))

    -- Linkshell: centered, no label. Hidden entirely when none is recorded.
    if display_linkshell ~= "" and display_linkshell ~= "No linkshell info" then
        center_next(content_w, imgui.CalcTextSize(display_linkshell))
        imgui.Text(esc(display_linkshell))
    end
    imgui.Separator()
end

local function render_notes()
    if display_note ~= "" then
        imgui.TextWrapped(esc(display_note))
    else
        imgui.Text("No notes for this player.")
    end
end

-- Inline editor for the currently targeted player on the main overlay.
local function render_quick_edit()
    imgui.Separator()
    imgui.Text("Rating:")
    for i = 1, 5 do
        imgui.SameLine()
        local active = (display_rating == i)
        if active then imgui.PushStyleColor(ImGuiCol_Button, {0.2, 0.5, 0.2, 1.0}) end
        if imgui.SmallButton(tostring(i) .. "##qr" .. i) then
            update_rating_for_player(target_name, i)
        end
        if active then imgui.PopStyleColor(1) end
    end
    imgui.SameLine()
    if imgui.SmallButton("Clear##qr0") then
        update_rating_for_player(target_name, 0)
    end

    imgui.InputTextMultiline("##quicknote", quick_note, 256, {0, 55})
    if imgui.Button("Save Note##quick") then
        add_or_update_note_for_player(target_name, quick_note[1], config.linkshells[target_name] or "")
        show_quick_edit = false
    end
    imgui.SameLine()
    if imgui.Button("Revert##quick") then
        quick_note[1] = config.notes[target_name] or ""
    end
end

local function render_advanced_window()
    local win_open = { true }
    imgui.SetNextWindowBgAlpha(config.config_alpha)
    imgui.SetNextWindowSize({1080, 640}, ImGuiCond_FirstUseEver)
    imgui.Begin("Advanced Player Notes", win_open, ImGuiWindowFlags_None)
    push_button_theme()

    -- Search + sort controls
    imgui.InputText("Search (name / note / linkshell)", filter_text, 64)
    imgui.Text("Sort by:")
    for _, opt in ipairs({{"Name", "name"}, {"Rating", "rating"}, {"Linkshell", "linkshell"}, {"Last Seen", "lastseen"}}) do
        imgui.SameLine()
        local label = opt[1] .. (sort_key == opt[2] and " *" or "") .. "##sort_" .. opt[2]
        if imgui.Button(label) then sort_key = opt[2] end
    end
    imgui.SameLine()
    local asc = { sort_asc }
    if imgui.Checkbox("Ascending", asc) then sort_asc = asc[1] end
    imgui.Separator()

    -- Size the two panes to the (resizable) window, reserving room for the
    -- settings/new-player controls below.
    local availW, availH = imgui.GetContentRegionAvail()
    local footerH = 170
    local paneH = math.max(200, availH - footerH)
    local leftW = math.max(645, math.floor(availW * 0.62) - 4)
    local rightW = math.max(300, availW - leftW - 8)

    -- Panes follow the window transparency setting via their child background.
    local pane_bg = {0.11, 0.11, 0.12, config.config_alpha}

    imgui.PushStyleColor(ImGuiCol_ChildBg, pane_bg)
    imgui.BeginChild("PlayerList", {leftW, paneH}, true)

    -- Build the (optionally filtered) player list.
    local q = filter_text[1]:lower()
    local player_names = {}
    for player in pairs(config.notes) do
        if q == "" then
            table.insert(player_names, player)
        else
            local note = (config.notes[player] or ""):lower()
            local ls = (config.linkshells[player] or ""):lower()
            if player:lower():find(q, 1, true) or note:find(q, 1, true) or ls:find(q, 1, true) then
                table.insert(player_names, player)
            end
        end
    end

    table.sort(player_names, function(a, b)
        if not sort_asc then a, b = b, a end
        if sort_key == "rating" then
            local ra, rb = config.ratings[a] or 0, config.ratings[b] or 0
            if ra ~= rb then return ra < rb end
        elseif sort_key == "linkshell" then
            local la, lb = (config.linkshells[a] or ""):lower(), (config.linkshells[b] or ""):lower()
            if la ~= lb then return la < lb end
        elseif sort_key == "lastseen" then
            local sa, sb = config.lastseen[a] or 0, config.lastseen[b] or 0
            if sa ~= sb then return sa < sb end
        end
        return a:lower() < b:lower()
    end)

    local open_delete_popup = false

    if imgui.BeginTable("PlayerNotesTable", 5, imgui.ImGuiTableFlags_Resizable) then
        imgui.TableSetupColumn("Player Name", imgui.ImGuiTableColumnFlags_WidthFixed, 150)
        imgui.TableSetupColumn("Rating", imgui.ImGuiTableColumnFlags_WidthFixed, 95)
        imgui.TableSetupColumn("Linkshell", imgui.ImGuiTableColumnFlags_WidthFixed, 140)
        imgui.TableSetupColumn("Last Seen", imgui.ImGuiTableColumnFlags_WidthFixed, 110)
        imgui.TableSetupColumn("Note Updated", imgui.ImGuiTableColumnFlags_WidthFixed, 130)
        imgui.TableHeadersRow()

        for i, player in ipairs(player_names) do
            local rating = config.ratings[player] or 0
            imgui.TableNextRow()

            imgui.TableNextColumn()
            if imgui.Selectable(player .. "##row" .. i, selected_player == player, ImGuiSelectableFlags_SpanAllColumns) then
                selected_player = player
                editing = false
            end
            imgui.TableNextColumn() render_stars(rating, get_rating_color(rating))
            imgui.TableNextColumn() imgui.Text(esc(config.linkshells[player] or ""))
            imgui.TableNextColumn() imgui.Text(time_ago(config.lastseen[player]))
            imgui.TableNextColumn() imgui.Text(fmt_datetime(config.updated[player]))
        end

        imgui.EndTable()
    end

    imgui.EndChild()
    imgui.PopStyleColor(1)

    imgui.SameLine()

    -- === Right pane: quick + detailed notes / editor for the selected player ===
    imgui.PushStyleColor(ImGuiCol_ChildBg, pane_bg)
    imgui.BeginChild("PlayerDetail", {rightW, paneH}, true)
    if selected_player == "" then
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "Select a player from the list")
        imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "to view or edit their notes.")
    elseif editing then
        imgui.Text("Editing: " .. esc(selected_player))
        imgui.Separator()
        imgui.Text("Rating:")
        for i, label in ipairs({"Terrible", "Bad", "Average", "Good", "Great"}) do
            if imgui.RadioButton(label .. "##advRating" .. i, advanced_rating == i) then
                advanced_rating = i
            end
        end
        imgui.Separator()
        imgui.InputText("Linkshell##edit", new_linkshell, 64)
        imgui.Text("Quick note (shown on the targeting overlay):")
        imgui.InputTextMultiline("##QuickNote", advanced_note, 256, {0, 55})
        imgui.Text("Detailed notes (this window only):")
        imgui.InputTextMultiline("##DetailNote", advanced_detail, 1024, {0, 130})
        if imgui.Button("Save") then
            save_player(selected_player, advanced_note[1], advanced_detail[1], new_linkshell[1], advanced_rating)
            editing = false
        end
        imgui.SameLine()
        if imgui.Button("Cancel") then
            if config.notes[selected_player] == nil then selected_player = "" end
            editing = false
        end
    else
        local note, rating, linkshell = get_player_data(selected_player)
        imgui.Text(esc(selected_player))
        imgui.SameLine()
        render_stars(rating, get_rating_color(rating))
        imgui.Text("Linkshell: " .. esc(linkshell))
        if config.created[selected_player] then
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "Note updated: " .. fmt_datetime(config.updated[selected_player]))
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "Last seen: " .. time_ago(config.lastseen[selected_player]))
        end
        imgui.Separator()
        imgui.TextColored({0.5, 1.0, 0.5, 1.0}, "Quick Notes")
        if note ~= "" then
            imgui.TextWrapped(esc(note))
        else
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "None.")
        end
        imgui.Text("")
        imgui.TextColored({0.5, 1.0, 0.5, 1.0}, "Detailed Notes")
        local detail = config.details[selected_player] or ""
        if detail ~= "" then
            imgui.TextWrapped(esc(detail))
        else
            imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "None.")
        end
        imgui.Separator()
        if imgui.Button("Edit") then
            editing = true
            advanced_note[1] = config.notes[selected_player] or ""
            advanced_detail[1] = config.details[selected_player] or ""
            advanced_rating = rating
            new_linkshell[1] = config.linkshells[selected_player] or ""
        end
        imgui.SameLine()
        if imgui.Button("Delete") then
            pending_delete = selected_player
            open_delete_popup = true
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor(1)

    -- Delete confirmation (opened at window scope, not inside the child).
    if open_delete_popup then imgui.OpenPopup("Confirm Delete") end
    if imgui.BeginPopupModal("Confirm Delete", nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text("Delete all notes for '" .. esc(pending_delete) .. "'?")
        imgui.Separator()
        if imgui.Button("Delete", {120, 0}) then
            delete_player_notes(pending_delete)
            if selected_player == pending_delete then selected_player, editing = "", false end
            pending_delete = ""
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Cancel", {120, 0}) then
            pending_delete = ""
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end

    imgui.Separator()

    -- Overlay behaviour toggle
    local hide_without_target = { config.hide_without_target }
    if imgui.Checkbox("Hide overlay when no player is targeted", hide_without_target) then
        config.hide_without_target = hide_without_target[1]
        save_config()
    end
    imgui.SameLine()
    imgui.TextColored({0.6, 0.6, 0.6, 1.0}, "   Tip: hold Shift to click-and-drag the overlay window around.")

    -- Transparency (saved when the slider is released, not every frame).
    local oa = { config.overlay_alpha }
    if imgui.SliderFloat("Overlay transparency", oa, 0.1, 1.0, "%.2f") then
        config.overlay_alpha = oa[1]
    end
    if imgui.IsItemDeactivatedAfterEdit() then save_config() end

    local ca = { config.config_alpha }
    if imgui.SliderFloat("Config window transparency", ca, 0.1, 1.0, "%.2f") then
        config.config_alpha = ca[1]
    end
    if imgui.IsItemDeactivatedAfterEdit() then save_config() end
    imgui.Separator()

    imgui.Text("Enter New Player:")
    imgui.InputText("##NewPlayerName", new_player_name, 64)
    imgui.SameLine()
    if imgui.Button("Create") then
        local name = normalize_name(new_player_name[1])
        if name ~= "" then
            -- Select the player and drop straight into edit mode. Loads any
            -- existing data so we never blank a player who already exists.
            selected_player = name
            editing = true
            advanced_note[1] = config.notes[name] or ""
            advanced_detail[1] = config.details[name] or ""
            advanced_rating = config.ratings[name] or 0
            new_linkshell[1] = config.linkshells[name] or ""
            new_player_name[1] = ""
        end
    end
    imgui.SameLine()
    if imgui.Button("Close") then show_advanced_window = false end

    pop_button_theme()
    imgui.End()

    -- The title-bar [X] writes back into win_open; honour it.
    if not win_open[1] then show_advanced_window = false end
end

ashita.events.register('d3d_present', 'present_cb', function()
    local memMgr = AshitaCore:GetMemoryManager()
    local targetMgr = memMgr:GetTarget()
    local target = ""
    if targetMgr then
        local targetIndex = targetMgr:GetTargetIndex(targetMgr:GetIsSubTargetActive())
        if targetIndex and targetIndex > 0 then
            local entityMgr = memMgr:GetEntity()
            if entityMgr then
                local race = entityMgr:GetRace(targetIndex)
                if race >= 1 and race <= 8 then
                    target = entityMgr:GetName(targetIndex) or ""
                end
            end
        end
    end

    target_name = target
    display_note, display_rating, display_linkshell = get_player_data(target_name)

    -- Keep the quick-edit buffer in sync with the current target.
    if quick_note_target ~= target_name then
        quick_note[1] = display_note
        quick_note_target = target_name
    end

    -- Update "last seen" once per target acquisition (avoids per-frame saves).
    if target_name ~= prev_target then
        if target_name ~= "" and config.notes[target_name] ~= nil then
            config.lastseen[target_name] = os.time()
            save_config()
        end
        prev_target = target_name
    end

    if config.visible and not (config.hide_without_target and target_name == "") then
        imgui.SetNextWindowBgAlpha(config.overlay_alpha)
        -- Pin the overlay to a fixed width that fits the longest possible name
        -- (FFXI names cap at 15 characters), so it doesn't resize as targets
        -- change. Height stays automatic via AlwaysAutoResize + the constraint.
        local longest = string.rep("W", 15)
        -- 'W' is the widest glyph, so 15 of them overshoots any real name; pull
        -- the width in a bit so the overlay isn't wider than it needs to be.
        local name_w = imgui.CalcTextSize(longest) * NAME_SCALE * 0.88
        local ls_w = imgui.CalcTextSize(longest)
        local stars_w = imgui.GetFontSize() * 5.88
        local overlay_w = math.max(name_w, ls_w, stars_w) + 16
        -- Content area excludes the window padding on both sides.
        overlay_content_w = overlay_w - 16
        imgui.SetNextWindowSizeConstraints({overlay_w, 0}, {overlay_w, FLT_MAX})
        -- Title bar is removed, so lock the window in place unless Shift is held,
        -- letting you drag it by its body only when you mean to.
        local overlay_flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_AlwaysAutoResize)
        if not imgui.GetIO().KeyShift then
            overlay_flags = bit.bor(overlay_flags, ImGuiWindowFlags_NoMove)
        end
        imgui.Begin("Player Notes", false, overlay_flags)
        push_button_theme()

        if target_name ~= "" then
            render_target_info()
            render_notes()
            imgui.Separator()
            if imgui.Button(show_quick_edit and "Hide Edit" or "Quick Edit") then
                show_quick_edit = not show_quick_edit
            end
            imgui.SameLine()
            if imgui.Button("Config") then show_advanced_window = not show_advanced_window end
            if show_quick_edit then render_quick_edit() end
        else
            imgui.TextColored({1.0, 0.5, 0.5, 1.0}, "No player target selected")
            if imgui.Button("Config") then show_advanced_window = not show_advanced_window end
        end

        pop_button_theme()
        imgui.End()
    end

    if show_advanced_window then render_advanced_window() end
end)

settings.register('settings', 'settings_update', function (s)
    config = s or config
end)
