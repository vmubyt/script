--[[
╔══════════════════════════════════════════════════════════════════╗
║           ULTIMATE GAME SCANNER v3.0 - POTATO GAME              ║
║  Scans: ALL GUI, ALL buttons, ALL prices, ALL mechanics,         ║
║  ALL RemoteEvents, ALL values, ALL assets, canvas positions,     ║
║  background positions, frame hierarchies, EVERYTHING             ║
╚══════════════════════════════════════════════════════════════════╝

HOW TO USE:
  1. Paste & run in executor (Synapse X / Script-Ware / etc)
  2. Wait for "SCAN COMPLETE" message
  3. Copy ALL output from console
  4. The output contains every single element in the game

OUTPUT SECTIONS:
  [GUI]       - All visible/hidden GUI elements with positions
  [BTN]       - All clickable buttons with exact positions
  [PRICE]     - All text containing $, numbers, "each", "per"
  [REMOTE]    - All RemoteEvents and RemoteFunctions
  [VALUE]     - All NumberValue, StringValue, BoolValue etc
  [REPLICATED]- ReplicatedStorage contents
  [WORKSPACE] - Workspace parts and models
  [ASSET]     - ImageLabels with asset IDs
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)

-- ============================================================
--  CONFIG
-- ============================================================

local CONFIG = {
    maxDepth = 99,          -- how deep to scan GUI tree
    printDelay = 0,         -- delay between prints (0 = instant)
    includHidden = true,    -- scan hidden elements too
    includeWorkspace = true,-- scan workspace
    includeReplicated = true,-- scan ReplicatedStorage
    includeRemotes = true,  -- scan RemoteEvents
    includeValues = true,   -- scan Value objects
    includeAssets = true,   -- scan ImageLabel assetIds
}

-- ============================================================
--  OUTPUT BUFFER
-- ============================================================

local outputLines = {}
local function out(line)
    outputLines[#outputLines + 1] = line
    print(line)
end

local function section(title)
    out("")
    out("╔══════════════════════════════════════════════════════╗")
    out("║  " .. title)
    out("╚══════════════════════════════════════════════════════╝")
end

local function divider(label)
    out("── " .. label .. " " .. string.rep("─", math.max(0, 50 - #label)))
end

-- ============================================================
--  HELPERS
-- ============================================================

local function getAbsolutePos(obj)
    -- Get absolute screen position using AbsolutePosition
    local ok, pos = pcall(function()
        return obj.AbsolutePosition
    end)
    if ok and pos then
        return math.floor(pos.X) .. ", " .. math.floor(pos.Y)
    end
    return "N/A"
end

local function getAbsoluteSize(obj)
    local ok, sz = pcall(function()
        return obj.AbsoluteSize
    end)
    if ok and sz then
        return math.floor(sz.X) .. " x " .. math.floor(sz.Y)
    end
    return "N/A"
end

local function getUDim2(udim2)
    if not udim2 then return "N/A" end
    return string.format("(%.3f, %.0f, %.3f, %.0f)",
        udim2.X.Scale, udim2.X.Offset,
        udim2.Y.Scale, udim2.Y.Offset)
end

local function getText(obj)
    local ok, txt = pcall(function() return obj.Text end)
    if ok and txt and txt ~= "" then
        -- Trim and limit length
        txt = txt:gsub("\n", "\\n"):sub(1, 80)
        return txt
    end
    return nil
end

local function getImage(obj)
    local ok, img = pcall(function() return obj.Image end)
    if ok and img and img ~= "" then return img end
    return nil
end

local function isInteractable(obj)
    return obj:IsA("TextButton") or obj:IsA("ImageButton") or
           obj:IsA("TextBox") or obj:IsA("ScrollingFrame")
end

local function isValueObject(obj)
    return obj:IsA("NumberValue") or obj:IsA("StringValue") or
           obj:IsA("BoolValue") or obj:IsA("IntValue") or
           obj:IsA("Vector3Value") or obj:IsA("CFrameValue") or
           obj:IsA("ObjectValue") or obj:IsA("Color3Value")
end

local function looksLikePrice(text)
    if not text then return false end
    return text:match("%$") or
           text:match("each") or
           text:match("per") or
           text:match("price") or
           text:match("Price") or
           text:match("sell") or
           text:match("Sell") or
           text:match("value") or
           text:match("Value") or
           text:match("%d+%.%d+") or  -- decimal number
           text:match("%d+,") or       -- number with comma
           text:match("[Mm]arket") or
           text:match("[Tt]otal")
end

-- ============================================================
--  SECTION 1: FULL GUI TREE SCAN
-- ============================================================

section("1. FULL GUI HIERARCHY + POSITIONS")

local buttonList = {}   -- collect all buttons for section 2
local priceList = {}    -- collect all price labels for section 3
local assetList = {}    -- collect all image assets for section 7

local function scanGui(obj, depth, parentPath)
    if depth > CONFIG.maxDepth then return end

    local indent = string.rep("  ", depth)
    local path = parentPath and (parentPath .. "." .. obj.Name) or obj.Name

    -- Basic info
    local className = obj.ClassName
    local visible = ""
    local ok, vis = pcall(function() return obj.Visible end)
    if ok then
        visible = vis and "[V]" or "[H]"
    end

    local text = getText(obj)
    local image = getImage(obj)
    local absPos = getAbsolutePos(obj)
    local absSize = getAbsoluteSize(obj)

    -- Build info string
    local info = indent .. visible .. " [" .. className .. "] " .. obj.Name
    if text then info = info .. ' TEXT="' .. text .. '"' end
    if image then info = info .. ' IMG=' .. image end
    info = info .. " | POS:" .. absPos .. " SIZE:" .. absSize

    -- UDim2 positions (for scripting reference)
    local okPos, objPos = pcall(function() return obj.Position end)
    local okSize, objSize = pcall(function() return obj.Size end)
    if okPos and objPos then
        info = info .. " | UDim2_POS:" .. getUDim2(objPos)
    end
    if okSize and objSize then
        info = info .. " | UDim2_SIZE:" .. getUDim2(objSize)
    end

    -- Canvas position for ScrollingFrames
    if obj:IsA("ScrollingFrame") then
        local okCanvas, canvas = pcall(function() return obj.CanvasPosition end)
        if okCanvas then
            info = info .. " | CANVAS_POS:" .. math.floor(canvas.X) .. "," .. math.floor(canvas.Y)
        end
    end

    -- Background color
    local okBg, bg = pcall(function() return obj.BackgroundColor3 end)
    if okBg and bg then
        local okTrans, trans = pcall(function() return obj.BackgroundTransparency end)
        if okTrans and trans < 1 then
            info = info .. string.format(" | BG:rgb(%d,%d,%d)",
                math.floor(bg.R * 255), math.floor(bg.G * 255), math.floor(bg.B * 255))
        end
    end

    out(info)

    -- Collect buttons
    if isInteractable(obj) then
        buttonList[#buttonList + 1] = {
            name = obj.Name,
            class = className,
            text = text or "",
            absPos = absPos,
            absSize = absSize,
            path = path,
            visible = vis,
        }
    end

    -- Collect price-related labels
    if text and looksLikePrice(text) then
        priceList[#priceList + 1] = {
            name = obj.Name,
            text = text,
            absPos = absPos,
            path = path,
        }
    end

    -- Collect assets
    if image and image ~= "" then
        assetList[#assetList + 1] = {
            name = obj.Name,
            image = image,
            path = path,
            absPos = absPos,
        }
    end

    -- Recurse
    for _, child in ipairs(obj:GetChildren()) do
        if CONFIG.includHidden or child.Visible ~= false then
            scanGui(child, depth + 1, path)
        end
    end
end

-- Scan all GUIs
for _, gui in ipairs(playerGui:GetChildren()) do
    divider("GUI: " .. gui.Name)
    scanGui(gui, 0, "PlayerGui")
end

-- ============================================================
--  SECTION 2: ALL BUTTONS (SORTED BY VISIBILITY)
-- ============================================================

section("2. ALL INTERACTABLE BUTTONS & INPUTS")

-- Visible first
local visibleBtns = {}
local hiddenBtns = {}
for _, b in ipairs(buttonList) do
    if b.visible then
        visibleBtns[#visibleBtns + 1] = b
    else
        hiddenBtns[#hiddenBtns + 1] = b
    end
end

divider("VISIBLE BUTTONS (" .. #visibleBtns .. ")")
for _, b in ipairs(visibleBtns) do
    local txt = b.text ~= "" and ('TEXT="' .. b.text .. '" ') or ""
    out(string.format("  [%s] %s %s| ABS_POS:%s | ABS_SIZE:%s",
        b.class, b.name, txt, b.absPos, b.absSize))
    out("    PATH: " .. b.path)
end

divider("HIDDEN BUTTONS (" .. #hiddenBtns .. ")")
for _, b in ipairs(hiddenBtns) do
    local txt = b.text ~= "" and ('TEXT="' .. b.text .. '" ') or ""
    out(string.format("  [%s] %s %s| ABS_POS:%s | ABS_SIZE:%s",
        b.class, b.name, txt, b.absPos, b.absSize))
    out("    PATH: " .. b.path)
end

-- ============================================================
--  SECTION 3: PRICE & VALUE LABELS
-- ============================================================

section("3. PRICE / VALUE / MARKET LABELS")

out("Found " .. #priceList .. " price-related text elements:")
out("")
for _, p in ipairs(priceList) do
    out(string.format('  "%s" | NAME:%s | POS:%s', p.text, p.name, p.absPos))
    out("    PATH: " .. p.path)
end

-- ============================================================
--  SECTION 4: REMOTE EVENTS & FUNCTIONS
-- ============================================================

if CONFIG.includeRemotes then
    section("4. REMOTE EVENTS & FUNCTIONS")

    local function scanRemotes(parent, indent)
        indent = indent or ""
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("RemoteEvent") then
                out(indent .. "[RemoteEvent] " .. obj.Name .. " | PATH: " .. obj:GetFullName())
            elseif obj:IsA("RemoteFunction") then
                out(indent .. "[RemoteFunction] " .. obj.Name .. " | PATH: " .. obj:GetFullName())
            elseif obj:IsA("BindableEvent") then
                out(indent .. "[BindableEvent] " .. obj.Name .. " | PATH: " .. obj:GetFullName())
            elseif obj:IsA("BindableFunction") then
                out(indent .. "[BindableFunction] " .. obj.Name .. " | PATH: " .. obj:GetFullName())
            end
            -- Recurse into folders
            if #obj:GetChildren() > 0 then
                scanRemotes(obj, indent .. "  ")
            end
        end
    end

    divider("ReplicatedStorage Remotes")
    scanRemotes(ReplicatedStorage)

    divider("Workspace Remotes")
    scanRemotes(Workspace)

    -- Also check player scripts
    local function scanPlayerRemotes(parent)
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                out("[RemoteEvent/Func] " .. obj:GetFullName())
            end
            pcall(function()
                for _, child in ipairs(obj:GetChildren()) do
                    if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                        out("[RemoteEvent/Func] " .. child:GetFullName())
                    end
                end
            end)
        end
    end

    divider("Player Remotes")
    scanPlayerRemotes(player)
end

-- ============================================================
--  SECTION 5: VALUE OBJECTS (game state)
-- ============================================================

if CONFIG.includeValues then
    section("5. VALUE OBJECTS (Game State / Variables)")

    local function scanValues(parent, depth, maxD)
        if depth > (maxD or 6) then return end
        for _, obj in ipairs(parent:GetChildren()) do
            if isValueObject(obj) then
                local val = ""
                pcall(function() val = tostring(obj.Value) end)
                out(string.rep("  ", depth) .. "[" .. obj.ClassName .. "] " ..
                    obj.Name .. " = " .. val .. " | PATH: " .. obj:GetFullName())
            end
            scanValues(obj, depth + 1, maxD)
        end
    end

    divider("Player Values")
    scanValues(player, 0)

    divider("ReplicatedStorage Values")
    scanValues(ReplicatedStorage, 0, 4)

    divider("Workspace Values")
    scanValues(Workspace, 0, 3)
end

-- ============================================================
--  SECTION 6: REPLICATED STORAGE FULL TREE
-- ============================================================

if CONFIG.includeReplicated then
    section("6. REPLICATED STORAGE TREE")

    local function scanReplicated(obj, depth)
        if depth > 8 then return end
        local indent = string.rep("  ", depth)
        local extra = ""

        -- Show value if it's a value object
        if isValueObject(obj) then
            local val = ""
            pcall(function() val = " = " .. tostring(obj.Value) end)
            extra = val
        end

        out(indent .. "[" .. obj.ClassName .. "] " .. obj.Name .. extra)

        for _, child in ipairs(obj:GetChildren()) do
            scanReplicated(child, depth + 1)
        end
    end

    for _, child in ipairs(ReplicatedStorage:GetChildren()) do
        scanReplicated(child, 0)
    end
end

-- ============================================================
--  SECTION 7: IMAGE ASSETS
-- ============================================================

if CONFIG.includeAssets then
    section("7. IMAGE ASSETS (ImageLabel / ImageButton)")

    out("Found " .. #assetList .. " image assets:")
    out("")
    for _, a in ipairs(assetList) do
        out(string.format("  NAME:%-30s IMG:%s", a.name, a.image))
        out("    POS:" .. a.absPos .. " | PATH: " .. a.path)
    end
end

-- ============================================================
--  SECTION 8: WORKSPACE SCAN (parts, models, etc)
-- ============================================================

if CONFIG.includeWorkspace then
    section("8. WORKSPACE MODELS & PARTS")

    local function scanWorkspace(obj, depth)
        if depth > 5 then return end
        local indent = string.rep("  ", depth)

        local info = indent .. "[" .. obj.ClassName .. "] " .. obj.Name

        -- Position for BasePart
        if obj:IsA("BasePart") then
            local pos = obj.Position
            local sz = obj.Size
            info = info .. string.format(" | POS:(%.1f,%.1f,%.1f) SIZE:(%.1f,%.1f,%.1f)",
                pos.X, pos.Y, pos.Z, sz.X, sz.Y, sz.Z)
        end

        -- SurfaceGui / BillboardGui
        if obj:IsA("SurfaceGui") or obj:IsA("BillboardGui") then
            info = info .. " [3D GUI]"
        end

        out(info)

        for _, child in ipairs(obj:GetChildren()) do
            scanWorkspace(child, depth + 1)
        end
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        scanWorkspace(child, 0)
    end
end

-- ============================================================
--  SECTION 9: LOCALSCRIPT & MODULE DETECTION
-- ============================================================

section("9. SCRIPTS DETECTED (LocalScripts / Modules)")

local function findScripts(parent, depth)
    if depth > 5 then return end
    for _, obj in ipairs(parent:GetChildren()) do
        if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
            local enabled = ""
            pcall(function()
                enabled = obj.Disabled and " [DISABLED]" or " [ACTIVE]"
            end)
            out("[" .. obj.ClassName .. "]" .. enabled .. " " .. obj:GetFullName())
        end
        findScripts(obj, depth + 1)
    end
end

findScripts(Players.LocalPlayer, 0)
findScripts(playerGui, 0)
findScripts(ReplicatedStorage, 0)

-- ============================================================
--  SECTION 10: MARKET PRICE DEEP SCAN (Sell Potatoes Tab)
-- ============================================================

section("10. MARKET PRICE DEEP SCAN")

-- Specifically scan the Sell Potatoes content area for market prices
local mainGui = playerGui:FindFirstChild("PotatoGameGUI")
if mainGui then
    out("Scanning PotatoGameGUI for ALL price/market related elements...")
    out("")

    local function deepScanForPrices(obj, depth)
        if depth > 15 then return end

        local text = getText(obj)
        local name = obj.Name:lower()

        -- Capture everything that might be price-related
        local isPriceRelated = (text and looksLikePrice(text)) or
            name:match("price") or name:match("market") or
            name:match("sell") or name:match("value") or
            name:match("count") or name:match("amount") or
            name:match("total") or name:match("cash") or
            name:match("golden") or name:match("potato") or
            name:match("per") or name:match("rate") or
            name:match("earn") or name:match("coin") or
            name:match("gold")

        if isPriceRelated then
            local absPos = getAbsolutePos(obj)
            local visStr = ""
            local ok, vis = pcall(function() return obj.Visible end)
            if ok then visStr = vis and "[VISIBLE]" or "[HIDDEN]" end

            out(string.format("  %s [%s] NAME:%-35s POS:%-15s TEXT:%s",
                visStr, obj.ClassName, obj.Name, absPos, text or "(no text)"))
            out("    FULL_PATH: " .. obj:GetFullName())
        end

        for _, child in ipairs(obj:GetChildren()) do
            deepScanForPrices(child, depth + 1)
        end
    end

    deepScanForPrices(mainGui, 0)
else
    out("PotatoGameGUI not found!")
end

-- ============================================================
--  SECTION 11: SELL TAB SPECIFIC SCAN
-- ============================================================

section("11. SELL POTATOES TAB - COMPLETE STRUCTURE")

if mainGui then
    -- Try to find the sell potatoes content area
    local function findSellArea(obj, depth)
        if depth > 10 then return end
        local nameLower = obj.Name:lower()
        if nameLower:match("sell") or nameLower:match("market") or
           nameLower:match("content") then
            out("FOUND AREA: " .. obj:GetFullName())
            out("  CLASS: " .. obj.ClassName)
            local okV, v = pcall(function() return obj.Visible end)
            if okV then out("  VISIBLE: " .. tostring(v)) end
            out("  ABS_POS: " .. getAbsolutePos(obj))
            out("  ABS_SIZE: " .. getAbsoluteSize(obj))
            out("")
            out("  CHILDREN:")

            -- Print all children of this area
            local function printChildren(o, d)
                if d > 8 then return end
                local ind = string.rep("    ", d)
                local txt = getText(o)
                local img = getImage(o)
                local absPos = getAbsolutePos(o)

                local line = ind .. "[" .. o.ClassName .. "] " .. o.Name
                if txt then line = line .. ' = "' .. txt .. '"' end
                if img then line = line .. " IMG=" .. img end
                line = line .. " | POS:" .. absPos

                out(line)
                for _, c in ipairs(o:GetChildren()) do
                    printChildren(c, d + 1)
                end
            end

            for _, child in ipairs(obj:GetChildren()) do
                printChildren(child, 1)
            end
            out("")
        end
        for _, child in ipairs(obj:GetChildren()) do
            findSellArea(child, depth + 1)
        end
    end

    findSellArea(mainGui, 0)
end

-- ============================================================
--  SECTION 12: SUMMARY
-- ============================================================

section("12. SCAN SUMMARY")

out(string.format("  Total output lines  : %d", #outputLines))
out(string.format("  Buttons found       : %d (%d visible, %d hidden)",
    #buttonList,
    (function() local c=0; for _,b in ipairs(buttonList) do if b.visible then c=c+1 end end; return c end)(),
    (function() local c=0; for _,b in ipairs(buttonList) do if not b.visible then c=c+1 end end; return c end)()
))
out(string.format("  Price labels found  : %d", #priceList))
out(string.format("  Image assets found  : %d", #assetList))
out("")
out("  ✅ SCAN COMPLETE!")
out("  📋 Copy all console output above to share/analyze")
out("")

-- ============================================================
--  OPTIONAL: SAVE TO CLIPBOARD (if supported by executor)
-- ============================================================

local fullOutput = table.concat(outputLines, "\n")

-- Try setclipboard (Synapse X / Script-Ware support this)
local clipOk = pcall(function()
    setclipboard(fullOutput)
end)

if clipOk then
    out("📋 Full output COPIED TO CLIPBOARD automatically!")
else
    out("ℹ️  setclipboard not available - manually copy console output")
end

-- Also store in _G for access
_G.ScanOutput = fullOutput
_G.ScanButtons = buttonList
_G.ScanPrices = priceList

out("")
out("💾 Data also stored in:")
out("   _G.ScanOutput  = full text output")
out("   _G.ScanButtons = button list table")
out("   _G.ScanPrices  = price label table")
out("")
out("🔍 To filter prices only, run: for _,p in ipairs(_G.ScanPrices) do print(p.text, p.path) end")
out("🔍 To filter buttons only, run: for _,b in ipairs(_G.ScanButtons) do print(b.name, b.absPos, b.path) end")
