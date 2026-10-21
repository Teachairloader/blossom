-- tea.cc — rf3: one line, no logs
-- Casts finish fast (queue drains, trigger frees up) + torn-finger trigger while
-- the real left button is held. Never stacks Fire calls, so it cannot wedge.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")

-- tear down any previous rf3 without needing another script
if type(getgenv().rf3Stop) == "function" then
    pcall(getgenv().rf3Stop)
end

getgenv().rf3 = { speed = 8, maxDistance = 220, rate = 60 }

local module = ReplicatedStorage:FindFirstChild("SimpleCast")
local cast = module and module:IsA("ModuleScript") and select(2, pcall(require, module)) or nil

if type(cast) == "table" and type(cast.Fire) == "function" then
    local original = cast.Fire
    cast.Fire = function(self, origin, direction, speed, options)
        local result = original(self, origin, direction, speed, options)
        local cfg = getgenv().rf3
        if cfg and type(result) == "table" then
            if typeof(result.Velocity) == "Vector3" then
                result.Velocity = result.Velocity * (tonumber(cfg.speed) or 8)
            end
            local cap = tonumber(cfg.maxDistance)
            if cap and (not result.MaxDistance or result.MaxDistance > cap) then
                result.MaxDistance = cap
            end
        end
        return result
    end

    getgenv().rf3Stop = function()
        pcall(function() cast.Fire = original end)
        getgenv().rf3 = nil
        getgenv().rf3Stop = nil
    end
end

local nextPull = 0

RunService.Heartbeat:Connect(function()
    local cfg = getgenv().rf3
    if not cfg then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
    if os.clock() < nextPull then return end

    nextPull = os.clock() + (1 / math.clamp(tonumber(cfg.rate) or 60, 1, 60))
    local mouse = UIS:GetMouseLocation()
    pcall(function()
        VIM:SendMouseButtonEvent(mouse.X, mouse.Y, 0, true, game, 1)
        VIM:SendMouseButtonEvent(mouse.X, mouse.Y, 0, false, game, 1)
    end)
end)
