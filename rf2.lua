-- tea.cc — rapid fire for a queued-cast weapon
--
-- Straight from the SimpleCast source: Fire() does not shoot, it appends a
-- cast record to _activeCasts, and the module steps each record on Heartbeat
-- until it dies. A weapon that will not fire twice is waiting for its previous
-- cast to leave that table. So stacking extra Fire() calls is exactly the wrong
-- move — it fills the queue and wedges the gun.
--
-- Two levers that respect the queue instead:
--
--   1. speed     - multiply the cast's Velocity, so it covers MaxDistance in
--                  fewer Heartbeats and leaves the queue sooner
--   2. spam      - while the real left button is held, inject extra pulls at a
--                  chosen rate, so a semi-auto trigger sees a torn finger
--
--   rf2Fast(true)      velocity x3, MaxDistance capped at 300
--   rf2Fast(true, 5)   velocity x5
--   rf2Spam(true)      extra pulls while LMB is held
--   rf2Stop()          restore the module

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")

local RF = getgenv().rf2 or {
    enabled = false,
    speed = 3,
    maxDistance = 300,
    spam = false,
    rate = 30,
}
getgenv().rf2 = RF

-- ------------------------------------------------------------------- panel --

local panel = getgenv().rf2Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_rf2"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 206

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(560, 240)
    frame.Position = UDim2.fromOffset(30, 60)
    frame.BackgroundColor3 = Color3.fromRGB(12, 14, 12)
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(169, 209, 142)
    stroke.Thickness = 1
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 0, 26)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(169, 209, 142)
    title.Text = "  tea.cc — rf2"
    title.Parent = frame

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(26, 22)
    close.Position = UDim2.new(1, -32, 0, 2)
    close.BackgroundColor3 = Color3.fromRGB(24, 28, 24)
    close.BorderSizePixel = 0
    close.Font = Enum.Font.Code
    close.TextSize = 14
    close.TextColor3 = Color3.fromRGB(169, 209, 142)
    close.Text = "x"
    close.Parent = frame
    close.MouseButton1Click:Connect(function() frame.Visible = false end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -34)
    scroll.Position = UDim2.fromOffset(6, 30)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    panel = frame
    output = scroll
    return panel, output
end

local function say(text, tint)
    text = tostring(text)
    pcall(print, text)

    local frame, scroll = buildPanel()
    if not scroll then return end

    lineCount = lineCount + 1
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -8, 0, 16)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = tint or Color3.fromRGB(220, 226, 218)
    label.Text = text
    label.LayoutOrder = lineCount
    label.Parent = scroll

    scroll.CanvasSize = UDim2.new(0, 0, 0, lineCount * 18 + 8)
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 180))
    frame.Visible = true
end

task.spawn(function()
    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            local frame = buildPanel()
            if frame then frame.Visible = not frame.Visible end
        end
    end)
end)

-- -------------------------------------------------------------------- module --

local castModule = nil
local castOriginal = nil

local function getModule()
    if castModule then return castModule end
    local module = ReplicatedStorage:FindFirstChild("SimpleCast")
    if not module or not module:IsA("ModuleScript") then return nil end
    local ok, cast = pcall(require, module)
    if ok and type(cast) == "table" and type(cast.Fire) == "function" then
        castModule = cast
        return cast
    end
    return nil
end

local function queueDepth()
    local cast = getModule()
    if not cast then return -1 end
    local instances = cast._instances
    if type(instances) ~= "table" then return -1 end

    local total = 0
    for _, instance in ipairs(instances) do
        local casts = instance._activeCasts
        if type(casts) == "table" then total = total + #casts end
    end
    return total
end

local function install()
    local cast = getModule()
    if not cast then return false, "SimpleCast not found" end
    if castOriginal then return true end

    castOriginal = cast.Fire

    cast.Fire = function(self, origin, direction, speed, options)
        local result = castOriginal(self, origin, direction, speed, options)

        local cfg = getgenv().rf2
        if not cfg or not cfg.enabled or type(result) ~= "table" then
            return result
        end

        if typeof(result.Velocity) == "Vector3" then
            local mult = math.clamp(tonumber(cfg.speed) or 3, 1, 12)
            result.Velocity = result.Velocity * mult
        end

        if tonumber(cfg.maxDistance) then
            local cap = math.clamp(tonumber(cfg.maxDistance), 20, 2000)
            if not result.MaxDistance or result.MaxDistance > cap then
                result.MaxDistance = cap
            end
        end

        return result
    end

    return true
end

getgenv().rf2Fast = function(on, speed)
    local ok, why = install()
    if not ok then
        say("!! " .. tostring(why), Color3.fromRGB(255, 120, 120))
        return
    end

    RF.enabled = on ~= false
    if tonumber(speed) then
        RF.speed = math.clamp(tonumber(speed), 1, 12)
    end

    say(string.format("fast casts %s · velocity x%.1f · max %d studs",
        RF.enabled and "ON" or "OFF", RF.speed, RF.maxDistance))
    say("queue now: " .. tostring(queueDepth()))
end

-- ---------------------------------------------------------------- lmb spam --

local nextPull = 0

local function click()
    local mouse = UIS:GetMouseLocation()
    pcall(function()
        VIM:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 1)
        VIM:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 1)
    end)
end

RunService.Heartbeat:Connect(function()
    if not RF.spam then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    if os.clock() < nextPull then return end

    local rate = math.clamp(tonumber(RF.rate) or 30, 1, 60)
    nextPull = os.clock() + (1 / rate)
    click()
end)

getgenv().rf2Spam = function(on)
    RF.spam = on ~= false
    say("lmb spam " .. (RF.spam and ("ON · " .. tostring(RF.rate) .. "/s") or "OFF"))
    if RF.spam then
        say("hold left mouse — extra pulls fire on top of your own")
    end
end

getgenv().rf2Stop = function()
    if castModule and castOriginal then
        pcall(function() castModule.Fire = castOriginal end)
        say("SimpleCast.Fire restored")
    end
    castModule = nil
    castOriginal = nil
    RF.enabled = false
    RF.spam = false
end

say("tea.cc rf2 loaded  —  RightShift toggles")
say("run: rf2Fast(true)  then  rf2Spam(true)")
