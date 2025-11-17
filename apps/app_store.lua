local tui = require("touchui")
local container = require("touchui.containers")
local input = require("touchui.input")

-- Create main window
local mainWin = window.create(term.current(), 1, 1, term.getSize())

-- App store data structure (empty by default)
local apps = {}
local appsLoaded = false

-- Function to fetch apps list from GitHub
local function fetchAppsList()
    if appsLoaded then return end
    
    remos.notification("*", "Loading apps...")
    local response = http.get("https://raw.githubusercontent.com/Kuberow/kos_apps/main/apps.json")
    
    if response then
        local content = response.readAll()
        response.close()
        
        local success, decoded = pcall(textutils.unserializeJSON, content)
        if success and decoded then
            apps = decoded
            appsLoaded = true
            remos.notification("+", "Apps loaded!")
        else
            remos.notification("!", "Failed to parse apps list")
        end
    else
        remos.notification("!", "Failed to fetch apps list")
    end
end

-- Function to download and run script from URL
local function downloadAndRun(url)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()
        
        -- Save to temporary file
        local tempFile = "/tmp/downloaded_app.lua"
        local file = fs.open(tempFile, "w")
        file.write(content)
        file.close()
        
        -- Run the script
        local success, err = pcall(function()
            shell.run(tempFile)
        end)
        
        if not success then
            remos.notification("!", "Error running app: " .. tostring(err))
        end
    else
        remos.notification("!", "Failed to download app")
    end
end

-- Function to show app details and download
local function showAppDetails(app)
    local detailWin = window.create(term.current(), 1, 1, term.getSize())
    local detailVBox = container.vBox()
    detailVBox:setWindow(detailWin)
    
    detailVBox:addWidget(tui.textWidget(app.name, "c"))
    detailVBox:addWidget(tui.textWidget("by " .. app.author, "c"))
    detailVBox:addWidget(tui.textWidget(app.description, "l"), 3)
    detailVBox:addWidget(tui.textWidget("URL: " .. app.url, "l"), 2)
    
    detailVBox:addWidget(input.buttonWidget("Download & Run", function(self)
        remos.notification("*", "Downloading " .. app.name .. "...")
        downloadAndRun(app.url)
    end), 3)
    
    detailVBox:addWidget(input.buttonWidget("Back", function(self)
        showMainMenu()
    end), 3)
    
    tui.run(detailVBox)
end

-- Main menu
function showMainMenu()
    -- Fetch apps on first load
    if not appsLoaded then
        fetchAppsList()
    end

    -- Sort apps alphabetically by name (case-insensitive)
    if #apps > 1 then
        table.sort(apps, function(a, b)
            return string.lower(a.name) < string.lower(b.name)
        end)
    end

    local rootVBox = container.vBox()
    rootVBox:setWindow(mainWin)
    
    rootVBox:addWidget(tui.textWidget("App Store", "c"))
    rootVBox:addWidget(tui.textWidget("Browse and install apps", "c"))
    
    -- Show apps or empty message
    if #apps == 0 then
        rootVBox:addWidget(tui.textWidget("No apps available", "c"), 3)
    else
        -- Add app list
        for i, app in ipairs(apps) do
            rootVBox:addWidget(input.buttonWidget(app.name .. " - " .. app.author, function(self)
                showAppDetails(app)
            end), 3)
        end
    end

    rootVBox:addWidget(input.buttonWidget("Refresh Apps", function(self)
        appsLoaded = false
        showMainMenu()
    end), 3)

    tui.run(rootVBox)
end

-- Start the app
remos.notification("*", "Welcome to App Store!")
showMainMenu()
