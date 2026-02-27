--[[
╔══════════════════════════════════════════════════════════════════╗
║          AUTO SELL POTATO GAME - FINAL v4.0                      ║
║  Built from actual game scan data                                ║
║                                                                  ║
║  DISCOVERY: Game has NATIVE RemoteEvents for selling!            ║
║   • SellAllPotatoes        → sell semua normal potato            ║
║   • SellAllGoldenPotatoes  → sell semua golden potato            ║
║   • SellPotatoes           → sell normal dengan jumlah tertentu  ║
║   • SellGoldenPotatoes     → sell golden dengan jumlah tertentu  ║
║   • UpdateAutoSellSettings → update setting auto sell game       ║
║   • AutoSellTriggered      → event ketika auto sell terjadi      ║
║   • GetPlayerData          → ambil data player (harga, balance)  ║
║   • DataUpdated            → event update data real-time         ║
║                                                                  ║
║  BALANCE paths dari scan:                                        ║
║   • Normal : CurrencyFrame.PotatoRow.PotatoCount (text)         ║
║   • Golden : CurrencyFrame.GoldenRow.GoldenCount (text)         ║
╚══════════════════════════════════════════════════════════════════╝
]]

-- ════════════════════════════════════════════════
--  SERVICES
-- ════════════════════════════════════════════════
local Players       = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService    = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ════════════════════════════════════════════════
--  REMOTES (Verified dari scan)
-- ════════════════════════════════════════════════
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not Remotes then
    warn("[AutoSell] Remotes folder tidak ditemukan!")
    return
end

local remote = {
    SellAll         = Remotes:WaitForChild("SellAllPotatoes", 10),
    SellAllGolden   = Remotes:WaitForChild("SellAllGoldenPotatoes", 10),
    SellPotatoes    = Remotes:WaitForChild("SellPotatoes", 10),
    SellGolden      = Remotes:WaitForChild("SellGoldenPotatoes", 10),
    UpdateAutoSell  = Remotes:WaitForChild("UpdateAutoSellSettings", 10),
    GetPlayerData   = Remotes:WaitForChild("GetPlayerData", 10),
    DataUpdated     = Remotes:WaitForChild("DataUpdated", 10),
    SellComplete    = Remotes:WaitForChild("SellComplete", 10),
    AutoSellTriggered = Remotes:WaitForChild("AutoSellTriggered", 10),
}

-- Cek semua remote tersedia
local allRemotesOk = true
for name, r in pairs(remote) do
    if not r then
        warn("[AutoSell] Remote tidak ditemukan: " .. name)
        allRemotesOk = false
    end
end

-- ════════════════════════════════════════════════
--  CONFIG
-- ════════════════════════════════════════════════
local Config = {
    -- Normal Potato
    normalEnabled   = true,
    normalTarget    = 1.0,      -- sell jika harga >= nilai ini
    normalMode      = "above",  -- "above" = jual saat harga di atas target
                                -- "below" = jual saat harga di bawah target
                                -- "always" = selalu jual

    -- Golden Potato
    goldenEnabled   = true,
    goldenTarget    = 100.0,
    goldenMode      = "above",

    -- Timing
    checkInterval   = 1.0,     -- cek harga setiap N detik
    sellDelay       = 0.3,     -- delay antara sell normal & golden

    -- Debug
    debug           = true,
}

-- ════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════
local State = {
    enabled         = false,
    normalPrice     = 0,
    goldenPrice     = 0,
    normalBalance   = 0,
    goldenBalance   = 0,
    totalNormalSold = 0,
    totalGoldenSold = 0,
    sellCount       = 0,
    lastSellTime    = 0,
    lastCheck       = 0,
    playerData      = nil,
}

-- ════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════

local function log(msg)
    if Config.debug then
        print("[AutoSell] " .. msg)
    end
end

local function parseNumber(text)
    if not text or text == "" then return 0 end
    text = tostring(text):gsub(",", ""):gsub("%s", "")

    local num, suffix = text:match("^([%d%.]+)([KMBTkm]?)$")
    if not num then
        -- Try matching with $ prefix
        num, suffix = text:match("^%$([%d%.]+)([KMBTkm]?)$")
    end
    if not num then return 0 end

    local value = tonumber(num) or 0
    local s = suffix:upper()
    if s == "K" then value = value * 1e3
    elseif s == "M" then value = value * 1e6
    elseif s == "B" then value = value * 1e9
    elseif s == "T" then value = value * 1e12
    end
    return value
end

local function formatNumber(n)
    if n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return string.format("%.2f", n)
    end
end

-- ════════════════════════════════════════════════
--  PRICE READING - 3 methods
-- ════════════════════════════════════════════════

-- Method 1: Read from GetPlayerData RemoteFunction
local function getPricesFromRemote()
    if not remote.GetPlayerData then return false end
    local ok, data = pcall(function()
        return remote.GetPlayerData:InvokeServer()
    end)
    if ok and data then
        State.playerData = data
        -- Try common data structures
        -- Structure 1: data.marketPrices.normal / data.marketPrices.golden
        if data.marketPrices then
            State.normalPrice = data.marketPrices.normal or data.marketPrices.potato or 0
            State.goldenPrice = data.marketPrices.golden or data.marketPrices.goldenPotato or 0
            return true
        end
        -- Structure 2: data.prices
        if data.prices then
            State.normalPrice = data.prices.normal or data.prices[1] or 0
            State.goldenPrice = data.prices.golden or data.prices[2] or 0
            return true
        end
        -- Structure 3: direct fields
        if data.potatoPrice or data.normalPrice then
            State.normalPrice = data.potatoPrice or data.normalPrice or 0
            State.goldenPrice = data.goldenPrice or data.goldenPotatoPrice or 0
            return true
        end
        -- Log the data structure so we can see what's available
        log("PlayerData structure: " .. tostring(data))
        for k, v in pairs(data) do
            if type(v) ~= "table" then
                log("  " .. tostring(k) .. " = " .. tostring(v))
            else
                log("  [TABLE] " .. tostring(k))
            end
        end
    end
    return false
end

-- Method 2: Read from GUI labels (PotatoCount & GoldenCount as fallback balance)
-- From scan: CurrencyFrame.PotatoRow.PotatoCount TEXT="1.85M"
--            CurrencyFrame.GoldenRow.GoldenCount TEXT="160,959.38"
local function getBalanceFromGui()
    local mainGui = playerGui:FindFirstChild("PotatoGameGUI")
    if not mainGui then return end

    local bg = mainGui:FindFirstChild("Background")
    if not bg then return end

    local clickerArea = bg:FindFirstChild("ClickerArea")
    if not clickerArea then return end

    local clickerContainer = clickerArea:FindFirstChild("ClickerContainer")
    if not clickerContainer then return end

    local currencyFrame = clickerContainer:FindFirstChild("CurrencyFrame")
    if not currencyFrame then return end

    -- Normal potato balance
    local potatoRow = currencyFrame:FindFirstChild("PotatoRow")
    if potatoRow then
        local potatoCount = potatoRow:FindFirstChild("PotatoCount")
        if potatoCount then
            State.normalBalance = parseNumber(potatoCount.Text)
        end
    end

    -- Golden potato balance
    local goldenRow = currencyFrame:FindFirstChild("GoldenRow")
    if goldenRow then
        local goldenCount = goldenRow:FindFirstChild("GoldenCount")
        if goldenCount then
            State.goldenBalance = parseNumber(goldenCount.Text)
        end
    end
end

-- Method 3: Listen to DataUpdated event for real-time prices
local function setupDataListener()
    if not remote.DataUpdated then return end
    remote.DataUpdated.OnClientEvent:Connect(function(data)
        if not data then return end
        State.playerData = data

        -- Extract prices from update
        if data.marketPrices then
            State.normalPrice = data.marketPrices.normal or State.normalPrice
            State.goldenPrice = data.marketPrices.golden or State.goldenPrice
        elseif data.prices then
            State.normalPrice = data.prices.normal or data.prices[1] or State.normalPrice
            State.goldenPrice = data.prices.golden or data.prices[2] or State.goldenPrice
        end

        -- Extract balance from update
        if data.potatoes ~= nil then State.normalBalance = data.potatoes end
        if data.goldenPotatoes ~= nil then State.goldenBalance = data.goldenPotatoes end

        log(string.format("DataUpdated → Normal:$%.2f Golden:$%.2f | Bal: N=%s G=%s",
            State.normalPrice, State.goldenPrice,
            formatNumber(State.normalBalance), formatNumber(State.goldenBalance)))
    end)
    log("DataUpdated listener active")
end

-- Listen to SellComplete to track actual sells
local function setupSellListener()
    if not remote.SellComplete then return end
    remote.SellComplete.OnClientEvent:Connect(function(data)
        State.sellCount = State.sellCount + 1
        State.lastSellTime = tick()
        if data then
            if data.normal then State.totalNormalSold = State.totalNormalSold + (data.normal or 0) end
            if data.golden then State.totalGoldenSold = State.totalGoldenSold + (data.golden or 0) end
        end
        log("SellComplete received → total sells: " .. State.sellCount)
        updateUI()
    end)
end

-- Also listen to AutoSellTriggered (game's own auto sell)
local function setupAutoSellListener()
    if not remote.AutoSellTriggered then return end
    remote.AutoSellTriggered.OnClientEvent:Connect(function(data)
        log("Game's native AutoSell triggered: " .. tostring(data))
    end)
end

-- ════════════════════════════════════════════════
--  SELL LOGIC
-- ════════════════════════════════════════════════

local function shouldSell(price, target, mode)
    if mode == "always" then return true end
    if mode == "above" then return price >= target end
    if mode == "below" then return price <= target end
    return false
end

local function doSell()
    if not State.enabled then return end

    local now = tick()
    if now - State.lastSellTime < Config.sellDelay then return end

    -- Get latest balance from GUI
    getBalanceFromGui()

    local soldAnything = false

    -- Sell Normal Potatoes
    if Config.normalEnabled and State.normalBalance > 0 then
        if shouldSell(State.normalPrice, Config.normalTarget, Config.normalMode) then
            local ok, err = pcall(function()
                remote.SellAll:FireServer()
            end)
            if ok then
                log(string.format("✅ SELL NORMAL | Price:$%.2f | Balance:%s",
                    State.normalPrice, formatNumber(State.normalBalance)))
                soldAnything = true
            else
                warn("[AutoSell] SellAll error: " .. tostring(err))
            end
        end
    end

    -- Small delay between sells
    if soldAnything then
        task.wait(Config.sellDelay)
    end

    -- Sell Golden Potatoes
    if Config.goldenEnabled and State.goldenBalance > 0 then
        if shouldSell(State.goldenPrice, Config.goldenTarget, Config.goldenMode) then
            local ok, err = pcall(function()
                remote.SellAllGolden:FireServer()
            end)
            if ok then
                log(string.format("✅ SELL GOLDEN | Price:$%.2f | Balance:%s",
                    State.goldenPrice, formatNumber(State.goldenBalance)))
            else
                warn("[AutoSell] SellAllGolden error: " .. tostring(err))
            end
        end
    end
end

-- ════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════

local UI = {}

-- UI element references (filled in createUI)
local uiRefs = {}

local function updateUI()
    if not uiRefs.statusLabel then return end

    -- Status
    uiRefs.statusLabel.Text = State.enabled and "● RUNNING" or "● STOPPED"
    uiRefs.statusLabel.TextColor3 = State.enabled
        and Color3.fromRGB(72, 199, 120)
        or Color3.fromRGB(239, 68, 68)

    -- Toggle button
    if uiRefs.toggleBtn then
        uiRefs.toggleBtn.Text = State.enabled and "⏸ PAUSE" or "▶ START"
        uiRefs.toggleBtn.BackgroundColor3 = State.enabled
            and Color3.fromRGB(239, 68, 68)
            or Color3.fromRGB(72, 199, 120)
    end

    -- Price display
    if uiRefs.normalPriceLabel then
        uiRefs.normalPriceLabel.Text = string.format("$%.4f", State.normalPrice)
    end
    if uiRefs.goldenPriceLabel then
        uiRefs.goldenPriceLabel.Text = string.format("$%.4f", State.goldenPrice)
    end

    -- Balance display
    if uiRefs.normalBalLabel then
        uiRefs.normalBalLabel.Text = formatNumber(State.normalBalance)
    end
    if uiRefs.goldenBalLabel then
        uiRefs.goldenBalLabel.Text = formatNumber(State.goldenBalance)
    end

    -- Stats
    if uiRefs.statsLabel then
        uiRefs.statsLabel.Text = string.format("Sells: %d", State.sellCount)
    end
end

local function createLabel(parent, text, size, pos, color, fontSize, bold)
    local label = Instance.new("TextLabel")
    label.Size = size
    label.Position = pos
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(220, 220, 220)
    label.BackgroundTransparency = 1
    label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    label.TextSize = fontSize or 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function createButton(parent, text, pos, size, bg, textColor)
    local btn = Instance.new("TextButton")
    btn.Size = size or UDim2.new(1, -10, 0, 28)
    btn.Position = pos or UDim2.new(0, 5, 0, 0)
    btn.Text = text
    btn.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    btn.BackgroundColor3 = bg or Color3.fromRGB(60, 60, 80)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    btn.Parent = parent
    return btn
end

local function createInput(parent, pos, size, default)
    local box = Instance.new("TextBox")
    box.Size = size or UDim2.new(0.5, -5, 0, 22)
    box.Position = pos or UDim2.new(0.5, 2, 0, 0)
    box.Text = tostring(default or "")
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    box.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
    box.Font = Enum.Font.Gotham
    box.TextSize = 12
    box.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = box
    box.Parent = parent
    return box
end

local function createSeparator(parent, yOffset)
    local sep = Instance.new("Frame")
    sep.Size = UDim2.new(1, -10, 0, 1)
    sep.Position = UDim2.new(0, 5, 0, yOffset)
    sep.BackgroundColor3 = Color3.fromRGB(60, 50, 40)
    sep.BorderSizePixel = 0
    sep.Parent = parent
    return sep
end

local function createUI()
    -- Cleanup existing
    local existing = playerGui:FindFirstChild("AutoSellGUI_v4")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoSellGUI_v4"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    -- Main frame
    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 280, 0, 420)
    frame.Position = UDim2.new(0, 10, 0.5, -210)
    frame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(180, 140, 60)
    stroke.Thickness = 1.5
    stroke.Parent = frame

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(173, 125, 61)
    header.BorderSizePixel = 0
    header.Parent = frame
    local hCorner = Instance.new("UICorner")
    hCorner.CornerRadius = UDim.new(0, 10)
    hCorner.Parent = header

    -- Header fix (bottom corners)
    local hFix = Instance.new("Frame")
    hFix.Size = UDim2.new(1, 0, 0, 10)
    hFix.Position = UDim2.new(0, 0, 1, -10)
    hFix.BackgroundColor3 = Color3.fromRGB(173, 125, 61)
    hFix.BorderSizePixel = 0
    hFix.Parent = header

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -10, 1, 0)
    titleLabel.Position = UDim2.new(0, 10, 0, 0)
    titleLabel.Text = "⚡ AUTO SELL v4.0"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header

    -- Status label (top right)
    uiRefs.statusLabel = Instance.new("TextLabel")
    uiRefs.statusLabel.Size = UDim2.new(0, 90, 0, 20)
    uiRefs.statusLabel.Position = UDim2.new(1, -100, 0, 8)
    uiRefs.statusLabel.Text = "● STOPPED"
    uiRefs.statusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
    uiRefs.statusLabel.BackgroundTransparency = 1
    uiRefs.statusLabel.Font = Enum.Font.GothamBold
    uiRefs.statusLabel.TextSize = 12
    uiRefs.statusLabel.TextXAlignment = Enum.TextXAlignment.Right
    uiRefs.statusLabel.Parent = header

    -- Content area
    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, 0, 1, -36)
    content.Position = UDim2.new(0, 0, 0, 36)
    content.BackgroundTransparency = 1
    content.Parent = frame

    local y = 8

    -- === NORMAL POTATO SECTION ===
    createLabel(content, "🟡 NORMAL POTATOES", UDim2.new(1, -10, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(240, 200, 80), 12, true)
    y = y + 20

    -- Price row
    createLabel(content, "Current Price:", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    uiRefs.normalPriceLabel = createLabel(content, "$0.0000",
        UDim2.new(0.5, -5, 0, 16), UDim2.new(0.5, 5, 0, y),
        Color3.fromRGB(100, 220, 100), 11, true)
    y = y + 18

    -- Balance row
    createLabel(content, "Balance:", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    uiRefs.normalBalLabel = createLabel(content, "0",
        UDim2.new(0.5, -5, 0, 16), UDim2.new(0.5, 5, 0, y),
        Color3.fromRGB(220, 220, 220), 11)
    y = y + 20

    -- Target price input
    createLabel(content, "Target Price ($):", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    local normalTargetBox = createInput(content, UDim2.new(0.5, 2, 0, y-2),
        UDim2.new(0.4, 0, 0, 20), Config.normalTarget)
    normalTargetBox:GetPropertyChangedSignal("Text"):Connect(function()
        local v = tonumber(normalTargetBox.Text)
        if v then Config.normalTarget = v end
    end)
    y = y + 24

    -- Mode selector
    createLabel(content, "Sell When:", UDim2.new(0.35, 0, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    local normalModeBtn = createButton(content, "Above ▾",
        UDim2.new(0.4, 0, 0, y-2), UDim2.new(0.35, 0, 0, 20),
        Color3.fromRGB(50, 50, 70), Color3.fromRGB(200, 200, 255))
    normalModeBtn.TextSize = 11
    local modes = {"above", "below", "always"}
    local modeIdx = 1
    normalModeBtn.MouseButton1Click:Connect(function()
        modeIdx = (modeIdx % #modes) + 1
        Config.normalMode = modes[modeIdx]
        local labels = {above = "Above ▾", below = "Below ▾", always = "Always"}
        normalModeBtn.Text = labels[Config.normalMode]
    end)
    y = y + 28

    createSeparator(content, y)
    y = y + 10

    -- === GOLDEN POTATO SECTION ===
    createLabel(content, "🌟 GOLDEN POTATOES", UDim2.new(1, -10, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(255, 220, 50), 12, true)
    y = y + 20

    -- Price row
    createLabel(content, "Current Price:", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    uiRefs.goldenPriceLabel = createLabel(content, "$0.0000",
        UDim2.new(0.5, -5, 0, 16), UDim2.new(0.5, 5, 0, y),
        Color3.fromRGB(255, 200, 50), 11, true)
    y = y + 18

    -- Balance row
    createLabel(content, "Balance:", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    uiRefs.goldenBalLabel = createLabel(content, "0",
        UDim2.new(0.5, -5, 0, 16), UDim2.new(0.5, 5, 0, y),
        Color3.fromRGB(220, 220, 220), 11)
    y = y + 20

    -- Target price input
    createLabel(content, "Target Price ($):", UDim2.new(0.5, -5, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    local goldenTargetBox = createInput(content, UDim2.new(0.5, 2, 0, y-2),
        UDim2.new(0.4, 0, 0, 20), Config.goldenTarget)
    goldenTargetBox:GetPropertyChangedSignal("Text"):Connect(function()
        local v = tonumber(goldenTargetBox.Text)
        if v then Config.goldenTarget = v end
    end)
    y = y + 24

    -- Mode selector
    createLabel(content, "Sell When:", UDim2.new(0.35, 0, 0, 16),
        UDim2.new(0, 8, 0, y), Color3.fromRGB(180, 180, 180), 11)
    local goldenModeBtn = createButton(content, "Above ▾",
        UDim2.new(0.4, 0, 0, y-2), UDim2.new(0.35, 0, 0, 20),
        Color3.fromRGB(50, 50, 70), Color3.fromRGB(200, 200, 255))
    goldenModeBtn.TextSize = 11
    local gModeIdx = 1
    goldenModeBtn.MouseButton1Click:Connect(function()
        gModeIdx = (gModeIdx % #modes) + 1
        Config.goldenMode = modes[gModeIdx]
        local labels = {above = "Above ▾", below = "Below ▾", always = "Always"}
        goldenModeBtn.Text = labels[Config.goldenMode]
    end)
    y = y + 28

    createSeparator(content, y)
    y = y + 10

    -- Stats row
    uiRefs.statsLabel = createLabel(content, "Sells: 0",
        UDim2.new(1, -10, 0, 14), UDim2.new(0, 8, 0, y),
        Color3.fromRGB(150, 150, 150), 10)
    y = y + 18

    -- Sell NOW buttons
    local sellNowBtn = createButton(content, "⚡ Sell ALL Now",
        UDim2.new(0, 8, 0, y), UDim2.new(0.48, -4, 0, 28),
        Color3.fromRGB(220, 140, 20))
    sellNowBtn.MouseButton1Click:Connect(function()
        getBalanceFromGui()
        pcall(function() remote.SellAll:FireServer() end)
        task.wait(0.1)
        pcall(function() remote.SellAllGolden:FireServer() end)
        log("Manual SELL ALL triggered")
    end)

    local refreshBtn = createButton(content, "🔄 Refresh Data",
        UDim2.new(0.5, 4, 0, y), UDim2.new(0.48, -4, 0, 28),
        Color3.fromRGB(40, 80, 140))
    refreshBtn.MouseButton1Click:Connect(function()
        getPricesFromRemote()
        getBalanceFromGui()
        updateUI()
        log("Manual refresh triggered")
    end)
    y = y + 36

    -- Toggle button
    uiRefs.toggleBtn = createButton(content, "▶ START",
        UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 32),
        Color3.fromRGB(72, 199, 120))
    uiRefs.toggleBtn.TextSize = 14
    uiRefs.toggleBtn.MouseButton1Click:Connect(function()
        State.enabled = not State.enabled
        log("AutoSell " .. (State.enabled and "ENABLED" or "DISABLED"))
        updateUI()
    end)

    -- Draggable
    local dragging = false
    local dragStart, frameStart
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            frameStart = frame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                frameStart.X.Scale, frameStart.X.Offset + delta.X,
                frameStart.Y.Scale, frameStart.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    -- F1 toggle
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.F1 then
            State.enabled = not State.enabled
            log("F1 Toggle → " .. (State.enabled and "ON" or "OFF"))
            updateUI()
        end
    end)

    updateUI()
    log("UI created successfully")
end

-- ════════════════════════════════════════════════
--  MAIN LOOP
-- ════════════════════════════════════════════════

local function mainLoop()
    local now = tick()
    if now - State.lastCheck < Config.checkInterval then return end
    State.lastCheck = now

    -- Always update balance from GUI
    getBalanceFromGui()
    updateUI()

    -- Run sell logic if enabled
    if State.enabled then
        doSell()
    end
end

-- ════════════════════════════════════════════════
--  INITIALIZE
-- ════════════════════════════════════════════════

log("Initializing AutoSell v4.0...")

-- Setup listeners
setupDataListener()
setupSellListener()
setupAutoSellListener()

-- Create UI
createUI()

-- Initial data fetch
task.spawn(function()
    task.wait(1)
    local ok = getPricesFromRemote()
    getBalanceFromGui()
    if ok then
        log("Initial price data loaded from remote")
    else
        log("Prices will update via DataUpdated events")
    end
    updateUI()
end)

-- Main loop via RunService
local loopConn = RunService.Heartbeat:Connect(mainLoop)

-- Cleanup function
_G.AutoSellV4_Stop = function()
    if loopConn then loopConn:Disconnect() end
    local gui = playerGui:FindFirstChild("AutoSellGUI_v4")
    if gui then gui:Destroy() end
    log("AutoSell v4.0 stopped and cleaned up")
end

log("✅ AutoSell v4.0 ready!")
log("   F1 = toggle on/off")
log("   _G.AutoSellV4_Stop() = unload script")
log("")
log("REMOTE EVENTS AVAILABLE:")
log("  SellAllPotatoes       → sell semua normal")
log("  SellAllGoldenPotatoes → sell semua golden")
log("  UpdateAutoSellSettings → update game's own auto sell")
log("  DataUpdated → listen harga real-time")
