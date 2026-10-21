-- tea.cc — hitbox recon, plain source, on-screen output
--
-- Same passive scan as hbs2, with two differences that matter when a console
-- stays silent: the file is served as plain Lua (no armour container, nothing
-- to decode before it runs) and every result is drawn into an in-game panel so
-- the output is visible even with no console attached.
--
--   RightShift   show / hide the panel
--   hbs2Remotes()
--   hbs2Grep("FireServer")
--   hbs2Modules()

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H2 = getgenv().hbs2 or { maxLines = 400, fan = false }
getgenv().hbs2 = H2

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs2Panel
local output

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs2"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 200

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(620, 420)
    frame.Position = UDim2.fromOffset(40, 80)
    frame.BackgroundColor3 = Color3.fromRGB(12, 14, 12)
    frame.BackgroundTransparency = 0.08
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
    title.Text = "  tea.cc — hbs2 (RightShift to hide)"
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

local lineCount = 0

local function say(text)
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
    label.TextColor3 = Color3.fromRGB(220, 226, 218)
    label.Text = text
    label.LayoutOrder = lineCount
    label.Parent = scroll

    scroll.CanvasSize = UDim2.new(0, 0, 0, lineCount * 18 + 8)
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 360))
    frame.Visible = true
end

getgenv().hbs2Say = say

task.spawn(function()
    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            local frame = buildPanel()
            if frame then frame.Visible = not frame.Visible end
        end
    end)
end)

-- ----------------------------------------------------------------- scans ----

local function moduleScan(filter)
    local needle = filter and filter:lower() or nil
    local list = {}
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        if descendant:IsA("ModuleScript") then
            if not needle or descendant.Name:lower():find(needle, 1, true) then
                list[#list + 1] = descendant
            end
        end
    end
    return list
end

getgenv().hbs2Remotes = function()
    local list = {}
    for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
        local class = descendant.ClassName
        if class == "RemoteEvent" or class == "RemoteFunction"
            or class == "UnreliableRemoteEvent" then
            list[#list + 1] = descendant
        end
    end

    say(string.format("-- %d remotes under ReplicatedStorage", #list))
    for _, remote in ipairs(list) do
        say("  " .. remote.ClassName .. "  " .. remote:GetFullName())
    end
    return list
end

getgenv().hbs2Modules = function(filter)
    local list = moduleScan(filter)
    say(string.format("-- %d module scripts", #list))
    for _, module in ipairs(list) do
        say("  " .. module:GetFullName())
    end
    return list
end

getgenv().hbs2Grep = function(pattern, moduleFilter)
    if type(pattern) ~= "string" then
        say("!! hbs2Grep needs a pattern, e.g. hbs2Grep(\"FireServer\")")
        return
    end
    if type(decompile) ~= "function" then
        say("!! no decompile() in this executor")
        return
    end

    local limit = tonumber(H2.maxLines) or 400
    local printed, scanned = 0, 0

    for _, module in ipairs(moduleScan(moduleFilter)) do
        local ok, source = pcall(decompile, module)
        scanned = scanned + 1
        if ok and type(source) == "string" then
            for line in source:gmatch("[^\r\n]+") do
                if printed >= limit then
                    say("!! line cap reached — narrow the filter")
                    return
                end
                local okMatch, start = pcall(string.find, line, pattern)
                if okMatch and start then
                    printed = printed + 1
                    say("[" .. module.Name .. "] " .. (line:gsub("^%s+", "")))
                end
            end
        end
    end

    say(string.format("-- %d lines across %d modules", printed, scanned))
end

say("tea.cc hbs2 plain build loaded")
say("RightShift toggles this panel")
say("run: hbs2Remotes()  then  hbs2Grep(\"FireServer\")")
