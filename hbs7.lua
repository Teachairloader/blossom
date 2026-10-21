-- tea.cc — unstick the gun and restore the cast module
--
-- Symptom: one bullet, then the weapon refuses to fire until re-equipped. That
-- is the cast queue wedging, not the gun's cooldown. SimpleCast keeps every
-- live projectile in `_activeCasts` and only lets the weapon fire again once
-- its cast leaves that table. A wrapper that returns early, errors mid-call or
-- swaps in a proxy options table can leave a cast in there forever.
--
-- So this build hooks nothing. It finds the original Fire through the wrapper's
-- upvalues, puts it back, empties the stuck queues, and removes every part any
-- earlier build left behind.
--
--   hbs7Restore()     restore Fire + clear casts + remove boxes
--   hbs7Casts()       show live cast counts per instance
--   hbs7Box(12)       hook-free shadow body, for one last honest test
--   hbs7Stop()        remove boxes only

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H7 = getgenv().hbs7 or { boxSize = 12, visible = false }
getgenv().hbs7 = H7

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs7Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs7"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 205

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(700, 340)
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
    title.Text = "  tea.cc — hbs7 repair"
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
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 280))
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

-- --------------------------------------------------------------- cast repair --

local function getModule()
    local module = ReplicatedStorage:FindFirstChild("SimpleCast")
    if not module or not module:IsA("ModuleScript") then return nil end
    local ok, cast = pcall(require, module)
    if ok and type(cast) == "table" then return cast end
    return nil
end

-- The wrapper we installed is still sitting in cast.Fire even after the script
-- that made it stopped running. Its original lives in an upvalue; find the
-- function-valued upvalue that is not itself and put it back.
local function recoverOriginal(wrapper)
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
        return nil, "debug.getupvalue unavailable"
    end

    local candidates = {}
    for index = 1, 32 do
        local name, value = debug.getupvalue(wrapper, index)
        if not name then break end
        if type(value) == "function" and value ~= wrapper then
            candidates[#candidates + 1] = { name = name, fn = value }
        end
    end

    for _, candidate in ipairs(candidates) do
        local lower = candidate.name:lower()
        if lower:find("original", 1, true) or lower:find("fire", 1, true)
            or lower:find("old", 1, true) then
            return candidate.fn
        end
    end

    if #candidates == 1 then return candidates[1].fn end
    return nil, ("%d candidate upvalues, none named like an original"):format(#candidates)
end

local function clearQueues(cast)
    local cleared = 0
    local instances = cast._instances
    if type(instances) ~= "table" then return 0 end

    for _, instance in ipairs(instances) do
        local casts = instance._activeCasts
        if type(casts) == "table" and #casts > 0 then
            cleared = cleared + #casts
            instance._activeCasts = {}
        end
    end
    return cleared
end

getgenv().hbs7Casts = function()
    local cast = getModule()
    if not cast then
        say("!! SimpleCast not found")
        return
    end

    local instances = cast._instances
    say(string.format("-- %d cast instance(s)", type(instances) == "table" and #instances or 0),
        Color3.fromRGB(169, 209, 142))

    if type(instances) == "table" then
        for index, instance in ipairs(instances) do
            local casts = instance._activeCasts
            say(string.format("  [%d] active casts: %d", index,
                type(casts) == "table" and #casts or -1))
        end
    end
end

getgenv().hbs7Restore = function()
    local cast = getModule()
    if not cast then
        say("!! SimpleCast not found", Color3.fromRGB(255, 120, 120))
        return
    end

    local cleared = clearQueues(cast)
    say("cleared " .. cleared .. " stuck cast(s)")

    local fire = cast.Fire
    local name = "hooked"
    local recovered, why = recoverOriginal(fire)

    if recovered then
        cast.Fire = recovered
        say("SimpleCast.Fire restored from wrapper upvalue",
            Color3.fromRGB(200, 220, 190))
    else
        say("could not recover Fire: " .. tostring(why), Color3.fromRGB(255, 200, 120))
        say("rejoin once — that clears the wrapper for good")
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local box = character and character:FindFirstChild("__tea_hitbox")
        if box then pcall(function() box:Destroy() end) end
    end

    say("boxes removed · test the weapon now", Color3.fromRGB(200, 220, 190))
end

-- ------------------------------------------------------- hook-free body test --

local function ensureBox(player)
    local character = player.Character
    if not character then return end

    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end

    local size = math.clamp(tonumber(H7.boxSize) or 12, 2, 40)
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
        box.CFrame = root.CFrame
        box.Parent = character

        local weld = Instance.new("WeldConstraint")
        weld.Part0 = root
        weld.Part1 = box
        weld.Parent = box
    end

    box.Size = Vector3.new(size, size, size)
    box.Transparency = H7.visible and 0.6 or 1
    box.Color = Color3.fromRGB(144, 255, 144)
end

getgenv().hbs7Box = function(size, visible)
    H7.boxSize = tonumber(size) or H7.boxSize or 12
    H7.visible = visible == true

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then ensureBox(player) end
    end

    say("shadow bodies on · size " .. tostring(H7.boxSize)
        .. (H7.visible and " · visible" or ""))
end

getgenv().hbs7Stop = function()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local box = character and character:FindFirstChild("__tea_hitbox")
        if box then pcall(function() box:Destroy() end) end
    end
    say("shadow bodies removed")
end

say("tea.cc hbs7 loaded  —  RightShift toggles")
say("run: hbs7Casts() then hbs7Restore()")
