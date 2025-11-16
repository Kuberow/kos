-- MITP Website Client (CPID-aware) with Scrolling, Back/Forward, Pocket support, Safe modem
-- Full assembled client

-- CONFIG
local DNS_CHANNEL = 312
local TIMEOUT_SECONDS = 5

-- Try to find modem but don't error if missing
local MODEM = peripheral.find("modem")
local HAS_MODEM = MODEM ~= nil
if HAS_MODEM then
    pcall(function() MODEM.open(DNS_CHANNEL) end)
end

local function safeTransmit(...)
    if not HAS_MODem and not HAS_MODEM then return end -- harmless guard if spelled wrongly
    if HAS_MODEM then
        pcall(function(...) MODEM.transmit(...) end, ...)
    end
end

-- Utilities
local TOKEN_COUNTER = 0
local function getToken()
    TOKEN_COUNTER = TOKEN_COUNTER + 1
    return math.random(1000,9999) + TOKEN_COUNTER
end

-- color map (keeps your earlier mapping convenience)
local colors_table = {
    black=colors.black, white=colors.white, red=colors.red,
    green=colors.green, blue=colors.blue, yellow=colors.yellow,
    cyan=colors.cyan, magenta=colors.magenta, gray=colors.gray,
    lightGray=colors.lightGray, orange=colors.orange
}

-- Determine pocket/computer sizing
local function detectPocket()
    local w,h = term.getSize()
    -- Pocket computers are narrow and short; use heuristic
    return (w <= 26 and h <= 11)
end
local isPocket = detectPocket()

-- UI tuning
local UI = {
    scrollStep = isPocket and 1 or 1, -- you can tweak to 2 for large screens
    topBarHeight = 1,
    bottomBarHeight = 1,
    leftMenuWidth = isPocket and 6 or 8
}

-- Navigation stacks
local history = {}
local future = {}
local currentDomain = ""
local currentPage = ""

-- Scrolling globals
local scrollY = 0
local maxScrollY = 0
local contentHeight = 0

-- Loading flag & spinner
local loading = false
local spinnerFrames = {"-", "\\", "|", "/"}
local spinnerIndex = 1

-- Safe modem-aware DNS resolution: returns pcid, ok
local function getPCID(domain)
    if not HAS_MODEM then
        return nil, false
    end
    local token = getToken()
    safeTransmit(DNS_CHANNEL, DNS_CHANNEL, {
        ACTION="GET_ADDR",
        ADDR=domain,
        TOKEN=token,
        DEST="DNS"
    })
    local timer = os.startTimer(TIMEOUT_SECONDS)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5])=="table" and ev[5].TOKEN==token and ev[5].DEST=="CLIENT" then
            return ev[5].ADDR, ev[5].SUCCESS
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil, false
        end
    end
end

-- Safe getPage
local function getPage(serverPCID, page)
    if not HAS_MODEM then
        return nil
    end
    local token = getToken()
    safeTransmit(DNS_CHANNEL, DNS_CHANNEL, {
        ACTION="GET_WEB",
        ADDR=serverPCID,
        PAGE=page,
        DEST="SERVER",
        TOKEN=token,
        CPID=os.getComputerID()
    })
    local timer = os.startTimer(TIMEOUT_SECONDS)
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" and type(ev[5])=="table" and ev[5].TOKEN==token and ev[5].DEST=="CLIENT" then
            return ev[5].PAGE
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil
        end
    end
end

-- MCML parser (kept from your original with minor adjustments)
local function parseMCML(content)
    local elements = {}
    local styles = {}

    -- Parse head styles
    local head = content:match("<head>(.-)</head>") or ""
    for forid, defs in head:gmatch('<style%s+for="(.-)">(.-)</style>') do
        local styleTable = {}
        for k,v in defs:gmatch("(%w+)%s*:%s*(%w+)") do
            styleTable[k] = v
        end
        styles[forid] = styleTable
    end

    -- Parse body
    local bodyID, bodyContent = content:match('<body%s+id="(.-)">(.-)</body>')
    if not bodyID then
        bodyContent = content:match('<body.->(.-)</body>') or ""
        bodyID = "body"
    end
    local bodyStyle = styles[bodyID] or {}

    -- Split by <newLine> and append it to process last line
    bodyContent = bodyContent .. "<newLine>"
    
    for line in bodyContent:gmatch("(.-)<newLine>") do
        local pos = 1
        while pos <= #line do
            local s,e,tag = line:find("<(%w+)", pos)
            if s then
                if s > pos then
                    local plain = line:sub(pos, s-1)
                    if #plain>0 then
                        table.insert(elements,{type="text", text=plain, style=bodyStyle})
                    end
                end

                if tag=="text" then
                    local full = line:sub(s)
                    local id = full:match('<text%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<text.-x="(.-)"'))
                    local y = tonumber(full:match('<text.-y="(.-)"'))
                    local text = full:match('<text.->(.-)</text>') or ""
                    local style = (id~="" and styles[id]) or bodyStyle
                    table.insert(elements,{type="text", text=text, style=style, x=x, y=y})
                    local endPos = line:find("</text>", s)
                    pos = endPos and (endPos + 7) or (e + 1)
                    
                elseif tag=="button" then
                    local full = line:sub(s)
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    local id = full:match('id="(.-)"') or ""
                    local x = tonumber(full:match('<button.-x="(.-)"'))
                    local y = tonumber(full:match('<button.-y="(.-)"'))
                    local label = full:match('<button.->(.-)</button>') or ""
                    local style = (id~="" and styles[id]) or bodyStyle
                    -- Set default button colors
                    style = {
                        textColor = style.textColor or "white",
                        bgColor = style.bgColor or "blue"
                    }
                    table.insert(elements,{type="button", text=label, web=web, page=page, style=style, x=x, y=y})
                    local endPos = line:find("</button>", s)
                    pos = endPos and (endPos + 9) or (e + 1)
                    
                elseif tag=="rect" then
                    local full = line:sub(s)
                    local id = full:match('<rect%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<rect.-x="(.-)"'))
                    local y = tonumber(full:match('<rect.-y="(.-)"'))
                    local width = tonumber(full:match('<rect.-width="(.-)"')) or 1
                    local height = tonumber(full:match('<rect.-height="(.-)"')) or 1
                    local style = (id~="" and styles[id]) or bodyStyle
                    table.insert(elements,{type="rect", width=width, height=height, style=style, x=x, y=y})
                    local endPos = line:find("/>", s) or line:find("</rect>", s)
                    pos = endPos and (endPos + 2) or (e + 1)
                    
                elseif tag=="textbox" then
                    local full = line:sub(s)
                    local id = full:match('<textbox%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<textbox.-x="(.-)"'))
                    local y = tonumber(full:match('<textbox.-y="(.-)"'))
                    local width = tonumber(full:match('<textbox.-width="(.-)"')) or 10
                    local height = tonumber(full:match('<textbox.-height="(.-)"')) or 1
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    local style = (id~="" and styles[id]) or bodyStyle
                    table.insert(elements,{type="textbox", id=id, width=width, height=1, web=web, page=page, style=style, x=x, y=y, content=""})
                    local endPos = line:find("/>", s) or line:find("</textbox>", s)
                    pos = endPos and (endPos + 2) or (e + 1)
                else
                    pos = e+1
                end
            else
                local remaining = line:sub(pos)
                if #remaining>0 then
                    table.insert(elements,{type="text", text=remaining, style=bodyStyle})
                end
                break
            end
        end
        table.insert(elements,{type="newline"})
    end

    return elements, styles, bodyID, bodyStyle
end

-- Calculate content height for scrolling
local function calculateContentHeight(elements)
    local maxY = 2  -- Start from line 2
    local currentY = 2
    for _, el in ipairs(elements) do
        if el.type == "newline" then
            currentY = currentY + 1
            if currentY > maxY then maxY = currentY end
        elseif el.type == "text" then
            local elY = el.y or currentY
            if elY > currentY then currentY = elY end
            if elY > maxY then maxY = elY end
            -- advance currentX by length only when in-line; but for height we ignore
        elseif el.type == "button" then
            local elY = el.y or currentY
            if elY > currentY then currentY = elY end
            if elY > maxY then maxY = elY end
        elseif el.type == "rect" then
            local elY = el.y or currentY
            local bottom = elY + (el.height or 1) - 1
            if bottom > maxY then maxY = bottom end
            currentY = elY + (el.height or 1)
        elseif el.type == "textbox" then
            local elY = el.y or currentY
            local bottom = elY + 2 -- textbox with border
            if bottom > maxY then maxY = bottom end
            currentY = elY + 3
        end
    end
    return maxY
end

-- Render MCML with scrolling
local function renderMCML(elements, bodyStyle)
    local bg = colors_table[bodyStyle.bgColor] or colors.black
    local fg = colors_table[bodyStyle.textColor] or colors.white
    term.setBackgroundColor(bg)
    term.setTextColor(fg)

    -- Clear main area (below top bar and left menu)
    local screenWidth, screenHeight = term.getSize()
    for i = UI.topBarHeight + 1, screenHeight - UI.bottomBarHeight do
        term.setCursorPos(1, i)
        term.clearLine()
    end

    local x,y = UI.leftMenuWidth + 1, UI.topBarHeight + 1
    local buttons = {}
    local textboxes = {}

    for _, el in ipairs(elements) do
        if el.type == "newline" then
            y = y + 1
            x = UI.leftMenuWidth + 1
        elseif el.type == "text" then
            if el.x and el.y then
                x = el.x + UI.leftMenuWidth
                y = el.y + UI.topBarHeight
            end
            local renderY = y - scrollY
            if renderY >= UI.topBarHeight + 1 and renderY <= screenHeight - UI.bottomBarHeight then
                local fgclr = colors_table[el.style.textColor] or colors_table[bodyStyle.textColor] or colors.white
                local bgclr = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or bg
                term.setTextColor(fgclr)
                term.setBackgroundColor(bgclr)
                term.setCursorPos(x, renderY)
                term.write(el.text)
            end
            x = x + #el.text
        elseif el.type == "button" then
            if el.x and el.y then
                x = el.x + UI.leftMenuWidth
                y = el.y + UI.topBarHeight
            end
            local renderY = y - scrollY
            if renderY >= UI.topBarHeight + 1 and renderY <= screenHeight - UI.bottomBarHeight then
                local fgclr = colors_table[el.style.textColor] or colors.white
                local bgclr = colors_table[el.style.bgColor] or colors.blue
                term.setTextColor(fgclr)
                term.setBackgroundColor(bgclr)
                term.setCursorPos(x, renderY)
                term.write(" "..el.text.." ")
                table.insert(buttons, {x=x, y=renderY, w=#el.text+2, web=el.web, page=el.page, originalY = y})
            end
            x = x + #el.text + 2
        elseif el.type == "rect" then
            if el.x and el.y then
                x = el.x + UI.leftMenuWidth
                y = el.y + UI.topBarHeight
            end
            local bgclr = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or bg
            term.setBackgroundColor(bgclr)
            for row = 0, (el.height or 1)-1 do
                local renderY = y + row - scrollY
                if renderY >= UI.topBarHeight + 1 and renderY <= screenHeight - UI.bottomBarHeight then
                    term.setCursorPos(x, renderY)
                    term.write(string.rep(" ", el.width or 1))
                end
            end
            x = x + (el.width or 1)
        elseif el.type == "textbox" then
            if el.x and el.y then
                x = el.x + UI.leftMenuWidth
                y = el.y + UI.topBarHeight
            end
            local fgclr = colors_table[el.style.textColor] or colors_table[bodyStyle.textColor] or colors.white
            local bgclr = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or colors.black
            local borderColor = colors_table[el.style.borderColor] or colors.white
            for row = 0, 2 do
                local renderY = y + row - scrollY
                if renderY >= UI.topBarHeight + 1 and renderY <= screenHeight - UI.bottomBarHeight then
                    term.setBackgroundColor(borderColor)
                    term.setTextColor(borderColor)
                    term.setCursorPos(x, renderY)
                    if row == 0 then
                        term.write("+" .. string.rep("-", el.width) .. "+")
                    elseif row == 1 then
                        term.write("|")
                        term.setBackgroundColor(bgclr)
                        term.setTextColor(fgclr)
                        term.write(string.rep(" ", el.width))
                        term.setBackgroundColor(borderColor)
                        term.setTextColor(borderColor)
                        term.write("|")
                    else
                        term.write("+" .. string.rep("-", el.width) .. "+")
                    end
                end
            end
            local contentY = y + 1 - scrollY
            if contentY >= UI.topBarHeight + 1 and contentY <= screenHeight - UI.bottomBarHeight then
                if el.content and #el.content > 0 then
                    term.setBackgroundColor(bgclr)
                    term.setTextColor(fgclr)
                    term.setCursorPos(x+1, contentY)
                    if #el.content > el.width then
                        term.write(el.content:sub(1, el.width))
                    else
                        term.write(el.content)
                    end
                end
            end
            table.insert(textboxes, {
                x = x+1, y = y+1, width = el.width, height = 1,
                id = el.id, web = el.web, page = el.page,
                content = el.content or "",
                bg = bgclr, fg = fgclr, borderColor = borderColor,
                originalY = y+1
            })
            x = x + el.width + 2
        end
    end

    -- Draw scrollbar if needed
    local availableHeight = (screenHeight - UI.topBarHeight - UI.bottomBarHeight)
    if contentHeight <= availableHeight then
        maxScrollY = 0
    else
        maxScrollY = math.max(0, contentHeight - availableHeight)
    end

    if maxScrollY > 0 then
        local scrollbarX = screenWidth
        local scrollbarHeight = math.max(1, math.floor(availableHeight * (availableHeight / contentHeight)))
        local scrollbarPos = UI.topBarHeight + 1 + math.floor((scrollY / math.max(1,maxScrollY)) * (availableHeight - scrollbarHeight))
        for yPos = UI.topBarHeight + 1, screenHeight - UI.bottomBarHeight do
            term.setCursorPos(scrollbarX, yPos)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.gray)
            if yPos >= scrollbarPos and yPos < scrollbarPos + scrollbarHeight then
                term.write("#")
            else
                term.write("|")
            end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    return buttons, textboxes
end

-- textbox interaction (works with scroll)
local function handleTextboxInput(textbox)
    local content = textbox.content or ""
    local cursorPos = #content + 1
    local screenY = textbox.originalY - scrollY
    local _, screenHeight = term.getSize()
    if screenY < UI.topBarHeight + 1 or screenY > screenHeight - UI.bottomBarHeight then
        return content, false
    end

    term.setBackgroundColor(textbox.bg)
    term.setTextColor(textbox.fg)
    term.setCursorPos(textbox.x, screenY)
    term.write(string.rep(" ", textbox.width))
    term.setCursorPos(textbox.x, screenY)
    term.write(content)
    term.setCursorPos(textbox.x + cursorPos - 1, screenY)

    while true do
        local event = {os.pullEvent()}
        if event[1] == "char" then
            if #content < textbox.width then
                content = content:sub(1, cursorPos - 1) .. event[2] .. content:sub(cursorPos)
                cursorPos = cursorPos + 1
                term.write(event[2])
            end
        elseif event[1] == "key" then
            local key = event[2]
            if key == keys.enter then
                if textbox.web and textbox.web ~= "" and textbox.page and textbox.page ~= "" then
                    return content, true
                else
                    return content, false
                end
            elseif key == keys.backspace then
                if cursorPos > 1 then
                    content = content:sub(1, cursorPos - 2) .. content:sub(cursorPos)
                    cursorPos = cursorPos - 1
                    term.setCursorPos(textbox.x, screenY)
                    term.write(content .. " ")
                    term.setCursorPos(textbox.x + cursorPos - 1, screenY)
                end
            elseif key == keys.left then
                if cursorPos > 1 then
                    cursorPos = cursorPos - 1
                    term.setCursorPos(textbox.x + cursorPos - 1, screenY)
                end
            elseif key == keys.right then
                if cursorPos <= #content then
                    cursorPos = cursorPos + 1
                    term.setCursorPos(textbox.x + cursorPos - 1, screenY)
                end
            end
        elseif event[1] == "mouse_click" then
            local clickX, clickY = event[3], event[4]
            if clickY == screenY and clickX >= textbox.x and clickX <= textbox.x + textbox.width - 1 then
                cursorPos = math.min(clickX - textbox.x + 1, #content + 1)
                term.setCursorPos(textbox.x + cursorPos - 1, screenY)
            else
                return content, false
            end
        end
    end
end

-- UI drawing helpers
local function drawTopBar(domain, page, isLoading)
    local w,h = term.getSize()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.setCursorPos(1,1)
    term.clearLine()

    -- left mini-buttons
    term.setCursorPos(1,1)
    term.write(" < ")
    term.setCursorPos(4,1)
    term.write(" > ")

    -- home
    local homeText = "[H]"
    term.setCursorPos(w-18, 1)
    term.write(homeText)

    -- refresh
    term.setCursorPos(w-11, 1)
    term.write("[⟳]")

    -- spinner
    if isLoading then
        spinnerIndex = spinnerIndex + 1
        if spinnerIndex > #spinnerFrames then spinnerIndex = 1 end
        term.setCursorPos(w,1)
        term.write(spinnerFrames[spinnerIndex])
    else
        term.setCursorPos(w,1)
        term.write(" ")
    end

    -- domain/page string (trim to available)
    local midStart = 7
    local midEnd = w - UI.leftMenuWidth - 20
    local text = (domain == "" and "offline") or (domain .. "/" .. page)
    if #text > (w - midStart - 20) then
        text = text:sub(1, w - midStart - 20)
    end
    term.setCursorPos(midStart,1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.write(" " .. text .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function drawSideMenu()
    local w,h = term.getSize()
    for i=1,h do
        term.setCursorPos(1,i)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        if i == 2 then
            term.clearLine()
            local label = " Back "
            term.setCursorPos(1,2)
            term.write(label)
        elseif i == 3 then
            term.clearLine()
            term.setCursorPos(1,3)
            term.write(" Forward ")
        elseif i == 4 then
            term.clearLine()
            term.setCursorPos(1,4)
            term.write(" Reload ")
        elseif i == 5 then
            term.clearLine()
            term.setCursorPos(1,5)
            term.write(" Exit ")
        else
            term.clearLine()
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function drawStatusBar(status)
    local w,h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    term.clearLine()
    term.setCursorPos(1, h)
    term.write("Status: " .. status)
    if maxScrollY > 0 then
        term.setCursorPos(w-16, h)
        term.write(("Scroll %d/%d"):format(scrollY, maxScrollY))
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Navigation helpers
local function pushHistory(domain, page)
    if currentDomain ~= "" or currentPage ~= "" then
        table.insert(history, {domain=currentDomain, page=currentPage})
    end
end

local function loadPage(domain, page, fromHistory)
    -- manage history
    if not fromHistory then
        pushHistory(currentDomain, currentPage)
        future = {}
    end

    currentDomain = domain
    currentPage = page

    -- attempt to get page
    if not HAS_MODEM then
        return nil, "offline"
    end

    local pcid, ok = getPCID(domain)
    if not ok or not pcid then
        return nil, "dns"
    end
    local content = getPage(pcid, page)
    if not content then
        return nil, "fetch"
    end
    return content, "ok"
end

local function goBack()
    if #history == 0 then return nil end
    local last = table.remove(history)
    table.insert(future, {domain=currentDomain, page=currentPage})
    currentDomain = last.domain
    currentPage = last.page
    local content, status = loadPage(last.domain, last.page, true)
    return content, status
end

local function goForward()
    if #future == 0 then return nil end
    local nextPg = table.remove(future)
    table.insert(history, {domain=currentDomain, page=currentPage})
    currentDomain = nextPg.domain
    currentPage = nextPg.page
    local content, status = loadPage(nextPg.domain, nextPg.page, true)
    return content, status
end

-- Open page high-level: parse, render, and handle input loop
local function openPage(domain, page)
    -- reset scroll
    scrollY = 0
    maxScrollY = 0
    contentHeight = 0

    drawTopBar(domain, page, true)
    drawSideMenu()
    drawStatusBar("Loading...")

    loading = true
    local content, status = loadPage(domain, page)
    loading = false

    if not content then
        drawTopBar(domain, page, false)
        drawStatusBar(status == "offline" and "Offline (no modem)" or ("Error: "..tostring(status)))
        term.setCursorPos(UI.leftMenuWidth + 2, UI.topBarHeight + 2)
        if status == "offline" then
            print("No modem available. You are in offline mode.")
        elseif status == "dns" then
            print("Domain not found.")
        else
            print("Failed to fetch page.")
        end
        os.pullEvent("key") -- wait for key press to continue
        return
    end

    -- parse & render
    local elements, styles, bodyID, bodyStyle = parseMCML(content)
    contentHeight = calculateContentHeight(elements)

    local screenW, screenH = term.getSize()
    local availableHeight = screenH - UI.topBarHeight - UI.bottomBarHeight
    maxScrollY = math.max(0, contentHeight - availableHeight)

    -- Render initial
    drawTopBar(domain, page, false)
    drawSideMenu()
    drawStatusBar("OK")
    local buttons, textboxes = renderMCML(elements, bodyStyle)

    -- input loop
    while true do
        local e = {os.pullEvent()}
        if e[1] == "mouse_click" then
            local cx, cy = e[3], e[4]

            -- Top bar clicks
            local w,h = term.getSize()
            if cy == 1 then
                if cx >= 1 and cx <= 1 then
                    -- back button top-left
                    local content, stat = goBack()
                    if content then
                        elements, styles, bodyID, bodyStyle = parseMCML(content)
                        contentHeight = calculateContentHeight(elements)
                        maxScrollY = math.max(0, contentHeight - (term.getSize() - UI.topBarHeight - UI.bottomBarHeight))
                        scrollY = 0
                        drawTopBar(currentDomain, currentPage, false)
                        drawSideMenu()
                        drawStatusBar("OK")
                        buttons, textboxes = renderMCML(elements, bodyStyle)
                    else
                        drawStatusBar("No history")
                    end
                    goto continue
                elseif cx >= 4 and cx <= 4 then
                    -- forward top-left
                    local content, stat = goForward()
                    if content then
                        elements, styles, bodyID, bodyStyle = parseMCML(content)
                        contentHeight = calculateContentHeight(elements)
                        maxScrollY = math.max(0, contentHeight - (term.getSize() - UI.topBarHeight - UI.bottomBarHeight))
                        scrollY = 0
                        drawTopBar(currentDomain, currentPage, false)
                        drawSideMenu()
                        drawStatusBar("OK")
                        buttons, textboxes = renderMCML(elements, bodyStyle)
                    else
                        drawStatusBar("No forward")
                    end
                    goto continue
                end

                -- home click region
                if cx >= w-18 and cx <= w-14 then
                    -- simple home: go to root domain (empty)
                    openPage("","")
                    return
                end
                -- refresh
                if cx >= w-11 and cx <= w-6 then
                    openPage(currentDomain,currentPage)
                    return
                end
            end

            -- Side menu clicks (Left side)
            if cx >= 1 and cx <= UI.leftMenuWidth then
                if cy == 2 then
                    -- Back
                    local content, stat = goBack()
                    if content then
                        elements, styles, bodyID, bodyStyle = parseMCML(content)
                        contentHeight = calculateContentHeight(elements)
                        maxScrollY = math.max(0, contentHeight - (term.getSize() - UI.topBarHeight - UI.bottomBarHeight))
                        scrollY = 0
                        drawTopBar(currentDomain, currentPage, false)
                        drawSideMenu()
                        drawStatusBar("OK")
                        buttons, textboxes = renderMCML(elements, bodyStyle)
                    else
                        drawStatusBar("No history")
                    end
                    goto continue
                elseif cy == 3 then
                    -- Forward
                    local content, stat = goForward()
                    if content then
                        elements, styles, bodyID, bodyStyle = parseMCML(content)
                        contentHeight = calculateContentHeight(elements)
                        maxScrollY = math.max(0, contentHeight - (term.getSize() - UI.topBarHeight - UI.bottomBarHeight))
                        scrollY = 0
                        drawTopBar(currentDomain, currentPage, false)
                        drawSideMenu()
                        drawStatusBar("OK")
                        buttons, textboxes = renderMCML(elements, bodyStyle)
                    else
                        drawStatusBar("No forward")
                    end
                    goto continue
                elseif cy == 4 then
                    -- Reload
                    openPage(currentDomain, currentPage)
                    return
                elseif cy == 5 then
                    -- Exit
                    term.clear()
                    term.setCursorPos(1,1)
                    return
                end
            end

            -- Check page buttons
            for _,btn in ipairs(buttons) do
                if cy==btn.y and cx>=btn.x and cx<=btn.x+btn.w-1 then
                    openPage(btn.web, btn.page)
                    return
                end
            end

            -- Check textboxes
            for _,tb in ipairs(textboxes) do
                local screenY = tb.originalY - scrollY
                if cy == screenY and cx >= tb.x and cx <= tb.x + tb.width - 1 then
                    local newContent, shouldNav = handleTextboxInput(tb)
                    tb.content = newContent
                    -- redraw the textbox content
                    term.setBackgroundColor(tb.bg)
                    term.setTextColor(tb.fg)
                    term.setCursorPos(tb.x, screenY)
                    term.write(string.rep(" ", tb.width))
                    term.setCursorPos(tb.x, screenY)
                    term.write((#newContent > tb.width) and newContent:sub(1, tb.width) or newContent)

                    if shouldNav and tb.web and tb.page then
                        openPage(tb.web, tb.page .. "?" .. newContent)
                        return
                    end
                    break
                end
            end

        elseif e[1] == "key" then
            local key = e[2]
            if key == keys.up then
                if scrollY - UI.scrollStep >= 0 then
                    scrollY = scrollY - UI.scrollStep
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawTopBar(currentDomain,currentPage,false)
                    drawSideMenu()
                    drawStatusBar("OK")
                end
            elseif key == keys.down then
                if scrollY + UI.scrollStep <= maxScrollY then
                    scrollY = math.min(maxScrollY, scrollY + UI.scrollStep)
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawTopBar(currentDomain,currentPage,false)
                    drawSideMenu()
                    drawStatusBar("OK")
                end
            elseif key == keys.pageUp then
                local _, screenH = term.getSize()
                local step = math.max(1, screenH - UI.topBarHeight - UI.bottomBarHeight - 1)
                scrollY = math.max(0, scrollY - step)
                buttons, textboxes = renderMCML(elements, bodyStyle)
                drawTopBar(currentDomain,currentPage,false)
                drawSideMenu()
                drawStatusBar("OK")
            elseif key == keys.pageDown then
                local _, screenH = term.getSize()
                local step = math.max(1, screenH - UI.topBarHeight - UI.bottomBarHeight - 1)
                scrollY = math.min(maxScrollY, scrollY + step)
                buttons, textboxes = renderMCML(elements, bodyStyle)
                drawTopBar(currentDomain,currentPage,false)
                drawSideMenu()
                drawStatusBar("OK")
            elseif key == keys.home then
                scrollY = 0
                buttons, textboxes = renderMCML(elements, bodyStyle)
                drawTopBar(currentDomain,currentPage,false)
                drawSideMenu()
                drawStatusBar("OK")
            elseif key == keys["end"] then
                scrollY = maxScrollY
                buttons, textboxes = renderMCML(elements, bodyStyle)
                drawTopBar(currentDomain,currentPage,false)
                drawSideMenu()
                drawStatusBar("OK")
            elseif key == keys.f5 then
                openPage(currentDomain,currentPage)
                return
            end
        elseif e[1] == "mouse_scroll" then
            local dir = e[2]
            -- dir is 1 or -1; map to lines (invert so wheel down scrolls down)
            local delta = -dir * UI.scrollStep
            scrollY = math.max(0, math.min(maxScrollY, scrollY + delta))
            buttons, textboxes = renderMCML(elements, bodyStyle)
            drawTopBar(currentDomain,currentPage,false)
            drawSideMenu()
            drawStatusBar("OK")
        end
        ::continue::
    end
end

-- Start prompt (clean and pocket-friendly)
term.clear()
term.setCursorPos(1,1)
print("Internet Browser")
if not HAS_MODEM then
    print("(No modem detected — offline mode)")
end
write("Enter domain (blank for offline/home): ")
local domain = read()
write("Enter page: ")
local page = read()

-- If blank domain/page, open local empty page (shows offline info)
openPage(domain, page)
