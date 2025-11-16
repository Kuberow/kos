-- MITP Pocket Client (TouchUI, MCML, Back/Forward)
local hasModem, MODEM = pcall(peripheral.find, "modem")
if not hasModem then
    MODEM = { open = function() end, transmit = function() end } -- dummy
end

local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")

-- History support
local history, histIndex = {}, 0

-- Token generator
local TOKEN_COUNTER = 0
local function getToken()
    TOKEN_COUNTER = TOKEN_COUNTER + 1
    return math.random(1000,9999) + TOKEN_COUNTER
end

-- DNS resolution
local DNS_CHANNEL = 312
local function getPCID(domain)
    local token = getToken()
    MODEM.transmit(DNS_CHANNEL, DNS_CHANNEL, {
        ACTION="GET_ADDR", ADDR=domain, TOKEN=token, DEST="DNS"
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
local function getPage(serverPCID,page)
    local token = getToken()
    MODEM.transmit(DNS_CHANNEL, 312, {
        ACTION="GET_WEB", ADDR=serverPCID, PAGE=page, DEST="SERVER",
        TOKEN=token, CPID=os.getComputerID()
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

-- Parse MCML
local function parseMCML(content)
    local elements = {}
    local styles = {}
    local head = content:match("<head>(.-)</head>") or ""
    for forid, defs in head:gmatch('<style%s+for="(.-)">(.-)</style>') do
        local styleTable = {}
        for k,v in defs:gmatch("(%w+)%s*:%s*(%w+)") do styleTable[k]=v end
        styles[forid] = styleTable
    end
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
                    local plain = line:sub(pos,s-1)
                    if #plain>0 then table.insert(elements,{type="text",text=plain,style=bodyStyle}) end
                end
                if tag=="text" then
                    local full = line:sub(s)
                    local id = full:match('<text%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<text.-x="(.-)"'))
                    local y = tonumber(full:match('<text.-y="(.-)"'))
                    local text = full:match('<text.->(.-)</text>') or ""
                    local style = (id~="" and styles[id]) or bodyStyle
                    table.insert(elements,{type="text",text=text,style=style,x=x,y=y})
                    pos = (line:find("</text>", s) or e+1)
                elseif tag=="button" then
                    local full = line:sub(s)
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    local id = full:match('id="(.-)"') or ""
                    local x = tonumber(full:match('<button.-x="(.-)"'))
                    local y = tonumber(full:match('<button.-y="(.-)"'))
                    local label = full:match('<button.->(.-)</button>') or ""
                    local style = {textColor="white",bgColor="blue"}
                    table.insert(elements,{type="button",text=label,web=web,page=page,style=style,x=x,y=y})
                    pos = (line:find("</button>", s) or e+1)
                elseif tag=="rect" then
                    local full = line:sub(s)
                    local x = tonumber(full:match('<rect.-x="(.-)"'))
                    local y = tonumber(full:match('<rect.-y="(.-)"'))
                    local width = tonumber(full:match('<rect.-width="(.-)"')) or 1
                    local height = tonumber(full:match('<rect.-height="(.-)"')) or 1
                    table.insert(elements,{type="rect",x=x,y=y,width=width,height=height})
                    pos = (line:find("/>", s) or line:find("</rect>", s) or e+1)
                elseif tag=="textbox" then
                    local full = line:sub(s)
                    local id = full:match('<textbox%s+id="(.-)"') or ""
                    local x = tonumber(full:match('<textbox.-x="(.-)"'))
                    local y = tonumber(full:match('<textbox.-y="(.-)"'))
                    local width = tonumber(full:match('<textbox.-width="(.-)"')) or 10
                    local web = full:match('web="(.-)"') or ""
                    local page = full:match('page="(.-)"') or ""
                    table.insert(elements,{type="textbox",id=id,width=width,web=web,page=page,x=x,y=y,content=""})
                    pos = (line:find("/>", s) or line:find("</textbox>", s) or e+1)
                else
                    pos = e+1
                end
            else
                local remaining = line:sub(pos)
                if #remaining>0 then table.insert(elements,{type="text",text=remaining,style=bodyStyle}) end
                break
            end
        end
        table.insert(elements,{type="newline"})
    end
    return elements, bodyStyle
end

-- Render MCML into TouchUI
local function renderMCML(elements)
    local out = ""
    for _,el in ipairs(elements) do
        if el.type=="text" then
            out = out .. el.text
        elseif el.type=="newline" then
            out = out .. "\n"
        elseif el.type=="button" then
            out = out .. "["..el.text.."] "
        elseif el.type=="rect" then
            out = out .. string.rep(" ",el.width or 1)
        elseif el.type=="textbox" then
            out = out .. string.rep("_",el.width or 10)
        end
    end
    return out
end

-- Main UI
local termW, termH = term.getSize()
local rootWin = window.create(term.current(),1,1,termW,termH)
local root = container.vBox()
root:setWindow(rootWin)

local domainInput, pageInput, viewer

domainInput = input.inputWidget("Domain","",function() end)
pageInput = input.inputWidget("Page","",function() end)
viewer = input.textWidget("Ready.\nEnter domain and page then Load.")

root:addWidget(domainInput)
root:addWidget(pageInput)
root:addWidget(input.buttonWidget("Load",function()
    local domain = domainInput:getValue()
    local page = pageInput:getValue()
    if not domain or domain=="" then return end

    -- Add to history
    histIndex = histIndex + 1
    history[histIndex] = {domain=domain,page=page}

    -- Fetch page safely
    local pcid, ok = getPCID(domain)
    if not ok or not pcid then
        viewer:setValue("Domain not found!")
        return
    end
    local content = getPage(pcid,page)
    if not content then
        viewer:setValue("Failed to fetch page!")
        return
    end
    local elements, style = parseMCML(content)
    local out = renderMCML(elements)
    viewer:setValue(out)
end))
root:addWidget(viewer)

-- Back / Forward buttons
root:addWidget(input.buttonWidget("Back",function()
    if histIndex>1 then
        histIndex = histIndex - 1
        local h = history[histIndex]
        domainInput:setValue(h.domain)
        pageInput:setValue(h.page)
        viewer:setValue("Press Load to view page.")
    end
end))
root:addWidget(input.buttonWidget("Forward",function()
    if histIndex<#history then
        histIndex = histIndex + 1
        local h = history[histIndex]
        domainInput:setValue(h.domain)
        pageInput:setValue(h.page)
        viewer:setValue("Press Load to view page.")
    end
end))

-- Run TouchUI
tui.run(root)
