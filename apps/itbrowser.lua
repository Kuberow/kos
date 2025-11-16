-- TOUCHUI MCML BROWSER (NO SCROLLING) with MCML parser
-- Features:
--   • MCML parsing: <head><style for="id">..</style></head>, <body>, <text>, <button>, <rect>, <textbox>, <a>, <img>
--   • Tabs, bookmarks, history, back/forward
--   • No-modem safe mode
--   • No scrolling (container.text)
--   • Simple rendering to plain text with markers for interactive elements

-------------------------------------------------
-- SAFE MODEM WRAPPER
-------------------------------------------------
local modem = peripheral.find("modem")
local HAS_MODEM = modem ~= nil

if HAS_MODEM then pcall(function() modem.open(312) end) end

local function tx(...)
    if HAS_MODEM then pcall(function(...) modem.transmit(...) end, ...) end
end

-------------------------------------------------
-- DEPENDENCIES
-------------------------------------------------
local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")

-------------------------------------------------
-- UTILS: simple popup/toast
-------------------------------------------------
local function toast(msg)
    -- minimal non-blocking toast: prints at bottom for a short time
    local w,h = term.getSize()
    local oldBg, oldFg = term.getBackgroundColor(), term.getTextColor()
    term.setBackgroundColor(colors.gray); term.setTextColor(colors.black)
    term.setCursorPos(1, h)
    term.clearLine()
    term.write(msg)
    local t = os.startTimer(1.6)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "timer" and ev[2] == t then break end
    end
    term.setBackgroundColor(oldBg); term.setTextColor(oldFg)
    term.setCursorPos(1, h); term.clearLine()
end

local function modal(title, body)
    -- simple blocking modal (text only) with OK
    local w,h = term.getSize()
    local mw = math.min(50, w-4)
    local mh = math.min(10, h-4)
    local mx = math.floor((w-mw)/2); local my = math.floor((h-mh)/2)
    local win = window.create(term.current(), mx, my, mw, mh)
    win.setBackgroundColor(colors.gray); win.setTextColor(colors.black); win.clear()
    win.setCursorPos(2,1); win.write(title)
    local ln = 3
    for line in body:gmatch("[^\n]+") do
        win.setCursorPos(2,ln); win.write(line); ln = ln + 1
        if ln >= mh-2 then break end
    end
    win.setCursorPos(2, mh-2); win.write("[ OK ]")
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "mouse_click" then
            -- any click inside modal closes
            win.clear(); break
        elseif ev[1] == "key" and ev[2] == keys.enter then
            win.clear(); break
        end
    end
end

-------------------------------------------------
-- MCML PARSER
-------------------------------------------------
local function parseMCML(content)
    -- returns elements (ordered list), styles table
    -- elements are tables like: {type="text", text="..", x=?, y=?, style=...}
    -- or {type="button", text="OK", web="domain", page="p", x=?, y=?, style=...}
    local elements = {}
    local styles = {}

    content = content or ""

    -- parse <head> styles
    local head = content:match("<head>(.-)</head>") or ""
    for forid, defs in head:gmatch('<style%s+for="(.-)">(.-)</style>') do
        local st = {}
        for k,v in defs:gmatch("(%w+)%s*:%s*([#%w]+)") do
            st[k] = v
        end
        styles[forid] = st
    end

    -- find <body ...>...</body>
    local body = content:match("<body.->(.-)</body>") or content

    -- normalize: split by <newLine> tokens (MCML earlier used)
    body = body .. "<newLine>"

    for line in body:gmatch("(.-)<newLine>") do
        local pos = 1
        while pos <= #line do
            local s,e,tag = line:find("<(%w+)", pos)
            if s then
                -- text before tag
                if s > pos then
                    local plain = line:sub(pos, s-1)
                    if #plain > 0 then table.insert(elements, {type="text", text=plain}) end
                end

                if tag == "text" then
                    local full = line:sub(s)
                    local id = full:match('<text%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<text.-x="(.-)"'))
                    local y = tonumber(full:match('<text.-y="(.-)"'))
                    local txt = full:match('>(.-)</text>') or ""
                    local style = (id ~= "" and styles[id]) or {}
                    table.insert(elements, {type="text", text=txt, x=x, y=y, style=style})
                    local endPos = line:find("</text>", s)
                    pos = endPos and (endPos + 7) or (e+1)

                elseif tag == "button" then
                    local full = line:sub(s)
                    local id = full:match('<button%s+id="(.-)"') or ""
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    local x = tonumber(full:match('<button.-x="(.-)"'))
                    local y = tonumber(full:match('<button.-y="(.-)"'))
                    local label = full:match('>(.-)</button>') or ""
                    local style = (id~="" and styles[id]) or {}
                    table.insert(elements, {type="button", text=label, web=web, page=page, x=x, y=y, style=style})
                    local endPos = line:find("</button>", s)
                    pos = endPos and (endPos + 9) or (e+1)

                elseif tag == "rect" then
                    local full = line:sub(s)
                    local x = tonumber(full:match('<rect.-x="(.-)"'))
                    local y = tonumber(full:match('<rect.-y="(.-)"'))
                    local w = tonumber(full:match('<rect.-width="(.-)"')) or 1
                    local h = tonumber(full:match('<rect.-height="(.-)"')) or 1
                    local id = full:match('<rect%s+id="(.-)"') or ""
                    local style = (id~="" and styles[id]) or {}
                    table.insert(elements, {type="rect", x=x, y=y, width=w, height=h, style=style})
                    local endPos = line:find("/>", s) or line:find("</rect>", s)
                    pos = endPos and (endPos + 2) or (e+1)

                elseif tag == "textbox" then
                    local full = line:sub(s)
                    local id = full:match('id="(.-)"') or ""
                    local x = tonumber(full:match('<textbox.-x="(.-)"'))
                    local y = tonumber(full:match('<textbox.-y="(.-)"'))
                    local width = tonumber(full:match('width="(.-)"')) or 20
                    local placeholder = full:match('placeholder="(.-)"') or ""
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    local style = (id~="" and styles[id]) or {}
                    table.insert(elements, {type="textbox", id=id, x=x, y=y, width=width, placeholder=placeholder, content="", web=web, page=page, style=style})
                    local endPos = line:find("/>", s) or line:find("</textbox>", s)
                    pos = endPos and (endPos + 2) or (e+1)

                elseif tag == "a" then
                    local full = line:sub(s)
                    local href = full:match('href="(.-)"') or ""
                    local label = full:match('>(.-)</a>') or href
                    table.insert(elements, {type="link", text=label, href=href})
                    local endPos = line:find("</a>", s)
                    pos = endPos and (endPos + 4) or (e+1)

                elseif tag == "img" then
                    local full = line:sub(s)
                    local src = full:match('src="(.-)"') or ""
                    local alt = full:match('alt="(.-)"') or "[img]"
                    table.insert(elements, {type="img", src=src, alt=alt})
                    local endPos = line:find("/>", s) or line:find("</img>", s)
                    pos = endPos and (endPos + 2) or (e+1)
                else
                    pos = e + 1
                end
            else
                -- remaining text
                local remaining = line:sub(pos)
                if #remaining > 0 then table.insert(elements, {type="text", text=remaining}) end
                break
            end
        end
        table.insert(elements, {type="newline"})
    end

    return elements, styles
end

-------------------------------------------------
-- RENDER MCML -> PLAIN TEXT (with markers)
-------------------------------------------------
local function renderToPlain(elements, styles)
    local lines = {}
    local cur = ""
    for _, el in ipairs(elements) do
        if el.type == "newline" then
            table.insert(lines, cur)
            cur = ""
        elseif el.type == "text" then
            cur = cur .. (el.text or "")
        elseif el.type == "link" then
            -- format: [Label]->(domain/page)
            cur = cur .. ("[%s]->(%s)"):format(el.text, el.href)
        elseif el.type == "button" then
            cur = cur .. ("[BUTTON:%s]"):format(el.text)
        elseif el.type == "img" then
            cur = cur .. ("[IMG:%s]"):format(el.alt)
        elseif el.type == "textbox" then
            local ph = (el.placeholder ~= "" and el.placeholder) or ("("..(el.id or "input")..")")
            cur = cur .. ("[INPUT:%s]"):format(ph)
        elseif el.type == "rect" then
            -- represent rect as block of spaces (single-line placeholder)
            cur = cur .. ("[%dx%d rect]"):format(el.width or 1, el.height or 1)
        else
            -- unknown -> ignore
        end
    end
    if #cur > 0 then table.insert(lines, cur) end
    return table.concat(lines, "\n")
end

-------------------------------------------------
-- NAV + UI STATE
-------------------------------------------------
local tabs = {}
local activeTab = 1
local bookmarks = {}
local history_list = {}
local future_list = {}
local darkMode = false

local function makeTab()
    return {
        domain = "",
        page = "",
        raw = "",
        elements = {},
        styles = {},
        text = "Blank tab.\nEnter domain & page.",
    }
end

table.insert(tabs, makeTab())

-------------------------------------------------
-- NETWORK HELPERS (DNS + fetch)
-------------------------------------------------
local function resolvePCID(domain)
    if not HAS_MODEM then return nil, false end
    local token = math.random(100000,999999)
    tx(312, 312, {ACTION="GET_ADDR", ADDR=domain, TOKEN=token, DEST="DNS"})
    local timer = os.startTimer(5)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5]) == "table" and ev[5].TOKEN == token and ev[5].DEST == "CLIENT" then
            return ev[5].ADDR, ev[5].SUCCESS
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, false
        end
    end
end

local function fetchPage(pcid, page)
    if not HAS_MODEM then return nil end
    local token = math.random(100000,999999)
    tx(312, 312, {ACTION="GET_WEB", ADDR=pcid, PAGE=page, DEST="SERVER", TOKEN=token, CPID=os.getComputerID()})
    local timer = os.startTimer(5)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5])=="table" and ev[5].TOKEN==token and ev[5].DEST=="CLIENT" then
            return ev[5].PAGE
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil
        end
    end
end

-- simple in-memory cache
local cache = {}

-------------------------------------------------
-- UI: TouchUI layout
-------------------------------------------------
local win = window.create(term.current(), 1, 1, term.getSize())
local root = container.vBox()
root:setWindow(win)

-- Tab bar
local tabBar = container.hBox()
root:addWidget(tabBar, 3)
local function redrawTabs()
    tabBar:clearWidgets()
    for i, t in ipairs(tabs) do
        local lab = (t.domain == "" and ("Tab "..i) or (t.domain .. "/" .. t.page))
        tabBar:addWidget(input.buttonWidget((i==activeTab) and ("* "..lab) or ("  "..lab), function()
            activeTab = i
            viewer:setText(t.text)
        end), 3)
    end
    tabBar:addWidget(input.buttonWidget("+", function()
        table.insert(tabs, makeTab())
        activeTab = #tabs
        redrawTabs()
        viewer:setText(tabs[activeTab].text)
    end), 3)
end

-- Address inputs
local addrRow = container.hBox()
root:addWidget(addrRow, 3)

local domainVal = ""
local pageVal = ""
addrRow:addWidget(input.inputWidget("Domain", nil, function(v) domainVal = v end))
addrRow:addWidget(input.inputWidget("Page", nil, function(v) pageVal = v end))

-- Load & nav buttons
local navRow = container.hBox()
root:addWidget(navRow, 3)
navRow:addWidget(input.buttonWidget("Load", function()
    local t = tabs[activeTab]
    if domainVal == "" or pageVal == "" then toast("Domain or page empty"); return end
    -- try cache
    local key = domainVal .. ":" .. pageVal
    if cache[key] then
        t.raw = cache[key]
        t.elements, t.styles = parseMCML(t.raw)
        t.text = renderToPlain(t.elements, t.styles)
        viewer:setText(t.text)
        toast("Loaded from cache")
        table.insert(history_list, {domain = domainVal, page = pageVal})
        return
    end
    -- resolve
    local pcid, ok = resolvePCID(domainVal)
    if not ok or not pcid then
        toast("Domain not found or no modem")
        return
    end
    local raw = fetchPage(pcid, pageVal)
    if not raw then
        toast("Failed to fetch")
        return
    end
    cache[key] = raw
    t.raw = raw
    t.elements, t.styles = parseMCML(raw)
    t.text = renderToPlain(t.elements, t.styles)
    viewer:setText(t.text)
    t.domain = domainVal; t.page = pageVal
    table.insert(history_list, {domain = domainVal, page = pageVal})
end))
navRow:addWidget(input.buttonWidget("< Back", function()
    if #history_list < 2 then toast("No history"); return end
    local cur = table.remove(history_list)
    local prev = history_list[#history_list]
    if prev then
        local t = tabs[activeTab]
        local key = prev.domain .. ":" .. prev.page
        if cache[key] then
            t.raw = cache[key]
            t.elements, t.styles = parseMCML(t.raw)
            t.text = renderToPlain(t.elements, t.styles)
            t.domain = prev.domain; t.page = prev.page
            viewer:setText(t.text)
        else
            toast("Not cached")
        end
    end
end))
navRow:addWidget(input.buttonWidget("Forward >", function()
    toast("Forward not implemented in history list mode")
end))
navRow:addWidget(input.buttonWidget("Bookmark", function()
    local t = tabs[activeTab]
    if t.domain == "" then toast("No domain to bookmark"); return end
    table.insert(bookmarks, {label = t.domain .. "/" .. t.page, domain = t.domain, page = t.page})
    toast("Bookmarked")
end))
navRow:addWidget(input.buttonWidget("Bookmarks", function()
    if #bookmarks == 0 then modal("Bookmarks", "(none)"); return end
    local s = ""
    for i,b in ipairs(bookmarks) do s = s .. i .. ". " .. b.label .. "\n" end
    modal("Bookmarks", s)
end))

-- Viewer (no scrolling)
local viewer = container.text("Ready.\nEnter domain and page then Load.")
root:addWidget(viewer, 0, 1) -- take remaining space

-- Clicking / input handling: simple method — ask user to type exact marker to interact
-- For now, interactive actions are handled by the user typing commands via the terminal line.
-- (Because container.text does not provide per-character click coords portably.)
-- Provide quick helper commands at bottom:
local helperRow = container.hBox()
root:addWidget(helperRow, 3)
helperRow:addWidget(input.buttonWidget("Run link", function()
    -- ask which link label or index
    term.setCursorPos(1, term.getSize()); write("Enter link target (domain/page): ")
    local targ = read()
    if not targ or targ == "" then return end
    -- parse domain/page
    local d,p = targ:match("([^/]+)/?(.*)")
    if not d then toast("Bad target"); return end
    -- load into current tab (attempt cache first)
    local t = tabs[activeTab]
    local key = d .. ":" .. (p or "")
    if cache[key] then
        t.raw = cache[key]
        t.elements, t.styles = parseMCML(t.raw)
        t.text = renderToPlain(t.elements, t.styles)
        t.domain = d; t.page = p
        viewer:setText(t.text)
        toast("Opened cached")
    else
        local pcid, ok = resolvePCID(d)
        if not ok then toast("Resolve failed"); return end
        local raw = fetchPage(pcid, p)
        if not raw then toast("Fetch failed"); return end
        cache[key] = raw
        t.raw = raw
        t.elements, t.styles = parseMCML(raw)
        t.text = renderToPlain(t.elements, t.styles)
        t.domain = d; t.page = p
        viewer:setText(t.text)
        toast("Loaded")
    end
end))
helperRow:addWidget(input.buttonWidget("Fill input", function()
    term.setCursorPos(1, term.getSize()); write("Enter replacement text: ")
    local val = read()
    if not val then return end
    local t = tabs[activeTab]
    local txt = t.text:gsub("%[INPUT:.-%]", val, 1)
    t.text = txt
    viewer:setText(txt)
    toast("Replaced first input")
end))
helperRow:addWidget(input.buttonWidget("Show raw", function()
    local t = tabs[activeTab]
    modal("Raw MCML", (t.raw ~= "" and t.raw) or "(empty)")
end))

-- initial redraw
redrawTabs()
viewer:setText(tabs[activeTab].text)

-- run
tui.run(root)
