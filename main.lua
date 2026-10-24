-- POLY LOOT DUNGEON SPEEDRUN V5 + OASIS UI + 24H KEY
-- ============================================
-- POLY LOOT | DUNGEON SPEEDRUN V5 UNIVERSAL + ANTI-AFK

-- ============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================
-- 24H KEY SYSTEM | CLIENT SETTINGS
-- ============================================
local GET_KEY_URL = "https://direct-link.net/6460787/oJsS6xwt1UrJ"
local KEY_VERIFY_URL = "https://polyloot-key-api.lyrabo6.workers.dev/api/verify"
local KEY_RECHECK_SECONDS = 120
-- A failed network recheck must not invalidate a server-approved 24h key.
-- Retry sooner, but NEVER extend the local/server license expiry.
local KEY_RECHECK_RETRY_SECONDS = 20
-- An unreachable license server is tolerated briefly, not indefinitely.
local KEY_RECHECK_GRACE_SECONDS = 600
local SAVE_KEY_LOCALLY = true 
local KEY_CACHE_FILE = "PolyLoot_24h_AccessKey.txt"

local accessGranted = false
local accessKey = nil
local accessDeadline = 0
local nextServerCheck = 0
local accessBusy = false
local consecutiveRecheckFailures = 0
local lastSuccessfulServerCheck = 0


-- ============================================
-- EINSTELLUNGEN

-- ============================================
-- Equipped combat tool is detected automatically.
-- Add utility/non-combat Tool names here to avoid using them as weapons.
local NON_WEAPON_TOOLS = {
    ["halloween dungeon 2026"] = true,
    ["ghostnet"] = true,
}
-- Kampf
local ATTACK_DISTANCE = 2
local ATTACK_INTERVAL = 0.65
local ATTACK_STABILIZE = 0.12
local TARGET_SEARCH_RADIUS = 140
local REPOSITION_DISTANCE = 3.5
local REPOSITION_INTERVAL = 0.35
-- Bewegungs-Vorhersage
local PREDICTION_TIME = 0.04
local MAX_PREDICTION = 0.8
-- Anti-Stuck
local NO_DAMAGE_TIMEOUT = 12
local ENEMY_RETRY_DELAY = 5
-- Navigation
local DOOR_TELEPORT_DISTANCE = 12
local ROOM_CONFIRM_TIMEOUT = 6
local ROOM_RETRY_DELAY = 1.5
local ROOM_TRANSITION_DELAY = 1.5
local AUTO_ENTER_FIRST_ROOM = true

-- Auto Replay is opt-in because each successful restart costs one
-- Halloween Dungeon 2026 item. Selects available executor APIs automatically.
local AUTO_REPLAY_DEFAULT = false
-- Anti-AFK is enabled by default, but only sends activity while the
-- licensed Speedrun is running. It can be toggled independently in the GUI.
local ANTI_AFK_DEFAULT = true
local REPLAY_CONFIRM_TIMEOUT = 15
local transitionUntil = 0
local DEBUG_MODE = true

-- ============================================
-- AUTOMATISCHE DROP-SAMMLUNG

-- ============================================
local LOOT_SEARCH_RADIUS = 65
local LOOT_TIMEOUT = 8
local LOOT_SETTLE_TIME = 0.6
local LOOT_PICKUP_WAIT = 0.35

-- ============================================
-- STATUS

-- ============================================
local running = false
local sessionId = 0
local currentRoom = 0
local currentWave = 0
local totalWaves = 0
local roomCleared = false
local dungeonComplete = false
local waitingForRestart = false
local completedRuns = 0
local finalLootHandled = false
local restartRoomObserved = false
local autoReplayEnabled = AUTO_REPLAY_DEFAULT
local antiAfkEnabled = ANTI_AFK_DEFAULT
local replayAttempted = false
local replayAttemptAt = 0
local attackCount = 0
local defeatedCount = 0
local skippedEnemies = {}
local usedDoors = {}
local currentHighlight = nil
local lastRoomAttempt = 0

-- ============================================
-- SPIELOBJEKTE

-- ============================================

local function getEnemies()
    local live = workspace:FindFirstChild("Animal_Live")
    return live and live:FindFirstChild("Aggressors")
end

local function getDungeon()
    return workspace:FindFirstChild(
        "HalloweenDungeon_Chain"
    )
end

local function getCharacter()
    return player.Character
end

local function getRoot()
    local character = getCharacter()
    return character
        and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = getCharacter()
    return character
        and character:FindFirstChildOfClass("Humanoid")
end

local function getWeapon()
    local character = getCharacter()
    if not character then
        return nil
    end

    -- Equipped Roblox Tools are parented to the player's Character.
    -- Backpack items are intentionally ignored until equipped.
    local fallback = nil
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and not NON_WEAPON_TOOLS[tool.Name:lower()] then
            -- Prefer items carrying the game's weapon attributes when available.
            if tool:GetAttribute("WeaponId") ~= nil
                or tool:GetAttribute("WeaponRank") ~= nil
                or tool:GetAttribute("_HitboxReach") ~= nil then
                return tool
            end
            fallback = fallback or tool
        end
    end
    return fallback
end

local function validSession(id)
    return running and sessionId == id and accessGranted and os.clock() < accessDeadline
end

local function debugPrint(...)
    if DEBUG_MODE then
        print("[DUNGEON V5]", ...)
    end
end

local function horizontalDistance(a, b)
    return Vector3.new(
        a.X - b.X,
        0,
        a.Z - b.Z
    ).Magnitude
end

-- ============================================
-- OASIS UI | DUNGEON SELECTION HUB
-- ============================================
-- OasisUI's demo features are NOT loaded. Only the controls below exist.
-- Keep the original 24H Key window as a separate login gate.
local oldGui = playerGui:FindFirstChild("PolyLootDungeonV4")
if oldGui then oldGui:Destroy() end

-- A lightweight lifecycle parent retained for the existing dungeon logic,
-- and for target Highlights that were parented to the old ScreenGui.
local gui = Instance.new("ScreenGui")
gui.Name = "PolyLootDungeonV4"
gui.ResetOnSpawn = false
gui.Parent = playerGui

local OasisUI = loadstring(game:HttpGet(
    "https://github.com/Mold53/OasisUI/releases/download/v1.6.0/OasisUI.lua"
))()

local Window = OasisUI:CreateWindow({
    Title = "POLY LOOT",
    Subtitle = "Dungeon Speedrun V5",
    Folder = "PolyLootSpeedrun",
    GuiName = "PolyLootOasisV5",
    Icon = "swords",
    Theme = "Midnight",
    ToggleKey = Enum.KeyCode.RightShift,
    Settings = false,          -- Hide built-in settings/config editor
    Search = false,            -- Hide the search bar
    SearchShortcut = false,
    User = false,              -- Hide the user profile card
    AutoLoad = false,          -- Do not restore a saved Speedrun ON state
    AutoSave = false,
    CloseAction = "Hide",
})
Window:SetVisible(false)     -- Key must be verified first

-- Legacy "frame.Visible" reads/writes are mapped to the Oasis window.
-- This also keeps the Auto Replay mouse-blocking workaround intact.
local oasisVisible = false
local frame = setmetatable({}, {
    __index = function(_, key)
        if key == "Visible" then return oasisVisible end
    end,
    __newindex = function(_, key, value)
        if key == "Visible" then
            oasisVisible = value == true
            Window:SetVisible(oasisVisible)
        end
    end,
})

-- Make Oasis labels respond to the existing statusLabel.Text assignments.
-- This lets the combat/navigation logic stay untouched.
local function textProxy(element)
    local current = ""
    return setmetatable({}, {
        __index = function(_, key)
            if key == "Text" then return current end
        end,
        __newindex = function(_, key, value)
            if key == "Text" then
                current = tostring(value)
                element:SetValue(current:match("^[^:]+:%s*(.*)$") or current)
            end
        end,
    })
end

-- Dungeon hub architecture: selecting a dungeon reveals only its own controls.
-- To add another dungeon later, register it below and implement its engine.
local DUNGEON_ORDER = { "halloween" }
local DUNGEONS = {
    halloween = {
        Title = "Halloween Dungeon",
        Description = "Halloween Dungeon 2026 | 18 rooms and bosses",
        Icon = "skull",
    },
}

local selectedDungeonId = nil
local onSpeedrunToggle = nil   -- Implemented after the dungeon loop
local syncingSpeedrun = false

local dungeonTab = Window:Tab({ Title = "Dungeon", Icon = "swords", Columns = 1 })
local statusTab = Window:Tab({ Title = "Status", Icon = "activity", Columns = 1 })

-- Only registered dungeons appear in the selector. No fake or placeholder modes.
local dungeonValues = {}
for _, dungeonId in ipairs(DUNGEON_ORDER) do
    local definition = DUNGEONS[dungeonId]
    table.insert(dungeonValues, {
        Title = definition.Title,
        Value = dungeonId,
        Description = definition.Description,
        Icon = definition.Icon,
    })
end

local selectorSection = dungeonTab:Section({ Title = "Dungeon Selection", Icon = "list" })
local selectorInfo = selectorSection:Paragraph({
    Title = "Select a Dungeon",
    Content = "Choose a dungeon to display its available farming functions.",
    Icon = "info",
})
local onDungeonSelected = nil
local dungeonSelector = selectorSection:Dropdown({
    Title = "Dungeon",
    Values = dungeonValues,
    Default = nil,
    Multi = false,
    AllowNone = true,
    Search = false,
    Placeholder = "Choose a dungeon...",
    Callback = function(value)
        if onDungeonSelected then
            onDungeonSelected(value)
        end
    end,
})

-- Halloween-specific features: displayed only while Halloween is selected.
local speedrunModule = dungeonTab:Module({
    Title = "Dungeon Speedrun",
    Description = "Automatically enter, fight, and clear the 18 Halloween rooms.",
    Icon = "swords",
    Keybind = false,
    Default = false,
    Callback = function(enabled)
        if not syncingSpeedrun and onSpeedrunToggle then
            onSpeedrunToggle(enabled)
        end
    end,
})

local autoReplayModule = dungeonTab:Module({
    Title = "Auto Replay",
    Description = "Attempt to restart after clearing the dungeon. Uses one dungeon item per successful replay.",
    Icon = "rotate-cw",
    Keybind = false,
    Default = AUTO_REPLAY_DEFAULT,
    Callback = function(enabled)
        autoReplayEnabled = enabled
        debugPrint("Auto Replay:", enabled and "ON" or "OFF")
    end,
})

local antiAfkModule = dungeonTab:Module({
    Title = "Anti-AFK",
    Description = "Attempt to prevent idle disconnects while the licensed Speedrun is running.",
    Icon = "shield-check",
    Keybind = false,
    Default = ANTI_AFK_DEFAULT,
    Callback = function(enabled)
        antiAfkEnabled = enabled
        debugPrint("Anti-AFK:", enabled and "ON" or "OFF")
    end,
})

-- Future dungeons register their own modules here, without showing
-- irrelevant controls from the Halloween farm.
local dungeonModules = {
    halloween = { speedrunModule, autoReplayModule, antiAfkModule },
}

local function updateDungeonModules()
    for dungeonId, modules in pairs(dungeonModules) do
        local show = (dungeonId == selectedDungeonId)
        for _, module in ipairs(modules) do
            module:SetVisible(show)
        end
    end
end

onDungeonSelected = function(value)
    -- OasisUI single-select returns the configured string Value.
    -- This also handles clearing the selection or a table value defensively.
    if type(value) == "table" then
        value = value.Value or value.value or value[1]
    end
    if type(value) ~= "string" or not DUNGEONS[value] then
        value = nil
    end
    if value == selectedDungeonId then
        return
    end

    -- Switching or clearing a selected dungeon safely stops a running farm.
    if running and onSpeedrunToggle then
        onSpeedrunToggle(false)
    end
    selectedDungeonId = value
    updateDungeonModules()

    if selectedDungeonId == "halloween" then
        selectorInfo:SetContent(
            "Halloween Dungeon 2026 selected. Choose Speedrun, Auto Replay, and Anti-AFK below."
        )
        Window:SetSubtitle("Halloween Dungeon | Speedrun V5")
        debugPrint("Dungeon selected:", "Halloween Dungeon")
    else
        selectorInfo:SetContent("Choose a dungeon to display its available farming functions.")
        Window:SetSubtitle("Dungeon Speedrun V5")
        debugPrint("Dungeon selection cleared")
    end
end

-- On first launch, nothing is selected and no farming controls are visible.
updateDungeonModules()
onDungeonSelected(dungeonSelector:Get())

-- Universal status and license page retained independently from the selected dungeon.
local live = statusTab:Section({ Title = "Dungeon Statistics", Icon = "chart-no-axes-column" })
local roomLabel = textProxy(live:Label({ Text = "Room", Value = "Room: - / 18" }))
local waveLabel = textProxy(live:Label({ Text = "Wave", Value = "Wave: -" }))
local targetLabel = textProxy(live:Label({ Text = "Target", Value = "Target: -" }))
local healthLabel = textProxy(live:Label({ Text = "Target HP", Value = "HP: -" }))
local killLabel = textProxy(live:Label({ Text = "Defeated", Value = "Enemies defeated: 0" }))
local attackLabel = textProxy(live:Label({ Text = "Attacks", Value = "Attacks: 0" }))
local statusLabel = textProxy(live:Label({ Text = "Status", Value = "Status: Ready" }))
local licenseArea = statusTab:Section({ Title = "License", Icon = "key-round" })
local licenseButton = textProxy(licenseArea:Label({ Text = "Remaining access", Value = "Not activated" }))

local function setButton(enabled)
    syncingSpeedrun = true
    if speedrunModule:Get() ~= enabled then
        speedrunModule:Set(enabled)
    end
    syncingSpeedrun = false
end

-- Stop all background dungeon tasks if OasisUI is unloaded.
OasisUI:OnUnload(function()
    running = false
    sessionId = sessionId + 1
    if gui.Parent then gui:Destroy() end
    local oldAccess = playerGui:FindFirstChild("PolyLootAccessV4")
    if oldAccess then oldAccess:Destroy() end
end)

local function stopMovement()
    local humanoid = getHumanoid()
    local root = getRoot()
    if humanoid and root then
        humanoid:MoveTo(root.Position)
    end
end


-- ============================================
-- KEY GUI / SERVER VERIFICATION
-- ============================================
local HttpService = game:GetService("HttpService")

local previousAccessGui = playerGui:FindFirstChild("PolyLootAccessV4")
if previousAccessGui then
    previousAccessGui:Destroy()
end

local accessGui = Instance.new("ScreenGui")
accessGui.Name = "PolyLootAccessV4"
accessGui.ResetOnSpawn = false
accessGui.DisplayOrder = 200
accessGui.Parent = playerGui

local accessFrame = Instance.new("Frame")
accessFrame.Name = "AccessPanel"
accessFrame.Size = UDim2.fromOffset(348, 325)
accessFrame.Position = UDim2.new(0.5, -174, 0.5, -162)
accessFrame.BackgroundColor3 = Color3.fromRGB(26, 26, 39)
accessFrame.BorderSizePixel = 0
accessFrame.Active = true
accessFrame.Draggable = true
accessFrame.Parent = accessGui
Instance.new("UICorner", accessFrame).CornerRadius = UDim.new(0, 14)

local function keyGuiText(name, content, y, h, size, color)
    local obj = Instance.new("TextLabel")
    obj.Name = name
    obj.Size = UDim2.new(1, -32, 0, h)
    obj.Position = UDim2.fromOffset(16, y)
    obj.BackgroundTransparency = 1
    obj.Text = content
    obj.TextColor3 = color or Color3.fromRGB(225, 225, 235)
    obj.TextSize = size or 14
    obj.TextWrapped = true
    obj.Font = Enum.Font.Gotham
    obj.Parent = accessFrame
    return obj
end

local accessTitle = keyGuiText("Title", "POLY LOOT | 24H ACCESS", 16, 28, 19)
accessTitle.Font = Enum.Font.GothamBold
keyGuiText("Description", "A valid key unlocks the Dungeon Speedrun.", 52, 38, 12, Color3.fromRGB(160, 165, 190))

local keyInput = Instance.new("TextBox")
keyInput.Name = "KeyInput"
keyInput.Size = UDim2.new(1, -32, 0, 42)
keyInput.Position = UDim2.fromOffset(16, 100)
keyInput.BackgroundColor3 = Color3.fromRGB(41, 42, 60)
keyInput.BorderSizePixel = 0
keyInput.PlaceholderText = "PL-XXXXXXXXXXXXXXXX..."
keyInput.ClearTextOnFocus = false
keyInput.Text = ""
keyInput.TextColor3 = Color3.fromRGB(245, 245, 250)
keyInput.PlaceholderColor3 = Color3.fromRGB(150, 150, 175)
keyInput.TextSize = 13
keyInput.Font = Enum.Font.Code
keyInput.Parent = accessFrame
Instance.new("UICorner", keyInput).CornerRadius = UDim.new(0, 8)

local function keyGuiButton(name, caption, x, y, width, bg)
    local obj = Instance.new("TextButton")
    obj.Name = name
    obj.Size = UDim2.fromOffset(width, 43)
    obj.Position = UDim2.fromOffset(x, y)
    obj.BackgroundColor3 = bg
    obj.BorderSizePixel = 0
    obj.Text = caption
    obj.TextColor3 = Color3.fromRGB(255, 255, 255)
    obj.TextSize = 14
    obj.Font = Enum.Font.GothamBold
    obj.Parent = accessFrame
    Instance.new("UICorner", obj).CornerRadius = UDim.new(0, 8)
    return obj
end

local getKeyButton = keyGuiButton("GetKey", "GET KEY", 16, 156, 150, Color3.fromRGB(64, 98, 170))
local verifyButton = keyGuiButton("VerifyKey", "VERIFY KEY", 182, 156, 150, Color3.fromRGB(37, 151, 96))

local accessStatus = keyGuiText("Status", "Enter a key or get one through Linkvertise.", 209, 46, 12, Color3.fromRGB(155, 195, 235))
local accessHint = keyGuiText("Hint", "Valid for 24 hours from first activation.", 265, 42, 11, Color3.fromRGB(140, 145, 165))


local manualLinkBox = Instance.new("TextBox")
manualLinkBox.Name = "ManualLink"
manualLinkBox.Size = UDim2.new(1, -32, 0, 27)
manualLinkBox.Position = UDim2.fromOffset(16, 288)
manualLinkBox.BackgroundColor3 = Color3.fromRGB(41, 42, 60)
manualLinkBox.TextColor3 = Color3.fromRGB(235, 235, 245)
manualLinkBox.Font = Enum.Font.Code
manualLinkBox.TextSize = 10
manualLinkBox.ClearTextOnFocus = false
manualLinkBox.Text = ""
manualLinkBox.Visible = false
manualLinkBox.Parent = accessFrame

-- The main window's license display and automation controls are in OasisUI.
-- The existing 24-hour key gate above remains unchanged.
frame.Visible = false

local function secondsToText(seconds)
    local s = math.max(0, math.floor(seconds))
    local hours = math.floor(s / 3600)
    local minutes = math.floor((s % 3600) / 60)
    return string.format("%02dh %02dm", hours, minutes)
end

local function readSavedKey()
    if not SAVE_KEY_LOCALLY or type(readfile) ~= "function" then
        return nil
    end
    local ok, result = pcall(function()
        return readfile(KEY_CACHE_FILE)
    end)
    if ok and type(result) == "string" then
        return result:match("^%s*(.-)%s*$")
    end
    return nil
end

local function saveKeyLocally(key)
    if SAVE_KEY_LOCALLY and type(writefile) == "function" then
        pcall(function() writefile(KEY_CACHE_FILE, key) end)
    end
end

local function requestVerification(key)
    local payload = HttpService:JSONEncode({ key = key })
    local params = {
        Url = KEY_VERIFY_URL,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", Accept = "application/json" },
        Body = payload,
    }

    local transport = nil
    if type(request) == "function" then
        transport = request
    elseif type(http_request) == "function" then
        transport = http_request
    elseif type(syn) == "table" and type(syn.request) == "function" then
        transport = syn.request
    elseif type(http) == "table" and type(http.request) == "function" then
        transport = http.request
    end

    local ok, reply
    if transport then
        ok, reply = pcall(function() return transport(params) end)
    else
        -- Funktioniert nur, falls HTTP-Anfragen in dieser Laufzeit erlaubt sind.
        ok, reply = pcall(function() return HttpService:RequestAsync(params) end)
    end

    if not ok then
        return false, nil, "HTTP request failed (check executor/HTTP)."
    end
    if type(reply) ~= "table" then
        return false, nil, "Unexpected HTTP response."
    end
    local raw = reply.Body or reply.body
    local httpStatus = tonumber(reply.StatusCode or reply.status_code or reply.Status)
    local decodedOk, data = pcall(function()
        return HttpService:JSONDecode(raw or "")
    end)
    if not decodedOk or type(data) ~= "table" then
        return false, nil,
            "License HTTP response invalid (status " .. tostring(httpStatus or "unknown") .. ")."
    end
    -- Explicit server denial is handled by verifyAccessKey(), including expiry.
    -- A gateway error that happens to have JSON must still count as retryable.
    if httpStatus and (httpStatus == 429 or httpStatus >= 500) then
        return false, nil, "License API temporarily unavailable (HTTP " .. httpStatus .. ")."
    end
    return true, data, nil
end

local function stopForAccess(reason)
    accessGranted = false
    accessKey = nil
    accessDeadline = 0
    lastSuccessfulServerCheck = 0
    consecutiveRecheckFailures = 0
    running = false
    sessionId = sessionId + 1
    setButton(false)
    stopMovement()
    frame.Visible = false
    accessGui.Enabled = true
    accessStatus.Text = reason or "A valid key is required."
    accessStatus.TextColor3 = Color3.fromRGB(255, 174, 141)
end

local function verifyAccessKey(key, automatic)
    if accessBusy then return end
    if type(key) ~= "string" then return end

    key = key:match("^%s*(.-)%s*$"):upper()
    if #key ~= 51 or not key:match("^PL%-%x+$") then
        if not automatic then
            accessStatus.Text = "Invalid key format (PL- + 48 hex characters)."
        end
        return
    end

    accessBusy = true
    verifyButton.Text = "VERIFYING..."
    if not automatic then
        accessStatus.Text = "Verifying key with server..."
    end

    local transportOk, data, transportError = requestVerification(key)
    accessBusy = false
    verifyButton.Text = "VERIFY KEY"

    if not transportOk then
        if automatic and accessGranted then
            -- Do not revoke a still-valid license because Solara/HTTP briefly failed.
            consecutiveRecheckFailures = consecutiveRecheckFailures + 1
            if lastSuccessfulServerCheck > 0 and
                os.clock() - lastSuccessfulServerCheck >= KEY_RECHECK_GRACE_SECONDS then
                stopForAccess("License server unreachable for 10 minutes. Verify again.")
                return
            end
            nextServerCheck = os.clock() + KEY_RECHECK_RETRY_SECONDS
            debugPrint("License network recheck failed; retry in",
                KEY_RECHECK_RETRY_SECONDS, "seconds; failures:",
                consecutiveRecheckFailures, "reason:", transportError or "unknown")
        else
            accessStatus.Text = transportError or "Server unavailable."
            accessStatus.TextColor3 = Color3.fromRGB(255, 174, 141)
        end
        return
    end

    local remaining = tonumber(data.secondsRemaining)
    if data.valid == true and remaining and remaining > 0 then
        local serverBasedDeadline = os.clock() + remaining
        -- An automatic renewal is a recheck, NOT a new 24-hour activation.
        -- Keep the earlier known expiry instead of accidentally extending it.
        if automatic and accessGranted and accessDeadline > 0 then
            accessDeadline = math.min(accessDeadline, serverBasedDeadline)
        else
            accessDeadline = serverBasedDeadline
        end
        accessGranted = true
        accessKey = key
        consecutiveRecheckFailures = 0
        lastSuccessfulServerCheck = os.clock()
        nextServerCheck = os.clock() + KEY_RECHECK_SECONDS
        if automatic then
            debugPrint("License recheck OK; remaining minutes:",
                math.floor(remaining / 60))
        end
        keyInput.Text = key
        saveKeyLocally(key)
        accessStatus.Text = "Key valid: " .. secondsToText(remaining) .. " remaining."
        accessStatus.TextColor3 = Color3.fromRGB(147, 224, 181)
        licenseButton.Text = "License: " .. secondsToText(remaining)
        frame.Visible = true
        accessGui.Enabled = false
        return
    end

    local reason = tostring(data.reason or "invalid_key")
    local messages = {
        expired = "Key expired. Get a new key.",
        invalid_key = "Invalid key format.",
        invalid_or_revoked = "Key not found or revoked.",
        database_unavailable = "Key server temporarily unavailable.",
    }
    local message = messages[reason] or ("Key rejected: " .. reason)
    -- Retry only transient/unexpected server errors. Explicit revocation or
    -- expiry still stops immediately. The original local deadline always applies.
    local transientReasons = {
        database_unavailable = true,
        server_unavailable = true,
        internal_error = true,
        rate_limited = true,
    }
    if automatic and accessGranted and
       (transientReasons[reason] or data.valid == nil or
        (data.valid == true and (not remaining or remaining <= 0))) then
        consecutiveRecheckFailures = consecutiveRecheckFailures + 1
        if lastSuccessfulServerCheck > 0 and
            os.clock() - lastSuccessfulServerCheck >= KEY_RECHECK_GRACE_SECONDS then
            stopForAccess("License server verification unavailable for 10 minutes. Verify again.")
            return
        end
        nextServerCheck = os.clock() + KEY_RECHECK_RETRY_SECONDS
        debugPrint("License response not conclusive; retry later:", reason)
        return
    end
    if automatic and accessGranted then
        debugPrint("Server rejected license:", reason)
        stopForAccess(message)
    else
        accessStatus.Text = message
        accessStatus.TextColor3 = Color3.fromRGB(255, 174, 141)
    end
end

getKeyButton.MouseButton1Click:Connect(function()
    if GET_KEY_URL == "HIER_DEIN_LINKVERTISE_LINK_EINFUEGEN"
        or GET_KEY_URL == "" then
        accessStatus.Text = "Set GET_KEY_URL in the script first."
        return
    end
    if type(setclipboard) == "function" then
        local ok = pcall(function() setclipboard(GET_KEY_URL) end)
        if ok then
            accessStatus.Text = "Link copied. Open it in your browser."
            return
        end
    end
    if type(toclipboard) == "function" then
        local ok = pcall(function() toclipboard(GET_KEY_URL) end)
        if ok then
            accessStatus.Text = "Link copied. Open it in your browser."
            return
        end
    end
    manualLinkBox.Text = GET_KEY_URL
    manualLinkBox.Visible = true
    accessStatus.Text = "Copy the link below and open it in your browser."
end)

verifyButton.MouseButton1Click:Connect(function()
    task.spawn(verifyAccessKey, keyInput.Text, false)
end)

keyInput.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        task.spawn(verifyAccessKey, keyInput.Text, false)
    end
end)

-- Bereits freigeschaltete Nutzer koennen das Key-Fenster wieder schliessen.
local closeAccessButton = Instance.new("TextButton")
closeAccessButton.Name = "CloseAccess"
closeAccessButton.Size = UDim2.fromOffset(24, 24)
closeAccessButton.Position = UDim2.new(1, -34, 0, 12)
closeAccessButton.BackgroundTransparency = 1
closeAccessButton.TextColor3 = Color3.fromRGB(190, 190, 205)
closeAccessButton.Text = "X"
closeAccessButton.Font = Enum.Font.GothamBold
closeAccessButton.TextSize = 15
closeAccessButton.Parent = accessFrame
closeAccessButton.MouseButton1Click:Connect(function()
    if accessGranted and os.clock() < accessDeadline then
        accessGui.Enabled = false
    else
        accessStatus.Text = "Please verify your key first."
    end
end)

licenseArea:Button({
    Title = "Open Key Manager",
    Icon = "key-round",
    Callback = function()
        accessStatus.Text = accessGranted
            and ("License: " .. secondsToText(accessDeadline - os.clock()) .. " remaining.")
            or "A valid key is required."
        accessGui.Enabled = true
    end,
})

-- Automatisch gespeicherten Key pruefen (nicht blind vertrauen).
task.spawn(function()
    local cached = readSavedKey()
    if cached and cached ~= "" then
        keyInput.Text = cached
        accessStatus.Text = "Verifying saved key..."
        verifyAccessKey(cached, false)
    end
end)

-- Der Server wird auch bei laufender Autofarm regelmaessig erneut befragt.
task.spawn(function()
    while gui.Parent and accessGui.Parent do
        if accessGranted then
            local remaining = accessDeadline - os.clock()
            if remaining <= 0 then
                stopForAccess("24-hour access expired. Get a new key.")
            else
                licenseButton.Text = "License: " .. secondsToText(remaining)
                if os.clock() >= nextServerCheck and not accessBusy then
                    nextServerCheck = os.clock() + KEY_RECHECK_SECONDS
                    verifyAccessKey(accessKey, true)
                end
            end
        end
        task.wait(1)
    end
end)

-- ============================================
-- UNIVERSAL ANTI-AFK | IDLE EVENT + SAFE FALLBACKS
-- ============================================
-- Fired by Roblox after a period without real player input.
-- No mouse clicks are used: they could accidentally click "Run again".
-- Executor capabilities vary; successful delivery is not a guarantee
-- that Roblox will reset the inactivity timer in every environment.
local antiAfkConnection = nil
local antiAfkWarningShown = false

local function sendAntiAfkActivity()
    -- Most executor environments expose VirtualUser. Prefer its right-click
    -- simulation since it does not require foreground mouse coordinates.
    local virtualUserOk, virtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if virtualUserOk and virtualUser then
        local ok = pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
        if ok then
            return true, "VirtualUser"
        end
    end

    -- Some executors expose VirtualInputManager instead.
    -- F15 should not activate normal in-game buttons or cause movement.
    local vimOk, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if vimOk and vim then
        local ok = pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
            task.wait(0.05)
            vim:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
        end)
        if ok then
            return true, "VirtualInputManager"
        end
    end

    -- Final fallback: executor-specific keyboard APIs. Only attempt
    -- when Roblox is focused; never generate a real desktop key into
    -- the browser, another app, or a chat text field.
    if type(keypress) == "function" and type(keyrelease) == "function" then
        local gameIsFocused = true
        if type(isrbxactive) == "function" then
            local ok, active = pcall(isrbxactive)
            gameIsFocused = ok and active == true
        elseif type(isgameactive) == "function" then
            local ok, active = pcall(isgameactive)
            gameIsFocused = ok and active == true
        else
            -- Unknown focus: do not synthesize desktop input.
            gameIsFocused = false
        end

        local textBoxFocused = false
        local inputOk, inputService = pcall(function()
            return game:GetService("UserInputService")
        end)
        if inputOk and inputService then
            local ok, focused = pcall(function()
                return inputService:GetFocusedTextBox()
            end)
            textBoxFocused = not ok or focused ~= nil
        end

        if gameIsFocused and not textBoxFocused then
            local ok = pcall(function()
                keypress(0x7E) -- F15
                task.wait(0.05)
                keyrelease(0x7E)
            end)
            if ok then
                return true, "Executor F15"
            end
            -- Release best-effort even after an unexpected error.
            pcall(keyrelease, 0x7E)
        end
    end

    return false, "No supported Anti-AFK input method"
end

antiAfkConnection = player.Idled:Connect(function()
    -- When a new script execution replaces this GUI, remove this old listener.
    if not gui.Parent then
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
        return
    end

    if not antiAfkEnabled or not running
        or not accessGranted or os.clock() >= accessDeadline then
        return
    end

    local ok, method = sendAntiAfkActivity()
    if ok then
        debugPrint("Anti-AFK activity sent via", method)
        antiAfkWarningShown = false
    elseif not antiAfkWarningShown then
        warn("[DUNGEON V5] Anti-AFK unavailable: " .. tostring(method))
        antiAfkWarningShown = true
    end
end)

local function dismissLootPopup()
    local rewardScreen = playerGui:FindFirstChild(
        "RewardScreen"
    )
    if not rewardScreen then
        return false
    end
    local main = rewardScreen:FindFirstChild("Main")
    local header = main and main:FindFirstChild("Header")
    local title = header and header:FindFirstChild("Title")
    if not main or not title then
        return false
    end
    if not rewardScreen.Enabled
        or not main.Visible
        or title.Text ~= "NEW LOOT!" then
        return false
    end
    debugPrint("NEW LOOT Popup erkannt")
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local camera = workspace.CurrentCamera
        if not camera then
            error("Keine Kamera")
        end
        local size = camera.ViewportSize
        local x = math.floor(size.X / 2)
        local y = math.floor(size.Y / 2)
        vim:SendMouseButtonEvent(
            x, y, 0, true, game, 0
        )
        task.wait(0.08)
        vim:SendMouseButtonEvent(
            x, y, 0, false, game, 0
        )
    end)
    if not ok then
        warn(
            "[DUNGEON V4] Loot-Klick fehlgeschlagen:",
            err
        )
        return false
    end
    task.wait(0.2)
    return not rewardScreen.Enabled
        or not main.Visible
end

-- ============================================
-- DUNGEON ABSCHLUSS

-- ============================================

local function isDungeonComplete()
    local hud = playerGui:FindFirstChild("DungeonHud")
    if not hud or not hud:IsA("ScreenGui") then
        return false
    end
    local result = hud:FindFirstChild("Result")
    if not result or not result:IsA("GuiObject") then
        return false
    end
    local header = result:FindFirstChild("Header")
    local resultTitle =
        header and header:FindFirstChild("Title")
    if not resultTitle
        or not resultTitle:IsA("TextLabel") then
        return false
    end
    return hud.Enabled
        and result.Visible
        and resultTitle.Text == "Dungeon Cleared!"
end

-- ============================================
-- HALLOWEEN SCENE REPLAY CONFIRMATION
-- ============================================
-- Scene is SERVER -> CLIENT. It confirms a restart but cannot start one.
-- Observed manual replay sequence: exit {reason="again"}, arrive, gate.
-- No __namecall hooks, no RemoteEvent:FireServer calls.
local SCENE_RESTART_WAIT_SECONDS = 45
local sceneReplay = {
    exit = false,
    arrive = false,
    gate = false,
    otherExit = false,
    exitAt = 0,
    arriveAt = 0,
}

local function clearSceneReplay()
    sceneReplay.exit = false
    sceneReplay.arrive = false
    sceneReplay.gate = false
    sceneReplay.otherExit = false
    sceneReplay.exitAt = 0
    sceneReplay.arriveAt = 0
end

local sceneEventsAvailable = false
local function installSceneReplayListener()
    local replicated = game:GetService("ReplicatedStorage")
    local engine = replicated:FindFirstChild("HalloweenDungeon_Engine")
    local remotes = engine and engine:FindFirstChild("Remotes")
    local scene = remotes and remotes:FindFirstChild("Scene")

    if not scene or not scene:IsA("RemoteEvent") then
        debugPrint("[SCENE] Scene RemoteEvent not available; legacy replay detection")
        return false
    end

    local ok, conn = pcall(function()
        return scene.OnClientEvent:Connect(function(action, data)
            -- Only interpret events for a dungeon which is currently completed.
            if not running or not accessGranted or not
                (waitingForRestart or isDungeonComplete()) then
                return
            end
            if type(action) ~= "string" then return end
            if type(data) ~= "table" then data = {} end

            if action == "exit" then
                local reason = tostring(data.reason or "")
                if reason == "again" then
                    if not sceneReplay.exit then
                        sceneReplay.exit = true
                        sceneReplay.exitAt = os.clock()
                        debugPrint("[SCENE] exit(reason=again): restart accepted")
                        statusLabel.Text = "Restart accepted - loading dungeon..."
                    end
                else
                    sceneReplay.otherExit = true
                    debugPrint("[SCENE] exit(reason=" .. reason .. "): not a replay")
                end
            elseif action == "arrive" and sceneReplay.exit then
                local dungeonName = tostring(data.name or "")
                if dungeonName == "" or dungeonName == "Halloween Dungeon 2026" then
                    sceneReplay.arrive = true
                    sceneReplay.arriveAt = os.clock()
                    debugPrint("[SCENE] arrive: new dungeon loaded")
                    statusLabel.Text = "New dungeon loaded - waiting for gate..."
                end
            elseif action == "gate" and sceneReplay.arrive then
                if tonumber(data.room) == 1 and data.open == true then
                    sceneReplay.gate = true
                    debugPrint("[SCENE] gate(room=1, open=true): ready to continue")
                    statusLabel.Text = "Dungeon ready - resuming speedrun"
                end
            end
        end)
    end)

    if not ok or not conn then
        debugPrint("[SCENE] Failed to connect; legacy replay detection")
        return false
    end

    -- Prevent accumulating listeners when the script GUI is destroyed.
    gui.Destroying:Connect(function()
        pcall(function() conn:Disconnect() end)
    end)
    debugPrint("[SCENE] Listener enabled: exit -> arrive -> gate")
    return true
end

sceneEventsAvailable = installSceneReplayListener()

-- ============================================
-- RAUM UND WELLEN

-- ============================================

local function processNotification(text)
    if type(text) ~= "string" then
        return
    end
    local room, _, waves = text:match(
        "Room%s+(%d+)%s*/%s*(%d+)%s*[^%d]+(%d+)%s+waves"
    )
    if room then
        local newRoom = tonumber(room)
        if waitingForRestart and newRoom == 1 then
            restartRoomObserved = true
            debugPrint("Neuer Dungeon: Raum 1 angekuendigt")
        end
        if newRoom ~= currentRoom then
            currentRoom = newRoom
            currentWave = 0
            totalWaves = tonumber(waves)
            roomCleared = false
            debugPrint("Neuer Raum:", currentRoom)
        end
        roomLabel.Text =
            "Room: " .. currentRoom .. " / 18"
        waveLabel.Text =
            "Waves: " .. totalWaves
        return
    end
    local wave, maxWave = text:match(
        "Wave%s+(%d+)%s*/%s*(%d+)"
    )
    if wave then
        currentWave = tonumber(wave)
        totalWaves = tonumber(maxWave)
        roomCleared = false
        waveLabel.Text =
            "Wave: " .. currentWave
            .. " / " .. totalWaves
        return
    end
    if text:lower():find("final wave", 1, true) then
        currentWave = totalWaves
        roomCleared = false
        waveLabel.Text = "Final wave"
        return
    end
    if text:lower():find("room cleared", 1, true) then
        roomCleared = true
        statusLabel.Text = "Room cleared"
        debugPrint("Raum abgeschlossen:", currentRoom)
    end
end

-- ============================================
-- DYNAMISCHE UI ERKENNUNG

-- ============================================
local observedLabels = {}

local function isNotificationLabel(obj)
    if not obj:IsA("TextLabel")
        or obj.Name ~= "text" then
        return false
    end
    local parent = obj.Parent
    return parent ~= nil
        and (
            parent.Name == "Blank"
            or parent.Name == "Success"
        )
end

local function observeLabel(label)
    if observedLabels[label] then
        return
    end
    observedLabels[label] = true
    label:GetPropertyChangedSignal("Text"):Connect(
        function()
            if gui.Parent then
                processNotification(label.Text)
            end
        end
    )
    processNotification(label.Text)
end

local function registerNotificationUI()
    local notifi = playerGui:FindFirstChild("NotifiUI")
    local notificationFrame =
        notifi and notifi:FindFirstChild("Frame")
    if not notificationFrame then
        return
    end
    for _, obj in ipairs(notificationFrame:GetDescendants()) do
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end
    notificationFrame.DescendantAdded:Connect(function(obj)
        if isNotificationLabel(obj) then
            observeLabel(obj)
        end
    end)
end
task.spawn(function()
    local notifi = playerGui:WaitForChild(
        "NotifiUI",
        15
    )
    if notifi then
        registerNotificationUI()
    else
        warn("[DUNGEON V4] NotifiUI nicht gefunden")
    end
end)

-- ============================================
-- GEGNER ERKENNEN

-- ============================================

local function enemyAlive(enemy)
    local folder = getEnemies()
    if not folder or not enemy
        or not enemy:IsDescendantOf(folder) then
        return false
    end
    local hp = enemy:GetAttribute("Health")
    return typeof(hp) == "number" and hp > 0
end

local function enemyPosition(enemy)
    if enemy and enemy:IsA("Model") then
        return enemy:GetPivot().Position
    end
    return nil
end

local function getNextEnemy()
    local root = getRoot()
    local folder = getEnemies()
    if not root or not folder then
        return nil
    end
    local nearest = nil
    local bestDistance = TARGET_SEARCH_RADIUS
    local now = os.clock()
    for _, enemy in ipairs(folder:GetChildren()) do
        if enemy:IsA("Model")
            and enemyAlive(enemy)
            and (skippedEnemies[enemy] or 0) <= now then
            local position = enemyPosition(enemy)
            if position then
                local distance =
                    horizontalDistance(
                        root.Position,
                        position
                    )
                if distance < bestDistance then
                    nearest = enemy
                    bestDistance = distance
                end
            end
        end
    end
    return nearest
end

-- ============================================
-- GEGNER MARKIEREN

-- ============================================

local function clearTarget()
    if currentHighlight then
        currentHighlight:Destroy()
        currentHighlight = nil
    end
    targetLabel.Text = "Target: -"
end

local function markEnemy(enemy)
    clearTarget()
    local highlight = Instance.new("Highlight")
    highlight.Name = "DungeonTarget"
    highlight.Adornee = enemy
    highlight.FillColor = Color3.fromRGB(255, 60, 60)
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.65
    highlight.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = gui
    currentHighlight = highlight
    targetLabel.Text =
        "Target: " .. enemy.Name:sub(1, 12)
end

-- ============================================
-- TELEPORT ZUM GEGNER

-- ============================================

local function teleportToEnemy(enemy)
    local character = getCharacter()
    local root = getRoot()
    local position = enemyPosition(enemy)
    if not character or not root or not position then
        return false
    end
    local horizontal = Vector3.new(
        root.Position.X - position.X,
        0,
        root.Position.Z - position.Z
    )
    local direction
    if horizontal.Magnitude > 0.01 then
        direction = horizontal.Unit
    else
        direction = -root.CFrame.LookVector
        direction = Vector3.new(
            direction.X,
            0,
            direction.Z
        )
        if direction.Magnitude < 0.01 then
            direction = Vector3.new(0, 0, 1)
        else
            direction = direction.Unit
        end
    end
    local destination =
        Vector3.new(
            position.X,
            root.Position.Y,
            position.Z
        ) + direction * ATTACK_DISTANCE
    local lookTarget = Vector3.new(
        position.X,
        destination.Y,
        position.Z
    )
    if (lookTarget - destination).Magnitude < 0.01 then
        return false
    end
    character:PivotTo(
        CFrame.lookAt(destination, lookTarget)
    )
    return true
end

-- ============================================
-- AUTOMATISCHER KAMPF

-- ============================================

local function fightEnemy(enemy, id)
    markEnemy(enemy)
    local lastAttack = -math.huge
    local lastTeleport = -math.huge
    local lastDamage = os.clock()
    local oldHealth = enemy:GetAttribute("Health")
    local attackPauseUntil = 0
    debugPrint("Kampf gestartet:", enemy.Name)
-- Einmal zum ersten Ziel teleportieren
    teleportToEnemy(enemy)
    while validSession(id)
        and enemyAlive(enemy)
        and not isDungeonComplete() do
        RunService.Heartbeat:Wait()
        if not validSession(id)
            or not enemyAlive(enemy) then
            break
        end
        local now = os.clock()
        local weapon = getWeapon()
        local root = getRoot()
        local humanoid = getHumanoid()
        if not weapon or not root or not humanoid
            or humanoid.Health <= 0 then
            statusLabel.Text = "Weapon or character missing"
            break
        end
        local hp = enemy:GetAttribute("Health")
        local maxHP = enemy:GetAttribute("MaxHealth")
        if typeof(hp) ~= "number" then
            break
        end
        healthLabel.Text =
            "HP: " .. math.floor(hp)
            .. " / " .. tostring(
                typeof(maxHP) == "number"
                and math.floor(maxHP)
                or "?"
            )
        if oldHealth and hp < oldHealth then
            lastDamage = now
        end
        oldHealth = hp
        local position = enemyPosition(enemy)
        if not position then
            break
        end
        local distance =
            horizontalDistance(root.Position, position)
-- Position nur bei Bedarf korrigieren.-- Keine Korrektur direkt waehrend Angriffspause.
        if now >= attackPauseUntil
            and now - lastTeleport >= REPOSITION_INTERVAL
            and distance > REPOSITION_DISTANCE then
            teleportToEnemy(enemy)
            lastTeleport = now
            statusLabel.Text = "Position adjusted"
        end
-- Angriff
        if distance <= REPOSITION_DISTANCE
            and weapon.Enabled
            and now - lastAttack >= ATTACK_INTERVAL
            and now >= attackPauseUntil then
-- Position unmittelbar vor Angriff korrigieren,-- aber nicht bei jedem Frame.
            if distance > ATTACK_DISTANCE + 0.4 then
                teleportToEnemy(enemy)
                task.wait(0.05)
            end
            if not validSession(id)
                or not enemyAlive(enemy) then
                break
            end
            weapon:Activate()
            lastAttack = os.clock()
            attackPauseUntil =
                lastAttack + ATTACK_STABILIZE
            attackCount = attackCount + 1
            attackLabel.Text =
                "Attacks: " .. attackCount
            statusLabel.Text = "Attacking enemy"
        end
-- Anti-Stuck bei ausbleibendem HP-Verlust
        if now - lastDamage >= NO_DAMAGE_TIMEOUT then
            skippedEnemies[enemy] =
                now + ENEMY_RETRY_DELAY
            debugPrint(
                "Kein HP-Fortschritt:",
                enemy.Name
            )
            break
        end
    end
    local ended = not enemyAlive(enemy)
    if validSession(id) then
        clearTarget()
        if ended then
            defeatedCount = defeatedCount + 1
            killLabel.Text =
                "Enemies defeated: " .. defeatedCount
        end
    end
    return ended
end

-- ============================================
-- PASSENDE OFFENE TÜR FINDEN

-- ============================================

local function getOpenDoor()
    local dungeonFolder = getDungeon()
    local root = getRoot()
    if not dungeonFolder or not root
        or currentRoom <= 0
        or currentRoom >= 18 then
        return nil
    end
    local nearestDoor = nil
    local nearestDistance = math.huge
-- Die Raumnummer im Ordner kann abweichen.-- Deshalb mehrere benachbarte Indizes erlauben.
    local minIndex = currentRoom + 1
    local maxIndex = currentRoom + 3
    for _, door in ipairs(dungeonFolder:GetDescendants()) do
        if door:IsA("BasePart")
            and door.Name == "Door"
            and door.CanCollide == false
            and not usedDoors[door] then
            local roomFolder = door.Parent
                and door.Parent.Parent
            local index = roomFolder
                and tonumber(
                    roomFolder.Name:match("^(%d+)_")
                )
            if index
                and index >= minIndex
                and index <= maxIndex then
                local distance = horizontalDistance(
                    root.Position,
                    door.Position
                )
                if distance < nearestDistance then
                    nearestDoor = door
                    nearestDistance = distance
                end
            end
        end
    end
    if nearestDoor then
        debugPrint(
            "Offene Ausgangstuer gefunden:",
            nearestDoor:GetFullName(),
            "Distanz:",
            math.floor(nearestDistance)
        )
    end
    return nearestDoor
end

local function enterFirstRoom(id)
    if not validSession(id) or currentRoom > 0 then
        return false
    end
    local dungeon = getDungeon()
    local character = getCharacter()
    local root = getRoot()
    if not dungeon or not character or not root then
        debugPrint("Dungeon oder Charakter fehlt")
        return false
    end
-- Exakte Eingangstuer suchen
    local startRoom = dungeon:FindFirstChild(
        "01_StartingRoom",
        true
    )
    if not startRoom then
        debugPrint("StartingRoom nicht gefunden")
        return false
    end
    local walls = startRoom:FindFirstChild("InvisWalls")
    local door = walls and walls:FindFirstChild("Door")
    if not door or not door:IsA("BasePart") then
        debugPrint("Eingangstuer nicht gefunden")
        return false
    end
    if door.CanCollide then
        debugPrint("Eingangstuer ist geschlossen")
        return false
    end
    local direction = Vector3.new(
        door.Position.X - root.Position.X,
        0,
        door.Position.Z - root.Position.Z
    )
    if direction.Magnitude < 0.1 then
        debugPrint("Richtung nicht bestimmbar")
        return false
    end
    direction = direction.Unit
    local destination = Vector3.new(
        door.Position.X,
        root.Position.Y,
        door.Position.Z
    ) + direction * DOOR_TELEPORT_DISTANCE
    debugPrint(
        "Teleportiere durch Dungeon-Eingang:",
        door:GetFullName()
    )
    character:PivotTo(
        CFrame.lookAt(
            destination,
            destination + direction
        )
    )
    transitionUntil = os.clock() + ROOM_TRANSITION_DELAY
-- Auf Raum 1 warten
    local started = os.clock()
    while validSession(id)
        and os.clock() - started < ROOM_CONFIRM_TIMEOUT do
        if currentRoom >= 1 then
            debugPrint(
                "Dungeon erfolgreich gestartet! Raum:",
                currentRoom
            )
            return true
        end
        task.wait(0.1)
    end
    debugPrint(
        "Eingang betreten, aber Raum 1 nicht bestaetigt"
    )
    return false
end

-- ============================================
-- TELEPORT DURCH OFFENE TÜR

-- ============================================

local function teleportThroughDoor(id)
    if not validSession(id)
        or currentRoom <= 0
        or currentRoom >= 18 then
        return false
    end
    local door = getOpenDoor()
    local root = getRoot()
    local character = getCharacter()
    if not door or not root or not character then
        return false
    end
    local roomBefore = currentRoom
    local horizontal = Vector3.new(
        door.Position.X - root.Position.X,
        0,
        door.Position.Z - root.Position.Z
    )
    if horizontal.Magnitude < 0.1 then
        return false
    end
    local direction = horizontal.Unit
    local destination =
        Vector3.new(
            door.Position.X,
            root.Position.Y,
            door.Position.Z
        ) + direction * DOOR_TELEPORT_DISTANCE
    statusLabel.Text =
        "Teleporting to room " .. (roomBefore + 1)
    debugPrint(
        "Teleport:",
        roomBefore,
        "->",
        roomBefore + 1,
        door:GetFullName()
    )
    if not validSession(id)
        or door.CanCollide then
        return false
    end
-- Charakter durch die geöffnete Tür teleportieren
character:PivotTo(
    CFrame.lookAt(
        destination,
        destination + direction
    )
)
-- Kampf während des Raumwechsels pausieren
transitionUntil = os.clock() + ROOM_TRANSITION_DELAY
debugPrint(
    "Raumwechsel-Sperre aktiviert:",
    ROOM_TRANSITION_DELAY,
    "Sekunden"
)
-- Auf neue Raumankuendigung warten
    local started = os.clock()
    while validSession(id)
        and os.clock() - started < ROOM_CONFIRM_TIMEOUT do
        if isDungeonComplete() then
            return false
        end
        if currentRoom > roomBefore then
            usedDoors[door] = true
            roomCleared = false
            debugPrint(
                "Raum erfolgreich betreten:",
                currentRoom
            )
            return true
        end
        task.wait(0.1)
    end
    debugPrint(
        "Raumwechsel nicht bestaetigt:",
        roomBefore
    )
    return false
end

-- ============================================
-- HAUPTSCHLEIFE

-- ============================================

local function resetDungeonRun(roomAlreadyDetected)
    completedRuns = completedRuns + 1
-- Raum 1 kann bereits gemeldet worden sein,-- bevor die Result-Anzeige verschwindet.
    currentRoom = roomAlreadyDetected and 1 or 0
    currentWave = 0
    totalWaves = 0
    roomCleared = false
    dungeonComplete = false
    waitingForRestart = false
    finalLootHandled = false
    restartRoomObserved = false
    replayAttempted = false
    replayAttemptAt = 0
    clearSceneReplay()
    skippedEnemies = {}
    usedDoors = {}
    lastRoomAttempt = 0
    transitionUntil = 0
    attackCount = 0
    defeatedCount = 0
    clearTarget()
    stopMovement()
    roomLabel.Text = roomAlreadyDetected
        and "Room: 1 / 18"
        or "Room: - / 18"
    waveLabel.Text = "Wave: -"
    targetLabel.Text = "Target: -"
    healthLabel.Text = "HP: -"
    killLabel.Text = "Enemies defeated: 0"
    attackLabel.Text = "Attacks: 0"
    statusLabel.Text = "Starting new run"
    debugPrint(
        "Dungeon-Reset abgeschlossen!",
        "Abgeschlossene Runs:",
        completedRuns
    )
end

local function getNearbyDrops(origin)
    local folder = workspace:FindFirstChild("WorldBits")
    local root = getRoot()
    if not folder or not root then
        return {}
    end
    origin = origin or root.Position
    local drops = {}
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") then
            local aura = model:FindFirstChild(
                "DropAura",
                true
            )
            local prompt = model:FindFirstChild(
                "ProximityPrompt",
                true
            )
            if aura
                and aura:IsA("BasePart")
                and aura:GetAttribute("DropAura") == true
                and prompt
                and prompt:IsA("ProximityPrompt")
                and prompt.ActionText == "Pick Up"
                and prompt.Enabled then
                local distance = (
                    aura.Position - origin
                ).Magnitude
                if distance <= LOOT_SEARCH_RADIUS then
                    table.insert(drops, {
                        model = model,
                        aura = aura,
                        prompt = prompt,
                        distance = distance
                    })
                end
            end
        end
    end
    table.sort(drops, function(a, b)
        return a.distance < b.distance
    end)
    return drops
end

local function collectDroppedItems(id)
    if not validSession(id) then
        return false
    end
    statusLabel.Text = "Checking for dropped items"
-- Warten, damit verzoegerte Drops erscheinen
    task.wait(LOOT_SETTLE_TIME)
    local started = os.clock()
    local attempted = {}
    local collected = 0
    -- Keep the search centered on the original room, even after teleporting.
    local originRoot = getRoot()
    local lootOrigin = originRoot and originRoot.Position or nil
    while validSession(id)
        and os.clock() - started < LOOT_TIMEOUT do
        local drops = getNearbyDrops(lootOrigin)
        local target = nil
-- Naechsten noch nicht versuchten Drop suchen
        for _, drop in ipairs(drops) do
            if (attempted[drop.model] or 0) < 2 then
                target = drop
                break
            end
        end
        if not target then
            break
        end
        attempted[target.model] = (attempted[target.model] or 0) + 1
        local character = getCharacter()
        local root = getRoot()
        if not character or not root then
            break
        end
        if not target.aura.Parent
            or not target.prompt.Parent then
            continue
        end
        local prompt = target.prompt
        local promptPart = prompt.Parent
        if not promptPart:IsA("BasePart") then
            debugPrint("Prompt ohne BasePart")
            continue
        end
-- Direkt neben den Pickup-Handle teleportieren
        local position = promptPart.Position
        local destination = Vector3.new(
            position.X,
            position.Y + 2,
            position.Z
        )
        debugPrint(
            "Sammle Drop:",
            target.model:GetAttribute("wbId")
                or target.model.Name
        )
        statusLabel.Text = "Collecting item..."
        character:PivotTo(
            CFrame.new(destination)
        )
-- Auf Interaktionsreichweite warten
        local pickupReady = false
        local waitStarted = os.clock()
        while validSession(id)
            and os.clock() - waitStarted < 2 do
            local currentRoot = getRoot()
            if not currentRoot
                or not prompt.Parent
                or not target.model.Parent then
                break
            end
            local distance = (
                currentRoot.Position - promptPart.Position
            ).Magnitude
            if prompt.Enabled
                and distance <= prompt.MaxActivationDistance then
                pickupReady = true
                break
            end
            task.wait(0.1)
        end
        if not validSession(id) then
            break
        end
        if pickupReady then
            local ok, err = pcall(function()
                if type(fireproximityprompt) ~= "function" then
                    error(
                        "fireproximityprompt nicht verfuegbar"
                    )
                end
                fireproximityprompt(prompt)
            end)
            if not ok then
                warn(
                    "[DUNGEON V4] Pickup fehlgeschlagen:",
                    err
                )
            end
-- Auf Verarbeitung des Pickups warten
            task.wait(LOOT_PICKUP_WAIT)
            if not target.model.Parent then
                collected = collected + 1
                debugPrint(
                    "Drop erfolgreich eingesammelt"
                )
            else
                debugPrint(
                    "Drop noch vorhanden:",
                    target.model.Name
                )
            end
        else
            debugPrint(
                "Pickup nicht bereit:",
                target.model.Name
            )
        end
    end
    debugPrint(
        "Loot-Phase beendet.",
        "Eingesammelt:",
        collected
    )
    statusLabel.Text = "Loot collection complete"
    return true
end

-- ============================================
-- UNIVERSAL AUTO REPLAY | EXECUTOR CAPABILITIES
-- ============================================
-- Detect the executor for diagnostics, but choose APIs by capability.
-- Executor names and APIs change between releases.
local function getExecutorInfo()
    local probes = {}
    if type(identifyexecutor) == "function" then
        table.insert(probes, identifyexecutor)
    end
    if type(getexecutorname) == "function" then
        table.insert(probes, getexecutorname)
    end
    for _, probe in ipairs(probes) do
        local ok, name, version = pcall(probe)
        if ok and type(name) == "string" and #name > 0 then
            return name, type(version) == "string" and version or ""
        end
    end
    return "Unknown", ""
end

local executorName, executorVersion = getExecutorInfo()
local executorNameLower = string.lower(executorName)
local function canUseNativeMouse()
    return type(mousemoveabs) == "function" and (
        type(mouse1click) == "function" or
        (type(mouse1press) == "function" and type(mouse1release) == "function")
    )
end

local function getNativeMouseFocus()
    local focusFn = nil
    if type(isrbxactive) == "function" then
        focusFn = isrbxactive
    elseif type(isgameactive) == "function" then
        focusFn = isgameactive
    elseif type(iswindowactive) == "function" then
        focusFn = iswindowactive
    end
    if focusFn then
        local ok, isActive = pcall(focusFn)
        if ok and isActive == false then
            return false
        end
    end
    return true
end

local function getReplayButton()
    local hud = playerGui:FindFirstChild("DungeonHud")
    local result = hud and hud:FindFirstChild("Result")
    local again = result and result:FindFirstChild("Again")
    if not again or not again:IsA("GuiButton") then
        return nil, "Run again button was not found"
    end
    if not again.Visible or not again.Active or not again.Interactable then
        return nil, "Run again button is not clickable"
    end
    return again, nil
end

-- ============================================
-- PRECISE REPLAY CLICK (Solara/desktop executors)
-- ============================================
-- Roblox AbsolutePosition is relative to CoreUISafeInsets. Native mouse
-- coordinates and UserInputService:GetMouseLocation() use screen pixels.
-- Add the top-left inset exactly once regardless of IgnoreGuiInset.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local function replayButtonCenter(again)
    local pos = again.AbsolutePosition
    local size = again.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then
        return nil, nil, "Run again button is not on-screen"
    end
    local center = pos + size * 0.5
    local ok, inset = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if not ok or typeof(inset) ~= "Vector2" then
        inset = Vector2.new(0, 0)
    end
    local x = math.floor(center.X + inset.X + 0.5)
    local y = math.floor(center.Y + inset.Y + 0.5)
    local camera = workspace.CurrentCamera
    if camera then
        local viewport = camera.ViewportSize
        if x < 0 or y < 0 or x >= viewport.X or y >= viewport.Y then
            return nil, nil, "Run again button is outside the viewport"
        end
    end
    return x, y, nil
end

local function readActualMouse()
    local ok, p = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if ok and typeof(p) == "Vector2" then
        return p
    end
    return nil
end

-- Move first, measure where the cursor actually landed, then correct any
-- window/inset offset BEFORE pressing. No probing clicks are performed.
local function moveToReplayCenter(x, y, again)
    local target = Vector2.new(x, y)
    local size = again.AbsoluteSize
    local toleranceX = math.max(5, math.min(16, size.X * 0.14))
    local toleranceY = math.max(5, math.min(16, size.Y * 0.14))

    mousemoveabs(x, y)
    task.wait(0.12)

    local last = readActualMouse()
    if not last then
        -- On executors where location cannot be read, preserve the normal
        -- native mouse behavior, but report that alignment was unverified.
        return true, "Mouse position unavailable; alignment unverified"
    end

    for step = 1, 3 do
        local dx = target.X - last.X
        local dy = target.Y - last.Y
        if math.abs(dx) <= toleranceX and math.abs(dy) <= toleranceY then
            return true, string.format(
                "Aligned at (%d,%d), target (%d,%d), correction steps %d",
                math.floor(last.X + 0.5), math.floor(last.Y + 0.5),
                x, y, step - 1
            )
        end

        if step == 3 then break end

        debugPrint(string.format(
            "Replay mouse offset: dx=%.1f dy=%.1f; adjusting",
            dx, dy
        ))
        local moved = pcall(function()
            if type(mousemoverel) == "function" then
                mousemoverel(math.floor(dx + (dx >= 0 and 0.5 or -0.5)),
                             math.floor(dy + (dy >= 0 and 0.5 or -0.5)))
            else
                -- Fallback if the executor only provides absolute movement.
                mousemoveabs(math.floor(x + dx + 0.5),
                             math.floor(y + dy + 0.5))
            end
        end)
        if not moved then
            return false, "Cursor correction API failed"
        end
        task.wait(0.12)
        local updated = readActualMouse()
        if not updated then
            return false, "Cursor location became unavailable"
        end
        last = updated
    end

    return false, string.format(
        "Cursor missed button center: target (%d,%d), actual (%d,%d)",
        x, y, math.floor(last.X + 0.5), math.floor(last.Y + 0.5)
    )
end

-- A single verified native press-and-release. Never spam clicks or retry
-- after input was dispatched, because each successful restart costs an item.
local function tryNativeMouseReplay(id, again)
    if not canUseNativeMouse() then
        return false, "Native mouse API not available"
    end
    if not getNativeMouseFocus() then
        return false, "Roblox is not the focused window"
    end

    local wasVisible = frame.Visible
    local pressed = false
    local inputStarted = false
    local movedDetails = "not attempted"
    local ok, err = pcall(function()
        frame.Visible = false
        task.wait(0.12)
        if not validSession(id) or not isDungeonComplete()
            or not again.Visible or not again.Interactable then
            error("Result screen changed before clicking")
        end

        -- Recalculate AFTER hiding the overlay, in case the GUI moved.
        local x, y, locationError = replayButtonCenter(again)
        if not x then error(locationError) end
        local aligned, details = moveToReplayCenter(x, y, again)
        movedDetails = details
        debugPrint("Replay cursor:", details)
        if not aligned then error(details) end

        if not validSession(id) or not isDungeonComplete()
            or not getNativeMouseFocus() then
            error("Replay stopped: result closed or window lost focus")
        end

        if type(mouse1press) == "function" and
            type(mouse1release) == "function" then
            mouse1press()
            inputStarted = true
            pressed = true
            task.wait(0.11)
            mouse1release()
            pressed = false
        else
            inputStarted = true
            mouse1click()
        end
        task.wait(0.15)
    end)

    if pressed then pcall(mouse1release) end
    frame.Visible = wasVisible and gui.Parent ~= nil

    if not ok then
        if inputStarted then
            return true, "Mouse input possibly sent: " .. tostring(err)
        end
        return false, "Mouse alignment/press failed: " .. tostring(err)
    end
    return true, "Single native click sent; " .. movedDetails
end

-- Direct signal activation for executors supporting firesignal.
-- This does not guarantee that game logic will accept a missing InputObject.
local function chooseReplaySignal(again)
    if type(getconnections) == "function" then
        local okA, activated = pcall(getconnections, again.Activated)
        local okM, clicked = pcall(getconnections, again.MouseButton1Click)
        if okA and type(activated) == "table" and #activated > 0 then
            return again.Activated, "Activated", activated
        end
        if okM and type(clicked) == "table" and #clicked > 0 then
            return again.MouseButton1Click, "MouseButton1Click", clicked
        end
    end
    return again.Activated, "Activated", nil
end

local function tryFireSignalReplay(_, again)
    if type(firesignal) ~= "function" then
        return false, "firesignal API not available"
    end
    local signal, eventName, listeners = chooseReplaySignal(again)
    if type(getconnections) == "function" and listeners == nil then
        -- If introspection works and reports no handlers for either event,
        -- use a real mouse action instead of treating an empty signal as success.
        local aOk, aList = pcall(getconnections, again.Activated)
        local mOk, mList = pcall(getconnections, again.MouseButton1Click)
        if aOk and mOk and type(aList) == "table" and type(mList) == "table"
            and #aList == 0 and #mList == 0 then
            return false, "No accessible replay button listeners"
        end
    end
    local ok, err = pcall(function()
        if eventName == "Activated" then
            firesignal(signal, nil, 0)
        else
            firesignal(signal)
        end
    end)
    if not ok then
        -- It is impossible to know whether any listener ran before the error.
        return true, "Signal dispatch may have partially succeeded: " .. tostring(err)
    end
    return true, "firesignal(" .. eventName .. ") dispatched"
end

-- Some executors have getconnections but no firesignal.
local function tryConnectionsReplay(_, again)
    if type(getconnections) ~= "function" then
        return false, "getconnections API not available"
    end
    local _, eventName, list = chooseReplaySignal(again)
    if type(list) ~= "table" or #list == 0 then
        return false, "No accessible button event connections"
    end
    local count = 0
    for _, conn in ipairs(list) do
        if conn.Enabled ~= false then
            local ok = pcall(function()
                if type(conn.Fire) == "function" then
                    if eventName == "Activated" then
                        conn:Fire(nil, 0)
                    else
                        conn:Fire()
                    end
                elseif type(conn.Function) == "function" then
                    if eventName == "Activated" then
                        conn.Function(nil, 0)
                    else
                        conn.Function()
                    end
                else
                    error("Unusable connection")
                end
            end)
            if ok then count = count + 1 end
        end
    end
    if count == 0 then
        return false, "Button connections could not be executed"
    end
    return true, "Fired " .. count .. " " .. eventName .. " connection(s)"
end

-- Last-resort API for runtimes which expose VirtualInputManager only.
-- This previously failed in some executors, so it is NOT the first choice.
local function tryVirtualInputReplay(id, again)
    local x, y, err = replayButtonCenter(again)
    if not x then return false, err end
    local okService, vim = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not okService or not vim then
        return false, "VirtualInputManager is unavailable"
    end
    local wasVisible = frame.Visible
    local inputStarted = false
    local ok, failure = pcall(function()
        frame.Visible = false
        task.wait(0.1)
        if not validSession(id) or not isDungeonComplete() then
            error("Result screen changed before clicking")
        end
        vim:SendMouseMoveEvent(x, y, game)
        task.wait(0.09)
        inputStarted = true
        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.09)
        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        task.wait(0.1)
    end)
    frame.Visible = wasVisible and gui.Parent ~= nil
    if not ok then
        if inputStarted then
            return true, "VirtualInputManager may have sent input: " .. tostring(failure)
        end
        return false, "VirtualInputManager failed: " .. tostring(failure)
    end
    return true, "VirtualInputManager click dispatched"
end

local function replayMethodOrder()
    -- Name-based preference is only a hint; functionality is checked at call.
    -- Solara: native cursor. Potassium: fire signal first, then native cursor.
    -- Unknown executor: detect and use whichever API is available.
    if executorNameLower:find("potassium", 1, true) then
        -- Prefer the previously used Potassium signal API. The generic native
        -- mouse path can report input dispatched even when it missed the GUI.
        return { "signal", "native", "connections", "virtual" }
    elseif executorNameLower:find("solara", 1, true) then
        return { "native", "virtual", "signal", "connections" }
    end
    return { "native", "signal", "connections", "virtual" }
end

local replayMethods = {
    native = tryNativeMouseReplay,
    signal = tryFireSignalReplay,
    connections = tryConnectionsReplay,
    virtual = tryVirtualInputReplay,
}

local function printReplayCapabilities()
    local versionText = executorVersion ~= "" and (" " .. executorVersion) or ""
    debugPrint("Executor detected:", executorName .. versionText)
    debugPrint("Replay API:",
        "nativeMouse=" .. tostring(canUseNativeMouse()),
        "firesignal=" .. tostring(type(firesignal) == "function"),
        "getconnections=" .. tostring(type(getconnections) == "function"))
    debugPrint("Replay preference:", table.concat(replayMethodOrder(), " -> "))
end
printReplayCapabilities()

-- One actual activation attempt per endscreen. If an API call errors BEFORE
-- dispatching input, the next supported method is tried automatically.
-- If input might have been sent, we wait for the game or require manual replay.
local function attemptAutoReplay(id)
    if not validSession(id) or not isDungeonComplete() then
        return false, "Endscreen not ready"
    end
    if accessGui.Enabled then
        return false, "Close the key window before replay"
    end
    local again, buttonError = getReplayButton()
    if not again then
        return false, buttonError
    end
    local failures = {}
    for _, method in ipairs(replayMethodOrder()) do
        if not validSession(id) or not isDungeonComplete() then
            return false, "Endscreen changed while choosing replay method"
        end
        local success, sent, reason = pcall(replayMethods[method], id, again)
        if success and sent then
            debugPrint("Auto Replay input dispatched by:", method, reason,
                "(not yet confirmed by dungeon)")
            return true, method .. ": " .. tostring(reason)
        end
        local failure = tostring(success and reason or sent)
        debugPrint("Auto Replay method skipped/failed:", method, failure)
        table.insert(failures, method .. "=" .. failure)
    end
    return false, "No usable method: " .. table.concat(failures, "; ")
end

local function startSpeedrun(id)
    debugPrint("Dungeon Speedrun started!")
    while validSession(id) do
        if isDungeonComplete() then
            if not waitingForRestart then
                waitingForRestart = true
                restartRoomObserved = false
                stopMovement()
                clearTarget()
                replayAttempted = false
                replayAttemptAt = 0
                -- Scene exit might already have arrived; do not clear it here.
                statusLabel.Text = "Dungeon cleared - waiting for restart"
                debugPrint("Dungeon cleared; waiting for restart")
            end
            -- Collect any final boss drops before requesting another run.
            if not finalLootHandled then
                finalLootHandled = true
                collectDroppedItems(id)
            end
            -- A Scene event confirms a restart. It never triggers one.
            -- Dispatch at most ONE input attempt; manual Run again stays available.
            local endscreenHiddenAt = nil
            local replayReady = false
            while validSession(id) do
                local completeScreenVisible = isDungeonComplete()
                local now = os.clock()

                if sceneEventsAvailable and sceneReplay.otherExit then
                    statusLabel.Text = "Dungeon exited without replay - stopped"
                    debugPrint("[SCENE] Left dungeon without Run again; stopping")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and sceneReplay.gate
                    and not completeScreenVisible then
                    replayReady = true
                    break
                end

                if not completeScreenVisible then
                    if not sceneEventsAvailable then
                        -- If the Scene listener cannot be installed, retain
                        -- the old endscreen-based fallback as a last resort.
                        task.wait(1)
                        replayReady = not isDungeonComplete()
                        break
                    end
                    endscreenHiddenAt = endscreenHiddenAt or now
                else
                    endscreenHiddenAt = nil
                end

                if completeScreenVisible and autoReplayEnabled
                    and not replayAttempted and not sceneReplay.exit then
                    replayAttempted = true
                    replayAttemptAt = os.clock()
                    local sent, reason = attemptAutoReplay(id)
                    debugPrint("Auto Replay attempt:", sent, reason)
                    if sent then
                        statusLabel.Text = "Replay input sent - awaiting Scene confirmation"
                    else
                        statusLabel.Text = "Auto Replay failed - click Run again"
                    end
                end

                -- Never automatically click again merely because Scene is slow.
                if replayAttempted and replayAttemptAt > 0
                    and not sceneReplay.exit
                    and now - replayAttemptAt >= REPLAY_CONFIRM_TIMEOUT then
                    statusLabel.Text = "Replay not confirmed - click Run again"
                    replayAttemptAt = 0
                end

                if sceneEventsAvailable and sceneReplay.exit
                    and not sceneReplay.gate
                    and now - sceneReplay.exitAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart received but gate not ready - stopped"
                    debugPrint("[SCENE] Timed out waiting for arrive/gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                if sceneEventsAvailable and endscreenHiddenAt
                    and not sceneReplay.gate
                    and now - endscreenHiddenAt >= SCENE_RESTART_WAIT_SECONDS then
                    statusLabel.Text = "Restart unconfirmed by Scene - stopped"
                    debugPrint("[SCENE] Endscreen vanished without confirmed gate")
                    running = false
                    sessionId = sessionId + 1
                    setButton(false)
                    break
                end

                task.wait(0.2)
            end
            if not validSession(id) then break end
            if not replayReady then
                statusLabel.Text = "Replay was not confirmed"
                break
            end

            -- New dungeon confirmed by the server: exit -> arrive -> gate.
            -- Room 1 may already be reported by a notification.
            local roomAlreadyDetected = restartRoomObserved and currentRoom == 1
            resetDungeonRun(roomAlreadyDetected)
            setButton(true)
            debugPrint("[SCENE] New dungeon confirmed; resuming")
            continue
        end
        if dismissLootPopup() then
            debugPrint("NEW LOOT bestaetigt")
        end
        local weapon = getWeapon()
        local humanoid = getHumanoid()
        if not weapon then
            statusLabel.Text = "Equip a weapon"
            task.wait(0.4)
        elseif not humanoid or humanoid.Health <= 0 then
            statusLabel.Text = "Character not ready"
            task.wait(0.4)
        elseif AUTO_ENTER_FIRST_ROOM and currentRoom == 0 then
            statusLabel.Text = "Entering dungeon..."
            enterFirstRoom(id)
            task.wait(0.5)
        elseif os.clock() < transitionUntil then
            statusLabel.Text = "Confirming room transition"
            task.wait(0.1)
        else
            local enemy = getNextEnemy()
            if enemy then
                fightEnemy(enemy, id)
            elseif currentRoom > 0 and currentRoom < 18 and getOpenDoor() then
            if os.clock() - lastRoomAttempt
                >= ROOM_RETRY_DELAY then
                lastRoomAttempt = os.clock()
-- Zuerst alle erreichbaren Drops einsammeln
                collectDroppedItems(id)
-- Danach erst zum nächsten Raum
                if validSession(id) then
                    teleportThroughDoor(id)
                end
            end
                task.wait(0.2)
            else
                statusLabel.Text = "Waiting for enemies / door"
                task.wait(0.25)
            end
        end
        task.wait(0.03)
    end
    if sessionId == id then
        clearTarget()
        stopMovement()
        statusLabel.Text = "Speedrun stopped"
    end
    debugPrint("Dungeon Speedrun beendet")
end

-- ============================================
-- AN / AUS BUTTON

-- ============================================
onSpeedrunToggle = function(enabled)
    if enabled and selectedDungeonId ~= "halloween" then
        setButton(false)
        statusLabel.Text = "Select Halloween Dungeon before starting"
        return
    end
    if enabled and (not accessGranted or os.clock() >= accessDeadline) then
        setButton(false)
        accessGui.Enabled = true
        accessStatus.Text = "Please verify a valid key."
        return
    end
    if running == enabled then return end
    running = enabled
    sessionId = sessionId + 1
    if running then
        dungeonComplete = false
        waitingForRestart = false
        replayAttempted = false
        replayAttemptAt = 0
        clearSceneReplay()
        skippedEnemies = {}
        usedDoors = {}
        lastRoomAttempt = 0
        setButton(true)
        statusLabel.Text = "Speedrun started"
        local id = sessionId
        task.spawn(startSpeedrun, id)
    else
        setButton(false)
        statusLabel.Text = "Speedrun stopped"
        stopMovement()
        clearTarget()
    end
end

print("Poly Loot Dungeon Speedrun V5 PATCHED + OasisUI dungeon selector + 24h Key loaded!")
