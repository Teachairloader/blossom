-- tea.cc — damage path resolver
--
-- hbs2Grep dumps raw source lines, which is a wall of text. This build reads
-- every client script, pulls out only the remote CALL SITES, and prints each
-- remote once with the arguments it is handed. That is the shape needed to
-- forge a hit report without hooking anything.
--
--   hbs3Damage()            focus list: remotes whose names look combat
--   hbs3All()               every FireServer / InvokeServer call site
--   hbs3Show("Hit")         filter by remote or module name
--   RightShift              toggle the panel

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local H3 = getgenv().hbs3 or { maxCalls = 120, maxArgs = 96 }
getgenv().hbs3 = H3

-- ------------------------------------------------------------------- panel --

local panel = getgenv().hbs3Panel
local output
local lineCount = 0

local function buildPanel()
    if panel and panel.Parent then return panel, output end

    local gui = Instance.new("ScreenGui")
    gui.Name = "tea_hbs3"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 201

    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(700, 460)
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
    title.Text = "  tea.cc — hbs3 damage path"
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
    scroll.CanvasPosition = Vector2.new(0, math.max(0, lineCount * 18 - 400))
    frame.Visible = true
end

getgenv().hbs3Say = say

task.spawn(function()
    UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            local frame = buildPanel()
            if frame then frame.Visible = not frame.Visible end
        end
    end)
end)

-- ------------------------------------------------------------------ source --

local function scriptRoots()
    local list = { ReplicatedStorage }
    local props = Players.LocalPlayer
    local scripts = props:FindFirstChild("PlayerScripts")
    if scripts then table.insert(list, scripts) end
    local gui = props:FindFirstChild("PlayerGui")
    if gui then table.insert(list, gui) end
    return list
end

local function clientScripts()
    local list = {}
    for _, root in ipairs(scriptRoots()) do
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("ModuleScript") or descendant:IsA("LocalScript") then
                list[#list + 1] = descendant
            end
        end
    end
    return list
end

local CALL_PATTERN = "([%a_][%w_%.%[%]\"'_:]-):(%a+Server)%(([^()]*)%)"

local function trim(text, limit)
    text = (text:gsub("%s+", " "))
    if #text > limit then
        return text:sub(1, limit - 3) .. "..."
    end
    return text
end

local function collect()
    if type(decompile) ~= "function" then
        say("!! no decompile() in this executor", Color3.fromRGB(255, 120, 120))
        return nil
    end

    local calls = {}
    local modules = 0

    for _, instance in ipairs(clientScripts()) do
        local ok, source = pcall(decompile, instance)
        modules = modules + 1
        if ok and type(source) == "string" then
            for remote, method, args in source:gmatch(CALL_PATTERN) do
                local key = remote .. ":" .. method
                local entry = calls[key]
                if not entry then
                    entry = {
                        remote = remote,
                        method = method,
                        module = instance.Name,
                        count = 0,
                        samples = {},
                    }
                    calls[key] = entry
                end
                entry.count = entry.count + 1
                if #entry.samples < 3 then
                    entry.samples[#entry.samples + 1] = trim(args, H3.maxArgs or 96)
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(calls) do list[#list + 1] = entry end

    local keywords = { "hit", "damage", "dmg", "shot", "bullet", "hitbox", "attack", "kill", "fire", "cast" }
    local function weight(entry)
        local score = 0
        local lower = entry.remote:lower()
        for _, keyword in ipairs(keywords) do
            if lower:find(keyword, 1, true) then
                score = score + 10
            end
        end
        return score + math.min(entry.count, 9)
    end

    table.sort(list, function(a, b)
        local wa, wb = weight(a), weight(b)
        if wa == wb then return a.remote < b.remote end
        return wa > wb
    end)

    return list, modules
end

local function render(filter)
    local list, modules = collect()
    if not list then return end

    local needle = filter and filter:lower() or nil
    say(string.format("-- %d call sites across %d scripts", #list, modules or 0),
        Color3.fromRGB(169, 209, 142))

    local shown = 0
    for _, entry in ipairs(list) do
        local haystack = (entry.remote .. " " .. entry.module):lower()
        if not needle or haystack:find(needle, 1, true) then
            shown = shown + 1
            say(string.format("%s:%s  x%d  [%s]",
                entry.remote, entry.method, entry.count, entry.module),
                Color3.fromRGB(240, 244, 236))
            for _, sample in ipairs(entry.samples) do
                say("    (" .. sample .. ")", Color3.fromRGB(150, 160, 148))
            end
        end
    end

    if shown == 0 then
        say("-- nothing matched that filter", Color3.fromRGB(255, 200, 120))
    end
end

getgenv().hbs3All = function() render(nil) end
getgenv().hbs3Show = function(filter) render(filter) end
getgenv().hbs3Damage = function() render(nil) end

say("tea.cc hbs3 loaded  —  RightShift toggles")
say("run: hbs3Damage()")
