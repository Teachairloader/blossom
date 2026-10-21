-- tea.cc — cast source dump + tolerance fan
--
-- The scan found no damage remote, which means the hit is most likely resolved
-- on the server from the cast you send. If that is true, no client script can
-- resize the target's parts — but the CAST can be made to tolerate a near miss,
-- which is the same practical result in ray space.
--
--   hbs4Source("SimpleCast")   dump the gun module into a copyable box
--   hbs4Find("TakeDamage")     counts per script, one line each, no walls
--   hbs4Fan(true)              tolerance fan: extra rays aimed at anyone the
--                              centre ray passes within `radius` studs of
--   hbs4Stop()                 restore the cast module

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H4 = getgenv().hbs4 or {
    fan = false,
    radius = 6,
    rays = 9,
    spread = 1.0,
    maxTargets = 3,
}
getgenv().hbs4 = H4

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs4Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs4"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 202

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(760, 500)
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
    title.Text = "  tea.cc — hbs4 cast work"
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
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 440))
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

-- ----------------------------------------------------------------- source ---

local function clientScripts()
    local roots = { ReplicatedStorage }
    local player = Players.LocalPlayer
    local scripts = player:FindFirstChild("PlayerScripts")
    if scripts then table.insert(roots, scripts) end
    local gui = player:FindFirstChild("PlayerGui")
    if gui then table.insert(roots, gui) end

    local list = {}
    for _, root in ipairs(roots) do
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("ModuleScript") or descendant:IsA("LocalScript") then
                list[#list + 1] = descendant
            end
        end
    end
    return list
end

getgenv().hbs4Source = function(name)
    if type(decompile) ~= "function" then
        say("!! no decompile() in this executor")
        return
    end
    name = tostring(name or "SimpleCast"):lower()

    local matches = {}
    for _, instance in ipairs(clientScripts()) do
        if instance.Name:lower():find(name, 1, true) then
            matches[#matches + 1] = instance
        end
    end

    if #matches == 0 then
        say("!! no script named like " .. name)
        return
    end

    local frame = buildPanel()
    say(string.format("-- %d script(s) matched \"%s\"", #matches, name),
        Color3.fromRGB(169, 209, 142))

    for _, instance in ipairs(matches) do
        local ok, source = pcall(decompile, instance)
        if not ok or type(source) ~= "string" then
            say("  (decompile failed) " .. instance:GetFullName())
        else
            say("  " .. instance:GetFullName() .. "  " .. #source .. " chars")

            if writefile then
                local okWrite, path = pcall(function()
                    local file = "tea_" .. instance.Name .. ".lua"
                    writefile(file, source)
                    return file
                end)
                if okWrite then
                    say("  saved: workspace/" .. tostring(path), Color3.fromRGB(200, 220, 190))
                end
            end

            local box = Instance.new("TextBox")
            box.Size = UDim2.new(1, -8, 0, 200)
            box.BackgroundColor3 = Color3.fromRGB(18, 20, 18)
            box.BorderSizePixel = 0
            box.ClearTextOnFocus = false
            box.MultiLine = true
            box.TextWrapped = false
            box.TextXAlignment = Enum.TextXAlignment.Left
            box.TextYAlignment = Enum.TextYAlignment.Top
            box.Font = Enum.Font.Code
            box.TextSize = 11
            box.TextColor3 = Color3.fromRGB(210, 218, 205)
            box.Text = source:sub(1, 120000)
            box.LayoutOrder = lineCount + 1
            box.Parent = output
            lineCount = lineCount + 1
            output.CanvasSize = UDim2.new(0, 0, 0, lineCount * 18 + 210)
        end
    end

    if frame then frame.Visible = true end
end

getgenv().hbs4Find = function(keyword)
    keyword = tostring(keyword or "TakeDamage")
    if type(decompile) ~= "function" then
        say("!! no decompile() in this executor")
        return
    end

    say("-- scanning for \"" .. keyword .. "\"", Color3.fromRGB(169, 209, 142))
    local hits = 0

    for _, instance in ipairs(clientScripts()) do
        local ok, source = pcall(decompile, instance)
        if ok and type(source) == "string" and source:find(keyword, 1, true) then
            local count = 0
            for _ in source:gmatch(keyword:gsub("[%p]", function(c) return "%" .. c end)) do
                count = count + 1
            end
            if count > 0 then
                hits = hits + 1
                say(string.format("  %-42s x%d", instance.Name, count))
            end
        end
    end

    if hits == 0 then
        say("  nothing — the client never touches that path")
    end
end

-- ------------------------------------------------------------ cast tolerance --

local castModule = nil
local castOriginal = nil

local function nearestTargets(origin, direction)
    local unit = direction.Unit
    local found = {}
    local localCharacter = Players.LocalPlayer.Character

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if character and humanoid and humanoid.Health > 0 then
                local part = character:FindFirstChild("Head")
                    or character:FindFirstChild("UpperTorso")
                    or character:FindFirstChild("HumanoidRootPart")
                if part then
                    local toPart = part.Position - origin
                    local along = toPart:Dot(unit)
                    if along > 0 then
                        local closest = origin + unit * along
                        local miss = (part.Position - closest).Magnitude
                        if miss <= (H4.radius or 6) then
                            found[#found + 1] = { part = part, miss = miss }
                        end
                    end
                end
            end
        end
    end

    table.sort(found, function(a, b) return a.miss < b.miss end)
    return found
end

local function directionsFor(origin, direction)
    local unit = direction.Unit
    local list = {}

    local up = Vector3.new(0, 1, 0)
    if math.abs(unit:Dot(up)) > 0.99 then up = Vector3.new(1, 0, 0) end
    local right = unit:Cross(up).Unit
    local realUp = right:Cross(unit).Unit
    local spread = math.rad(math.clamp(tonumber(H4.spread) or 1, 0.01, 20))

    local total = math.clamp(math.floor(tonumber(H4.rays) or 9), 1, 32)
    local ring = math.max(1, math.floor((total - 1) / 6))

    list[#list + 1] = unit

    local placed = 1
    for step = 1, ring do
        local radius = spread * step
        for slot = 1, 6 do
            if placed >= total then break end
            local theta = (slot - 1) * (math.pi / 3)
            list[#list + 1] = (unit
                + right * (math.cos(theta) * radius)
                + realUp * (math.sin(theta) * radius)).Unit
            placed = placed + 1
        end
    end

    -- rays that go straight through anyone the centre ray just barely missed
    local targets = nearestTargets(origin, unit)
    for index = 1, math.min(#targets, H4.maxTargets or 3) do
        local part = targets[index].part
        local toPart = (part.Position - origin)
        if toPart.Magnitude > 0.1 then
            list[#list + 1] = toPart.Unit
        end
    end

    return list
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
        local cfg = getgenv().hbs4
        if not cfg or not cfg.fan or typeof(direction) ~= "Vector3" then
            return castOriginal(self, origin, direction, speed, options)
        end

        local result
        for _, dir in ipairs(directionsFor(origin, direction)) do
            result = castOriginal(self, origin, dir, speed, options)
        end
        return result
    end

    return true
end

getgenv().hbs4Fan = function(on)
    if not castModule then
        local ok, why = castInstall()
        if not ok then
            say("!! " .. tostring(why), Color3.fromRGB(255, 120, 120))
            return
        end
    end
    H4.fan = on ~= false
    say("fan " .. (H4.fan and "ON" or "OFF")
        .. "  rays " .. tostring(H4.rays)
        .. "  radius " .. tostring(H4.radius) .. " studs")
end

getgenv().hbs4Stop = function()
    if castModule and castOriginal then
        pcall(function() castModule.Fire = castOriginal end)
        say("SimpleCast.Fire restored")
    end
    castModule = nil
    castOriginal = nil
    H4.fan = false
end

say("tea.cc hbs4 loaded  —  RightShift toggles")
say("1) hbs4Source(\"SimpleCast\")   2) hbs4Find(\"TakeDamage\")   3) hbs4Fan(true)")
