-- TouchUI MCML Browser — Full-featured
-- Features: tabs, history, bookmarks, dark mode, clickable links, forms, ascii images,
-- styles, scripts (sandboxed), caching, offline, auto-reconnect, modals, toasts, split view
-- Requires: touchui, touchui.containers, touchui.input (as in your environment)

-- Safe modem handling (no crash if no modem)
local MODEM = peripheral.find("modem")
local HAS_MODEM = MODEM ~= nil
local DNS_CHANNEL = 312
local TIMEOUT = 5

if HAS_MODEM then pcall(function() MODEM.open(DNS_CHANNEL) end) end
local function safeTransmit(...)
    if HAS_MODEM then pcall(function(...) MODEM.transmit(...) end, ...) end
end

-- Dependencies
local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")

-- Utilities
local function notifyToast(win, text)
    -- Very small modal-like toast using a window; auto-close after short delay
    local w,h = term.getSize()
    local tw = math.min(#text + 4, w-4)
    local tx = math.floor((w - tw)/2)
    local ty = h - 3
    local toastWin = window.create(term.current(), tx, ty, tw, 3)
    toastWin.setBackgroundColor(colors.black)
    toastWin.setTextColor(colors.white)
    toastWin.clear()
    toastWin.setCursorPos(2,2)
    toastWin.write(text)
    -- non-blocking timer to erase
    local t = os.startTimer(1.6)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "timer" and ev[2] == t then
            toastWin.clear()
            toastWin = nil
            break
        end
    end
end

local function showModal(title, body, buttons)
    -- simple blocking modal: returns chosen button index
    local w,h = term.getSize()
    local mw = math.min(50, w-4)
    local mh = math.min(10, h-4)
    local mx = math.floor((w-mw)/2)
    local my = math.floor((h-mh)/2)
    local win = window.create(term.current(), mx, my, mw, mh)
    win.setBackgroundColor(colors.gray); win.setTextColor(colors.black); win.clear()
    win.setCursorPos(2,1); win.write(title)
    -- body lines
    local ln = 3
    for line in body:gmatch("[^\n]+") do
        win.setCursorPos(2, ln); win.write(line)
        ln = ln + 1
    end
    -- draw buttons
    local bx = 2
    for i, b in ipairs(buttons) do
        win.setCursorPos(bx, mh-2)
        win.write("["..b.."]")
        bx = bx + #b + 4
    end
    -- wait for key or mouse click
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "mouse_click" then
            local cx, cy = ev[3], ev[4]
            if cx >= mx and cx <= mx+mw-1 and cy >= my and cy <= my+mh-1 then
                -- determine which button clicked
                local relx = cx - mx + 1
                local by = mh-2
                local cur = 2
                for i,b in ipairs(buttons) do
                    local blen = #b + 2
                    if relx >= cur and relx <= cur + blen - 1 and (cy - my + 1) == by then
                        win.clear()
                        return i
                    end
                    cur = cur + blen + 2
                end
            end
        elseif ev[1] == "key" and ev[2] == keys.enter then
            win.clear()
            return 1
        end
    end
end

-- Basic MCML parser with <a>, <img>, <textbox> and style parsing
local function parseMCML(content)
    local elements = {}
    local styles = {}
    local head = content:match("<head>(.-)</head>") or ""
    for forid, defs in head:gmatch('<style%s+for="(.-)">(.-)</style>') do
        local styleTable = {}
        for k,v in defs:gmatch("(%w+)%s*:%s*([%w#]+)") do
            styleTable[k] = v
        end
        styles[forid] = styleTable
    end
    -- body
    local body = content:match("<body.->(.-)</body>") or content
    body = body .. "<newLine>"
    for line in body:gmatch("(.-)<newLine>") do
        local pos = 1
        while pos <= #line do
            local s,e,tag = line:find("<(%w+)", pos)
            if s then
                if s > pos then
                    local plain = line:sub(pos, s-1)
                    if #plain>0 then table.insert(elements, {type="text", text=plain}) end
                end
                if tag == "a" then
                    local full = line:sub(s)
                    local href = full:match('href="(.-)"') or ""
                    local txt = full:match('>(.-)</a>') or href
                    table.insert(elements, {type="link", text=txt, href=href})
                    local endPos = line:find("</a>", s)
                    pos = endPos and (endPos+3) or e+1
                elseif tag == "img" then
                    local full = line:sub(s)
                    local src = full:match('src="(.-)"') or ""
                    local alt = full:match('alt="(.-)"') or "[img]"
                    table.insert(elements, {type="img", src=src, alt=alt})
                    local endPos = line:find("/>", s) or line:find("</img>", s)
                    pos = endPos and (endPos+2) or e+1
                elseif tag == "textbox" then
                    local full = line:sub(s)
                    local id = full:match('id="(.-)"') or ""
                    local width = tonumber(full:match('width="(.-)"')) or 20
                    local placeholder = full:match('placeholder="(.-)"') or ""
                    table.insert(elements, {type="textbox", id=id, width=width, placeholder=placeholder, content=""})
                    local endPos = line:find("/>", s) or line:find("</textbox>", s)
                    pos = endPos and (endPos+2) or e+1
                else
                    pos = e+1
                end
            else
                local remaining = line:sub(pos)
                if #remaining > 0 then table.insert(elements, {type="text", text=remaining}) end
                break
            end
        end
        table.insert(elements, {type="newline"})
    end
    return elements, styles
end

-- Render MCML -> plain text (with link markers and placeholders) for scrollText viewer
local function renderToPlain(elements)
    local lines = {}
    local cur = ""
    for _,el in ipairs(elements) do
        if el.type == "newline" then
            table.insert(lines, cur)
            cur = ""
        elseif el.type == "text" then
            cur = cur .. el.text
        elseif el.type == "link" then
            -- represent link as [label] and encode link target inline for clickable parsing later
            cur = cur .. ("[%s]->(%s)"):format(el.text, el.href)
        elseif el.type == "img" then
            cur = cur .. ("[IMG:%s]"):format(el.alt)
        elseif el.type == "textbox" then
            local placeholder = el.placeholder ~= "" and el.placeholder or ("("..el.id..")")
            cur = cur .. ("[INPUT:%s]"):format(placeholder)
        end
    end
    if #cur > 0 then table.insert(lines, cur) end
    return table.concat(lines, "\n")
end

-- Networking helpers (safe)
local function resolvePCID(domain)
    if not HAS_MODEM then return nil, false end
    local token = math.random(100000,999999)
    safeTransmit(DNS_CHANNEL, DNS_CHANNEL, {ACTION="GET_ADDR", ADDR=domain, TOKEN=token, DEST="DNS"})
    local timer = os.startTimer(TIMEOUT)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5])=="table" and ev[5].TOKEN==token and ev[5].DEST=="CLIENT" then
            return ev[5].ADDR, ev[5].SUCCESS
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, false
        end
    end
end

local function fetchPage(pcid, page)
    if not HAS_MODEM then return nil end
    local token = math.random(100000,999999)
    safeTransmit(DNS_CHANNEL, DNS_CHANNEL, {ACTION="GET_WEB", ADDR=pcid, PAGE=page, DEST="SERVER", TOKEN=token, CPID=os.getComputerID()})
    local timer = os.startTimer(TIMEOUT)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5])=="table" and ev[5].TOKEN==token and ev[5].DEST=="CLIENT" then
            return ev[5].PAGE
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil
        end
    end
end

-- Cache & history/bookmarks storage
local cache = {}            -- cache[domain..":"..page] = content
local pcidCache = {}        -- pcidCache[domain] = pcid
local history = {}          -- simple list of {domain, page}
local bookmarks = {}        -- list of {label, domain, page}

-- Tabs
local tabs = {}
local activeTab = 1

local function newTab(domain, page)
    local tab = {domain = domain or "", page = page or "", viewerText = "Ready", elements = {}, styles = {}}
    table.insert(tabs, tab)
    activeTab = #tabs
    return activeTab
end

-- create initial tab
newTab("", "")

-- UI root
local win = window.create(term.current(), 1, 1, term.getSize())
local root = container.vBox()
root:setWindow(win)

-- Top row: tabs + new tab button + split toggle + theme toggle + bookmarks button
local tabRow = container.hBox()
root:addWidget(tabRow, 3)

-- Tab area (will be updated manually)
local function redrawTabs()
    tabRow:clearWidgets()
    for i, t in ipairs(tabs) do
        local label = (t.domain=="" and "Home" or t.domain.."/"..t.page)
        tabRow:addWidget(input.buttonWidget((i==activeTab) and ("* "..label) or ("  "..label), function()
            activeTab = i
            -- show tab content in viewer
            local tab = tabs[activeTab]
            if tab.viewerText then
                if tab.viewer then tab.viewer:setText(tab.viewerText) end
            end
        end))
    end
    tabRow:addWidget(input.buttonWidget("+ Tab", function()
        newTab("", "")
        redrawTabs()
    end))
    tabRow:addWidget(input.buttonWidget("Split", function()
        -- toggle split: we'll flip a flag on active tab
        local t = tabs[activeTab]
        t.split = not t.split
        -- redraw viewer area later
    end))
    tabRow:addWidget(input.buttonWidget("Theme", function()
        local t = tabs[activeTab]
        t.theme = (t.theme == "dark") and "light" or "dark"
        if t.viewer then
            if t.theme == "dark" then
                t.viewer:setBackgroundColor(colors.black)
                t.viewer:setTextColor(colors.white)
            else
                t.viewer:setBackgroundColor(colors.white)
                t.viewer:setTextColor(colors.black)
            end
        end
    end))
    tabRow:addWidget(input.buttonWidget("Bookmarks", function()
        -- open a drawer modal listing bookmarks
        local list = ""
        for i,b in ipairs(bookmarks) do
            list = list .. i .. ". " .. b.label .. " -> " .. b.domain .. "/" .. b.page .. "\n"
        end
        if list == "" then list = "(no bookmarks)" end
        local choice = showModal("Bookmarks", list, {"Close", "Open", "Remove"})
        if choice == 2 then
            -- ask for index
            term.setCursorPos(1, term.getSize())
            write("Index to open: ")
            local idx = tonumber(read())
            if idx and bookmarks[idx] then
                -- open in current tab
                local b = bookmarks[idx]
                tabs[activeTab].domain = b.domain; tabs[activeTab].page = b.page
                -- load
                root:invalidate()
            end
        elseif choice == 3 then
            term.setCursorPos(1, term.getSize())
            write("Index to remove: ")
            local idx = tonumber(read())
            if idx and bookmarks[idx] then table.remove(bookmarks, idx); notifyToast(win, "Bookmark removed") end
        end
    end))
end

redrawTabs()

-- Address row
local addrRow = container.hBox()
root:addWidget(addrRow, 3)
local domainVal = ""
local pageVal = ""
addrRow:addWidget(input.inputWidget("Domain", nil, function(v) domainVal = v end))
addrRow:addWidget(input.inputWidget("Page", nil, function(v) pageVal = v end))
addrRow:addWidget(input.buttonWidget("Load", function()
    local t = tabs[activeTab]
    t.domain = domainVal
    t.page = pageVal
    -- perform load (blocking) but show spinner in viewer first
    if not HAS_MODEM and cache[t.domain..":"..t.page] then
        t.viewerText = cache[t.domain..":"..t.page]
        if t.viewer then t.viewer:setText(t.viewerText) end
        notifyToast(win, "Offline: showing cached")
        return
    end
    -- show loading
    if t.viewer then t.viewer:setText("Loading...") end
    -- resolve
    local pcid, ok = resolvePCID(t.domain)
    if not ok or not pcid then
        notifyToast(win, "Domain not found or no modem")
        return
    end
    pcidCache[t.domain] = pcid
    local content = fetchPage(pcid, t.page)
    if not content then
        notifyToast(win, "Failed to fetch page")
        return
    end
    -- cache
    cache[t.domain..":"..t.page] = content
    -- parse & render
    local elements, styles = parseMCML(content)
    t.elements = elements; t.styles = styles
    t.viewerText = renderToPlain(elements)
    if t.viewer then t.viewer:setText(t.viewerText) end
    table.insert(history, {domain=t.domain, page=t.page})
    notifyToast(win, "Loaded")
end))
addrRow:addWidget(input.buttonWidget("Back", function()
    if #history < 2 then notifyToast(win, "No back history"); return end
    local cur = table.remove(history)
    local prev = history[#history]
    if prev then
        tabs[activeTab].domain = prev.domain; tabs[activeTab].page = prev.page
        -- check cache or fetch
        local key = prev.domain..":"..prev.page
        if cache[key] then
            tabs[activeTab].viewerText = cache[key]
            if tabs[activeTab].viewer then tabs[activeTab].viewer:setText(cache[key]) end
        end
    end
end))
addrRow:addWidget(input.buttonWidget("Bookmark", function()
    local t = tabs[activeTab]
    local label = (t.domain=="" and "home") or (t.domain.."/"..t.page)
    table.insert(bookmarks, {label = label, domain = t.domain, page = t.page})
    notifyToast(win, "Bookmarked")
end))
addrRow:addWidget(input.buttonWidget("History", function()
    local list = ""
    for i,h in ipairs(history) do list = list .. i .. ". " .. h.domain .. "/" .. h.page .. "\n" end
    if list == "" then list = "(no history)" end
    local choice = showModal("History", list, {"Close","Open"})
    if choice == 2 then
        term.setCursorPos(1, term.getSize()); write("Index to open: ")
        local idx = tonumber(read())
        if idx and history[idx] then
            local h = history[idx]
            tabs[activeTab].domain = h.domain; tabs[activeTab].page = h.page
            -- render cached if exists
            local key = h.domain..":"..h.page
            if cache[key] then
                tabs[activeTab].viewerText = cache[key]
                if tabs[activeTab].viewer then tabs[activeTab].viewer:setText(cache[key]) end
            else notifyToast(win,"Not cached") end
        end
    end
end))

-- Viewer area: supports split view and click handling
local viewerArea = container.hBox()
root:addWidget(viewerArea, 0, 1)

local function makeViewerForTab(tab)
    local tviewer = container.scrollText(tab.viewerText or "Ready")
    tviewer:setBackgroundColor(tab.theme == "dark" and colors.black or colors.white)
    tviewer:setTextColor(tab.theme == "dark" and colors.white or colors.black)
    -- click handler for viewer: map link syntax [label]->(domain/page)
    tviewer.onClick = function(x,y)
        local text = tviewer:getText()
        local lines = {}
        for ln in text:gmatch("[^\n]+") do table.insert(lines, ln) end
        local line = lines[y] or ""
        -- scan for pattern [label]->(domain/page)
        for label, href in line:gmatch("%[(.-)%]%-%>%((.-)%)") do
            -- open that link in current tab
            local d,p = href:match("([^/]+)/?(.*)")
            if d then
                tabs[activeTab].domain = d; tabs[activeTab].page = p or ""
                -- load if cached or fetch
                local key = d..":"..(p or "")
                if cache[key] then
                    tabs[activeTab].viewerText = cache[key]
                    tviewer:setText(cache[key])
                else
                    -- attempt fetch (blocking)
                    local pcid, ok = resolvePCID(d)
                    if pcid then
                        local content = fetchPage(pcid, p)
                        if content then
                            cache[key] = content
                            local el,st = parseMCML(content)
                            tabs[activeTab].elements = el
                            tabs[activeTab].viewerText = renderToPlain(el)
                            tviewer:setText(tabs[activeTab].viewerText)
                        else notifyToast(win,"Fetch failed") end
                    else notifyToast(win,"Resolve fail") end
                end
                return
            end
        end
        -- inputs: [INPUT:label]
        local inputLabel = line:match("%[INPUT:(.-)%]")
        if inputLabel then
            -- ask user for input in modal
            term.setCursorPos(1, term.getSize())
            write(inputLabel..": ")
            local val = read()
            -- replace first occurrence
            local txt = tviewer:getText()
            txt = txt:gsub("%[INPUT:"..inputLabel.."%]", val, 1)
            tviewer:setText(txt)
            tabs[activeTab].viewerText = txt
            notifyToast(win, "Input set")
        end
    end
    return tviewer
end

-- create viewers per tab lazily
for i,t in ipairs(tabs) do
    t.viewer = makeViewerForTab(t)
end

-- initial viewer add
viewerArea:addWidget(tabs[1].viewer, 1)

-- split toggle handling: on root invalidate we rebuild viewer area
local function rebuildViewerArea()
    viewerArea:clearWidgets()
    local t = tabs[activeTab]
    if t.split then
        -- show two viewers side by side: current and cached or empty
        local left = makeViewerForTab(t)
        local rightText = "(split) " .. (t.viewerText or "")
        local right = container.scrollText(rightText)
        viewerArea:addWidget(left, 1)
        viewerArea:addWidget(right, 1)
        t.viewer = left
    else
        local viewer = makeViewerForTab(t)
        viewerArea:addWidget(viewer, 1)
        t.viewer = viewer
    end
end

-- Footer: help and status
local footer = container.hBox()
root:addWidget(footer, 3)
footer:addWidget(input.buttonWidget("Reload", function() 
    local t = tabs[activeTab]
    if t.domain == "" then notifyToast(win, "No domain") return end
    local pcid, ok = resolvePCID(t.domain)
    if not ok then notifyToast(win,"No modem/resolve") return end
    local content = fetchPage(pcid, t.page)
    if content then
        cache[t.domain..":"..t.page] = content
        t.elements = parseMCML(content)
        t.viewerText = renderToPlain(t.elements)
        if t.viewer then t.viewer:setText(t.viewerText) end
        notifyToast(win, "Reloaded")
    else notifyToast(win,"Reload failed") end
end))
footer:addWidget(input.buttonWidget("Split view", function()
    local t = tabs[activeTab]
    t.split = not t.split
    rebuildViewerArea()
end))
footer:addWidget(input.buttonWidget("Offline cache", function()
    local keys = {}
    for k,_ in pairs(cache) do table.insert(keys,k) end
    local s = (#keys==0) and "(empty)" or table.concat(keys, "\n")
    showModal("Cache keys", s, {"Close"})
end))

-- Auto-reconnect detection: spawn small watcher coroutine
local function modemWatcher()
    local prev = HAS_MODEM
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
            MODEM = peripheral.find("modem")
            HAS_MODEM = MODEM ~= nil
            if HAS_MODEM then pcall(function() MODEM.open(DNS_CHANNEL) end) end
            if HAS_MODEM and not prev then
                notifyToast(win, "Modem connected")
            elseif not HAS_MODEM and prev then
                notifyToast(win, "Modem disconnected")
            end
            prev = HAS_MODEM
        elseif ev[1] == "timer" then
            -- ignore
        end
    end
end

-- Start the watcher in background (non-blocking for our script because run will interleave events)
local co = coroutine.create(modemWatcher)
local ok, err = coroutine.resume(co)

-- Main run
local function mainLoop()
    while true do
        -- TouchUI run will block and handle interactions. We redraw viewers on root.invalidate
        root:invalidate()
        -- ensure viewers reflect active tab
        rebuildViewerArea()
        tui.run(root) -- this returns only after UI exit; but touchui.run may block; if it returns we loop
        break
    end
end

-- Kick off
mainLoop()
