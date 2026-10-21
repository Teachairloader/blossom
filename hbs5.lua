-- tea.cc — SimpleCast inspection
--
-- The dump worked, the panel just stacked the source box on top of the scan
-- lines, which reads as garbage. This build stops drawing source on screen and
-- puts it on your clipboard instead, plus it watches the module's own RayHit
-- signal so we can see whether hits are computed on the client.
--
--   hbs5Copy("SimpleCast")   decompile -> clipboard -> paste it to me
--   hbs5Keys()               require the module and list what it exposes
--   hbs5RayHit()             log the payloads of its RayHit signal
--   hbs5RayHitStop()

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H5 = getgenv().hbs5 or { maxEvents = 40 }
getgenv().hbs5 = H5

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs5Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs5"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 203

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(760, 420)
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
    title.Text = "  tea.cc — hbs5 SimpleCast"
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
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextColor3 = tint or Color3.fromRGB(220, 226, 218)
    label.Text = text
    label.LayoutOrder = lineCount
    label.Parent = scroll

    scroll.CanvasSize = UDim2.new(0, 0, 0, lineCount * 18 + 8)
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 360))
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

-- ------------------------------------------------------------------- dump ---

local function findScript(name)
    name = tostring(name):lower()
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if (descendant:IsA("ModuleScript") or descendant:IsA("LocalScript"))
            and descendant.Name:lower():find(name, 1, true) then
            return descendant
        end
    end
    return nil
end

getgenv().hbs5Copy = function(name)
    local script = findScript(name or "SimpleCast")
    if not script then
        say("!! no script named like " .. tostring(name))
        return
    end
    if type(decompile) ~= "function" then
        say("!! no decompile() in this executor")
        return
    end

    local ok, source = pcall(decompile, script)
    if not ok or type(source) ~= "string" then
        say("!! decompile failed on " .. script:GetFullName())
        return
    end

    say("-- " .. script:GetFullName() .. "  " .. #source .. " chars",
        Color3.fromRGB(169, 209, 142))

    local copied = false
    if type(setclipboard) == "function" then
        copied = pcall(setclipboard, source)
    end

    if copied then
        say("copied to clipboard — paste it here", Color3.fromRGB(200, 220, 190))
    else
        local okWrite, path = false, nil
        if type(writefile) == "function" then
            okWrite, path = pcall(writefile, "tea_" .. script.Name .. ".lua", source)
        end
        if okWrite then
            say("clipboard blocked — saved workspace/" .. tostring(path),
                Color3.fromRGB(255, 200, 120))
        else
            say("clipboard and writefile both blocked", Color3.fromRGB(255, 120, 120))
        end
    end

    -- short preview so the panel still proves it read the right file
    local preview = source:gsub("%s+", " ")
    say("  " .. preview:sub(1, 200), Color3.fromRGB(150, 160, 148))
end

getgenv().hbs5Keys = function()
    local script = findScript("SimpleCast")
    if not script then
        say("!! no SimpleCast found")
        return
    end

    local ok, module = pcall(require, script)
    if not ok or type(module) ~= "table" then
        say("!! require failed: " .. tostring(module), Color3.fromRGB(255, 120, 120))
        return
    end

    say("-- SimpleCast keys", Color3.fromRGB(169, 209, 142))
    for key, value in pairs(module) do
        say(string.format("  %-16s %s", tostring(key), typeof(value)))
    end
end

-- -------------------------------------------------------------- ray signal --

local rayConnection = nil
local rayCount = 0

local function describe(value)
    if typeof(value) == "Instance" then
        return "Instance(" .. value.ClassName .. ":" .. value.Name .. ")"
    end
    return typeof(value)
end

getgenv().hbs5RayHit = function()
    if rayConnection then
        say("ray log already running")
        return
    end

    local script = findScript("SimpleCast")
    if not script then
        say("!! no SimpleCast found")
        return
    end

    local ok, module = pcall(require, script)
    if not ok or type(module) ~= "table" then
        say("!! require failed", Color3.fromRGB(255, 120, 120))
        return
    end

    local signal = module.RayHit
    if not signal then
        say("!! module has no RayHit field")
        return
    end
    if type(signal.Connect) ~= "function" then
        say("!! RayHit is not a signal: " .. typeof(signal))
        return
    end

    rayConnection = signal:Connect(function(...)
        if rayCount >= (H5.maxEvents or 40) then return end
        rayCount = rayCount + 1
        local kinds = {}
        for index = 1, math.min(select("#", ...), 6) do
            kinds[index] = describe((select(index, ...)))
        end
        say(string.format("#%d RayHit(%s)", rayCount, table.concat(kinds, ", ")),
            Color3.fromRGB(210, 230, 200))
    end)

    say("listening on SimpleCast.RayHit — take a shot")
end

getgenv().hbs5RayHitStop = function()
    if rayConnection then
        pcall(function() rayConnection:Disconnect() end)
        rayConnection = nil
        say("ray log stopped")
    end
end

say("tea.cc hbs5 loaded  —  RightShift toggles")
say("1) hbs5Keys()   2) hbs5Copy(\"SimpleCast\")   3) hbs5RayHit()")
