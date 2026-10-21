-- tea.cc — cast-level hitbox work, built on the SimpleCast source
--
-- What the source proves:
--   * Fire() builds an active cast and returns it; the stepping loop runs on
--     RunService.Heartbeat INSIDE the client library, walking _activeCasts
--   * every cast carries data2.RaycastParams, handed in by the game's weapon
--     code, and that object decides what the cast is allowed to hit
--   * stepCast itself is irreducible bytecode, so its validation is opaque
--
-- That means the client owns the sweep and the game owns the filter. Two
-- levers follow, both here:
--   1. permissive params - replace the supplied RaycastParams with an open one
--   2. shadow bodies     - a big query-only part on each target, so anything
--                          the client sweeps finds flesh instead of air
--
--   hbs6Log()              print what the game actually passes to Fire()
--   hbs6Permissive(true)   swap in open RaycastParams
--   hbs6Box(true)          weld a 12-stud query box onto every other player
--   hbs6Stop()             restore module + remove boxes

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H6 = getgenv().hbs6 or {
    log = false,
    permissive = false,
    box = false,
    boxSize = 12,
    logLimit = 6,
}
getgenv().hbs6 = H6

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs6Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs6"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 204

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(760, 400)
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
    title.Text = "  tea.cc — hbs6 cast hitbox"
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
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 340))
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

-- ------------------------------------------------------------- cast module --

local castModule = nil
local castOriginal = nil
local logged = 0

local function openParams()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    local character = Players.LocalPlayer.Character
    if character then table.insert(ignore, character) end
    local camera = workspace.CurrentCamera
    if camera then table.insert(ignore, camera) end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    pcall(function() params.RespectCanCollide = false end)
    pcall(function() params.CollisionGroup = "Default" end)
    return params
end

local function describeFilter(params)
    if typeof(params) ~= "RaycastParams" then
        return "params=" .. typeof(params)
    end
    local names = {}
    local list = params.FilterDescendantsInstances
    for index = 1, math.min(#list, 4) do
        local item = list[index]
        names[index] = (typeof(item) == "Instance") and item.Name or typeof(item)
    end
    return string.format("%s [%d] %s",
        tostring(params.FilterType):gsub("Enum.RaycastFilterType.", ""),
        #list, table.concat(names, ","))
end

local function castInstall()
    local module = ReplicatedStorage:FindFirstChild("SimpleCast")
    if not module or not module:IsA("ModuleScript") then
        return false, "no SimpleCast in ReplicatedStorage"
    end

    local ok, cast = pcall(require, module)
    if not ok or type(cast) ~= "table" or type(cast.Fire) ~= "function" then
        return false, "SimpleCast.Fire unavailable"
    end

    castModule = cast
    castOriginal = cast.Fire

    cast.Fire = function(self, origin, direction, speed, options)
        local cfg = getgenv().hbs6

        if cfg and cfg.log and logged < (cfg.logLimit or 6) and type(options) == "table" then
            logged = logged + 1
            local keys = {}
            for key in pairs(options) do keys[#keys + 1] = tostring(key) end
            table.sort(keys)
            say(string.format("Fire  speed %s  spread %s  max %s",
                tostring(speed),
                tostring(options.SpreadAngle),
                tostring(options.MaxDistance)))
            say("  params " .. describeFilter(options.RaycastParams))
            say("  keys   " .. table.concat(keys, ", "))
        end

        if cfg and cfg.permissive and type(options) == "table" then
            local opened = setmetatable({}, { __index = options })
            opened.RaycastParams = openParams()
            return castOriginal(self, origin, direction, speed, opened)
        end

        return castOriginal(self, origin, direction, speed, options)
    end

    return true
end

getgenv().hbs6Log = function()
    if not castModule then
        local ok, why = castInstall()
        if not ok then say("!! " .. tostring(why)) return end
    end
    H6.log = true
    H6.logLimit = 12
    logged = 0
    say("logging the next Fire calls — take a shot")
end

getgenv().hbs6Permissive = function(on)
    if not castModule then
        local ok, why = castInstall()
        if not ok then say("!! " .. tostring(why)) return end
    end
    H6.permissive = on ~= false
    say("permissive params " .. (H6.permissive and "ON" or "OFF"))
end

-- ------------------------------------------------------------ shadow bodies --

local function ensureBox(player)
    local character = player.Character
    if not character then return end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end

    local size = math.clamp(tonumber(H6.boxSize) or 12, 2, 40)
    local box = character:FindFirstChild("__tea_hitbox")

    if not box then
        box = Instance.new("Part")
        box.Name = "__tea_hitbox"
        box.Material = Enum.Material.SmoothPlastic
        box.Anchored = false
        box.Massless = true
        box.CanCollide = false
        box.CanTouch = false
        box.CanQuery = true
        box.CastShadow = false
        box.Transparency = 0.85
        box.Color = Color3.fromRGB(144, 255, 144)
        box.CFrame = root.CFrame
        box.Parent = character

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = root
        weld.Part1 = box
        weld.Parent = box
    end

    box.Size = Vector3.new(size, size, size)
end

local function clearBoxes()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local box = character and character:FindFirstChild("__tea_hitbox")
        if box then pcall(function() box:Destroy() end) end
    end
end

task.spawn(function()
    while true do
        task.wait(0.3)
        if H6.box then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= Players.LocalPlayer then ensureBox(player) end
            end
        end
    end
end)

getgenv().hbs6Box = function(on)
    H6.box = on ~= false
    if not H6.box then clearBoxes() end
    say("shadow bodies " .. (H6.box and "ON" or "OFF")
        .. "  size " .. tostring(H6.boxSize))
end

-- ----------------------------------------------------------------- teardown --

getgenv().hbs6Stop = function()
    if castModule and castOriginal then
        pcall(function() castModule.Fire = castOriginal end)
        say("SimpleCast.Fire restored")
    end
    castModule = nil
    castOriginal = nil
    H6.permissive = false
    H6.log = false
    H6.box = false
    clearBoxes()
end

say("tea.cc hbs6 loaded  —  RightShift toggles")
say("1) hbs6Log()   2) hbs6Permissive(true)   3) hbs6Box(true)")
