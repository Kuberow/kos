-- MITP Website Client - Enhanced UI with Pocket Computer Support
local MODEM = peripheral.find("modem") or error("No modem found!")
MODEM.open(312)

local DNS_CHANNEL = 312
local TOKEN_COUNTER = 0
local colors_table = {
    black=colors.black, white=colors.white, red=colors.red,
    green=colors.green, blue=colors.blue, yellow=colors.yellow,
    cyan=colors.cyan, magenta=colors.magenta, gray=colors.gray,
    lightGray=colors.lightGray, orange=colors.orange, lime=colors.lime,
    pink=colors.pink, purple=colors.purple, brown=colors.brown
}

-- Detect if running on pocket computer
local isPocket = pocket

-- Scrolling variables
local scrollY = 0
local maxScrollY = 0
local contentHeight = 0
local currentDomain = "blank"
local currentPage = "home"

local function getToken()
    TOKEN_COUNTER = TOKEN_COUNTER + 1
    return math.random(1000,9999) + TOKEN_COUNTER
end

-- Default blank page content - responsive version
local function getBlankPage()
    if isPocket then
        -- Compact version for pocket computers
        return [[
<head>
    <style for="title">textColor:cyan bgColor:black</style>
    <style for="subtitle">textColor:lightGray bgColor:black</style>
    <style for="infotext">textColor:white bgColor:black</style>
    <style for="box">bgColor:gray</style>
    <style for="navbtn">textColor:white bgColor:blue</style>
</head>
<body id="body">
<text id="title" x="1" y="3"></text><newLine>
<text id="title" x="1" y="4">   MITP Browser 2.0   </text><newLine>
<text id="title" x="1" y="5"></text><newLine>
<newLine>
<text id="subtitle" x="1" y="7">Pocket Edition</text><newLine>
<newLine>
<text id="infotext" x="1" y="9">Navigation:</text><newLine>
<text id="infotext" x="1" y="10">• UP/DOWN: Scroll</text><newLine>
<text id="infotext" x="1" y="11">• Touch: Tap items</text><newLine>
<text id="infotext" x="1" y="12">• Menu: Navigate</text><newLine>
<newLine>
<rect id="box" x="1" y="14" width="24" height="1"/><newLine>
<newLine>
<text id="infotext" x="1" y="16">Enter domain/page:</text><newLine>
<textbox id="nav" x="1" y="17" width="22" web="nav" page="go"/>
</body>
]]
    else
        -- Full version for computers
        return [[
<head>
    <style for="title">textColor:cyan bgColor:black</style>
    <style for="subtitle">textColor:lightGray bgColor:black</style>
    <style for="infotext">textColor:white bgColor:black</style>
    <style for="box">bgColor:gray</style>
    <style for="navbutton">textColor:white bgColor:blue</style>
</head>
<body id="body">
<text id="title" x="2" y="3"></text><newLine>
<text id="title" x="2" y="4">          MITP Web Browser v2.0                 </text><newLine>
<text id="title" x="2" y="5"></text><newLine>
<newLine>
<text id="subtitle" x="2" y="7">Welcome to the MITP Protocol Browser!</text><newLine>
<newLine>
<text id="infotext" x="2" y="9">Navigation Instructions:</text><newLine>
<text id="infotext" x="4" y="10">• Press F5 to enter a new domain and page</text><newLine>
<text id="infotext" x="4" y="11">• Use UP/DOWN arrows to scroll</text><newLine>
<text id="infotext" x="4" y="12">• Use PAGE UP/PAGE DOWN for faster scrolling</text><newLine>
<text id="infotext" x="4" y="13">• Press HOME/END to jump to top/bottom</text><newLine>
<text id="infotext" x="4" y="14">• Click Refresh to reload current page</text><newLine>
<text id="infotext" x="4" y="15">• Mouse wheel to scroll smoothly</text><newLine>
<newLine>
<rect id="box" x="2" y="17" width="47" height="1"/><newLine>
<newLine>
<text id="infotext" x="2" y="19">Quick Start:</text><newLine>
<text id="infotext" x="4" y="20">Press F5 now to navigate to your first page!</text><newLine>
</body>
]]
    end
end

-- DNS resolution: returns server PCID
local function getPCID(domain)
    if domain == "blank" then
        return "blank", true
    end
    
    local token = getToken()
    MODEM.transmit(DNS_CHANNEL, DNS_CHANNEL, {
        ACTION="GET_ADDR",
        ADDR=domain,
        TOKEN=token,
        DEST="DNS"
    })
    local timer = os.startTimer(5)
    while true do
        local e = {os.pullEvent()}
        if e[1]=="modem_message" and type(e[5])=="table" and e[5].TOKEN==token and e[5].DEST=="CLIENT" then
            return e[5].ADDR, e[5].SUCCESS
        elseif e[1]=="timer" and e[2]==timer then
            return nil,false
        end
    end
end

-- Get page from server
local function getPage(serverPCID, page)
    if serverPCID == "blank" then
        return getBlankPage()
    end
    
    local token = getToken()
    MODEM.transmit(DNS_CHANNEL, 312, {
        ACTION="GET_WEB",
        ADDR=serverPCID,
        PAGE=page,
        DEST="SERVER",
        TOKEN=token,
        CPID=os.getComputerID()
    })
    local timer = os.startTimer(5)
    while true do
        local e = {os.pullEvent()}
        if e[1]=="modem_message" and type(e[5])=="table" and e[5].TOKEN==token and e[5].DEST=="CLIENT" then
            return e[5].PAGE
        elseif e[1]=="timer" and e[2]==timer then
            return nil
        end
    end
end

-- Parse MCML into ordered table of elements
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
    local maxY = 2
    local currentY = 2
    
    for _, el in ipairs(elements) do
        if el.type == "newline" then
            currentY = currentY + 1
            if currentY > maxY then maxY = currentY end
        elseif el.type == "text" then
            if el.y and el.y > currentY then
                currentY = el.y
            end
            if currentY > maxY then maxY = currentY end
        elseif el.type == "button" then
            if el.y and el.y > currentY then
                currentY = el.y
            end
            if currentY > maxY then maxY = currentY end
        elseif el.type == "rect" then
            if el.y and el.y > currentY then
                currentY = el.y
            end
            currentY = currentY + (el.height or 1) - 1
            if currentY > maxY then maxY = currentY end
        elseif el.type == "textbox" then
            if el.y and el.y > currentY then
                currentY = el.y
            end
            currentY = currentY + 2
            if currentY > maxY then maxY = currentY end
        end
    end
    
    return maxY
end

-- Render the MCML table with scrolling
local function renderMCML(elements, bodyStyle)
    local bg = colors_table[bodyStyle.bgColor] or colors.black
    local fg = colors_table[bodyStyle.textColor] or colors.white
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    
    local screenWidth, screenHeight = term.getSize()
    for i=2,screenHeight do
        term.setCursorPos(1,i)
        term.clearLine()
    end

    local x,y = 1,2
    local buttons = {}
    local textboxes = {}

    for _, el in ipairs(elements) do
        if el.type=="newline" then
            y=y+1
            x=1
        elseif el.type=="text" then
            if el.x and el.y then
                x, y = el.x, el.y
            end
            
            local renderY = y - scrollY
            if renderY >= 2 and renderY <= screenHeight then
                local fg = colors_table[el.style.textColor] or colors_table[bodyStyle.textColor] or colors.white
                local bg = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or colors.black
                term.setTextColor(fg)
                term.setBackgroundColor(bg)
                term.setCursorPos(x,renderY)
                term.write(el.text)
            end
            x=x+#el.text
            
        elseif el.type=="button" then
            if el.x and el.y then
                x, y = el.x, el.y
            end
            
            local renderY = y - scrollY
            if renderY >= 2 and renderY <= screenHeight then
                local fg = colors_table[el.style.textColor] or colors.white
                local bg = colors_table[el.style.bgColor] or colors.blue
                term.setTextColor(fg)
                term.setBackgroundColor(bg)
                term.setCursorPos(x,renderY)
                term.write(" "..el.text.." ")
                table.insert(buttons,{x=x,y=renderY,w=#el.text+2,web=el.web,page=el.page,originalY=y})
            end
            x=x+#el.text+2
            
        elseif el.type=="rect" then
            if el.x and el.y then
                x, y = el.x, el.y
            end
            
            local bg = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or colors.black
            term.setBackgroundColor(bg)
            
            for row = 0, (el.height or 1)-1 do
                local renderY = y + row - scrollY
                if renderY >= 2 and renderY <= screenHeight then
                    term.setCursorPos(x, renderY)
                    term.write(string.rep(" ", el.width or 1))
                end
            end
            
            x = x + (el.width or 1)
            
        elseif el.type=="textbox" then
            if el.x and el.y then
                x, y = el.x, el.y
            end
            
            local fg = colors_table[el.style.textColor] or colors_table[bodyStyle.textColor] or colors.white
            local bg = colors_table[el.style.bgColor] or colors_table[bodyStyle.bgColor] or colors.black
            local borderColor = colors_table[el.style.borderColor] or colors.white
            
            for row = 0, 2 do
                local renderY = y + row - scrollY
                if renderY >= 2 and renderY <= screenHeight then
                    term.setBackgroundColor(borderColor)
                    term.setTextColor(borderColor)
                    term.setCursorPos(x, renderY)
                    
                    if row == 0 then
                        term.write("+" .. string.rep("-", el.width) .. "+")
                    elseif row == 1 then
                        term.write("|")
                        term.setBackgroundColor(bg)
                        term.setTextColor(fg)
                        term.write(string.rep(" ", el.width))
                        term.setBackgroundColor(borderColor)
                        term.setTextColor(borderColor)
                        term.write("|")
                    elseif row == 2 then
                        term.write("+" .. string.rep("-", el.width) .. "+")
                    end
                end
            end
            
            local contentY = y + 1 - scrollY
            if contentY >= 2 and contentY <= screenHeight then
                if el.content and #el.content > 0 then
                    term.setBackgroundColor(bg)
                    term.setTextColor(fg)
                    term.setCursorPos(x+1, contentY)
                    if #el.content > el.width then
                        term.write(el.content:sub(1, el.width))
                    else
                        term.write(el.content)
                    end
                end
            end
            
            table.insert(textboxes, {
                x=x+1, y=y+1, width=el.width, height=1,
                id=el.id, web=el.web, page=el.page,
                content=el.content or "",
                bg=bg, fg=fg, borderColor=borderColor,
                originalY=y+1
            })
            
            x = x + el.width + 2
        end
    end

    -- Draw modern scrollbar (only for computers, pocket has limited space)
    if maxScrollY > 0 and not isPocket then
        local scrollbarX = screenWidth
        local availableHeight = screenHeight - 1
        local scrollbarHeight = math.max(1, math.floor(availableHeight * (availableHeight / contentHeight)))
        local scrollbarPos = 2 + math.floor((scrollY / maxScrollY) * (availableHeight - scrollbarHeight))
        
        for yPos = 2, screenHeight do
            term.setCursorPos(scrollbarX, yPos)
            if yPos >= scrollbarPos and yPos < scrollbarPos + scrollbarHeight then
                term.setBackgroundColor(colors.cyan)
                term.setTextColor(colors.cyan)
                term.write(" ")
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.gray)
                term.write(" ")
            end
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    return buttons, textboxes
end

-- Handle textbox input
local function handleTextboxInput(textbox)
    local content = textbox.content
    local cursorPos = #content + 1
    
    local screenY = textbox.originalY - scrollY
    if screenY < 2 or screenY > term.getSize() then
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

-- Draw enhanced URL bar - responsive
local function drawURLBar(domain,page)
    local w,h = term.getSize()
    
    -- Main URL bar
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1,1)
    term.clearLine()
    
    if isPocket then
        -- Compact URL for pocket with menu button
        local urlText = " " .. domain:sub(1,6)
        if #domain > 6 then urlText = urlText .. ".." end
        urlText = urlText .. "/" .. page:sub(1,4)
        if #page > 4 then urlText = urlText .. ".." end
        term.write(urlText)
        
        -- Menu button for navigation
        term.setCursorPos(w-5,1)
        term.setBackgroundColor(colors.orange)
        term.setTextColor(colors.white)
        term.write(" Menu ")
    else
        -- Full URL for computers
        local urlText = " " .. domain .. "/" .. page
        if #urlText > w - 11 then
            urlText = " " .. string.sub(urlText, 1, w - 14) .. "..."
        end
        term.write(urlText)
        
        -- Refresh button
        term.setCursorPos(w-9,1)
        term.setBackgroundColor(colors.lime)
        term.setTextColor(colors.black)
        term.write(" \16 Refresh")
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Show loading message
local function showLoading(message)
    local w,h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(isPocket and 1 or 2, 3)
    term.write(message)
end

-- Handle scrolling
local function handleScrolling(direction)
    local newScrollY = scrollY + direction
    if newScrollY >= 0 and newScrollY <= maxScrollY then
        scrollY = newScrollY
        return true
    end
    return false
end

-- Navigation prompt - responsive
local function promptNavigation()
    term.setCursorPos(1,2)
    term.setBackgroundColor(colors.black)
    term.clearLine()
    term.setTextColor(colors.cyan)
    write(isPocket and "Domain: " or "Domain: ")
    term.setTextColor(colors.white)
    local newDomain = read()
    term.setTextColor(colors.cyan)
    write(isPocket and "Page: " or "Page: ")
    term.setTextColor(colors.white)
    local newPage = read()
    return newDomain, newPage
end

-- Main UI loop
local function openPage(domain,page)
    scrollY = 0
    maxScrollY = 0
    currentDomain = domain
    currentPage = page
    
    -- Handle special navigation page for pocket
    if domain == "nav" and page == "go" and isPocket then
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(1,1)
        term.clearLine()
        term.write(" Navigation")
        
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.cyan)
        term.setCursorPos(1,3)
        write("Domain: ")
        term.setTextColor(colors.white)
        local newDomain = read()
        term.setTextColor(colors.cyan)
        term.setCursorPos(1,5)
        write("Page: ")
        term.setTextColor(colors.white)
        local newPage = read()
        
        if newDomain and newDomain ~= "" and newPage and newPage ~= "" then
            openPage(newDomain, newPage)
        else
            openPage("blank", "home")
        end
        return
    end
    
    term.setBackgroundColor(colors.black)
    term.clear()
    drawURLBar(domain,page)
    showLoading("Loading...")
    
    local pcid, ok = getPCID(domain)
    if not ok or not pcid then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.setCursorPos(isPocket and 1 or 2,3)
        print("Error: Domain not found!")
        term.setTextColor(colors.lightGray)
        term.setCursorPos(isPocket and 1 or 2,4)
        if isPocket then
            print("Tap Menu to try again")
        else
            print("Press F5 to try another domain")
        end
        while true do
            local e = {os.pullEvent()}
            if isPocket and e[1] == "mouse_click" then
                local w = term.getSize()
                if e[4] == 1 and e[3] >= w-5 then
                    openPage("nav", "go")
                    return
                end
            elseif not isPocket and e[1] == "key" and e[2] == keys.f5 then
                local newDomain, newPage = promptNavigation()
                openPage(newDomain,newPage)
                return
            end
        end
    end

    local content = getPage(pcid,page)
    if not content then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.setCursorPos(isPocket and 1 or 2,3)
        print("Error: Failed to fetch page!")
        term.setTextColor(colors.lightGray)
        term.setCursorPos(isPocket and 1 or 2,4)
        if isPocket then
            print("Tap Menu to try again")
        else
            print("Press F5 to try again")
        end
        while true do
            local e = {os.pullEvent()}
            if isPocket and e[1] == "mouse_click" then
                local w = term.getSize()
                if e[4] == 1 and e[3] >= w-5 then
                    openPage(domain, page)
                    return
                end
            elseif not isPocket and e[1] == "key" and e[2] == keys.f5 then
                openPage(domain,page)
                return
            end
        end
    end

    local elements, styles, bodyID, bodyStyle = parseMCML(content)
    
    contentHeight = calculateContentHeight(elements)
    local _, screenHeight = term.getSize()
    maxScrollY = math.max(0, contentHeight - screenHeight + 1)
    
    local buttons, textboxes = renderMCML(elements, bodyStyle)
    drawURLBar(domain,page)

    while true do
        local e = {os.pullEvent()}
        if e[1]=="mouse_click" then
            local cx, cy = e[3], e[4]
            local w,h = term.getSize()
            
            -- Check refresh button click
            if not isPocket then
                if cy==1 and cx>=w-9 and cx<=w then
                    openPage(domain,page)
                    return
                end
            else
                -- Pocket: tap Menu button to navigate
                if cy==1 and cx>=w-5 and cx<=w then
                    openPage("nav", "go")
                    return
                end
            end
            
            for _,btn in ipairs(buttons) do
                if cy==btn.y and cx>=btn.x and cx<=btn.x+btn.w-1 then
                    openPage(btn.web,btn.page)
                    return
                end
            end
            
            for _,textbox in ipairs(textboxes) do
                local screenY = textbox.originalY - scrollY
                if cy == screenY and cx >= textbox.x and cx <= textbox.x + textbox.width - 1 then
                    local newContent, shouldNavigate = handleTextboxInput(textbox)
                    textbox.content = newContent
                    
                    term.setBackgroundColor(textbox.bg)
                    term.setTextColor(textbox.fg)
                    term.setCursorPos(textbox.x, screenY)
                    term.write(string.rep(" ", textbox.width))
                    term.setCursorPos(textbox.x, screenY)
                    if #newContent > textbox.width then
                        term.write(newContent:sub(1, textbox.width))
                    else
                        term.write(newContent)
                    end
                    
                    if shouldNavigate and textbox.web and textbox.page then
                        openPage(textbox.web, textbox.page .. "?" .. newContent)
                        return
                    end
                    
                    break
                end
            end
            
        elseif e[1]=="key" then
            local key = e[2]
            if key == keys.up then
                if handleScrolling(-1) then
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys.down then
                if handleScrolling(1) then
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys.pageUp and not isPocket then
                local _, screenHeight = term.getSize()
                if handleScrolling(-(screenHeight - 3)) then
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys.pageDown and not isPocket then
                local _, screenHeight = term.getSize()
                if handleScrolling(screenHeight - 3) then
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys.home and not isPocket then
                if scrollY ~= 0 then
                    scrollY = 0
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys["end"] and not isPocket then
                if scrollY ~= maxScrollY then
                    scrollY = maxScrollY
                    buttons, textboxes = renderMCML(elements, bodyStyle)
                    drawURLBar(domain,page)
                end
            elseif key == keys.f5 and not isPocket then
                local newDomain, newPage = promptNavigation()
                openPage(newDomain,newPage)
                return
            end
        elseif e[1]=="mouse_scroll" and not isPocket then
            -- Mouse wheel scrolling (computers only)
            local direction = e[2]
            if handleScrolling(direction) then
                buttons, textboxes = renderMCML(elements, bodyStyle)
                drawURLBar(domain,page)
            end
        end
    end
end

-- Start with blank page
term.clear()
term.setBackgroundColor(colors.black)
term.setTextColor(colors.cyan)
openPage("blank", "home")
