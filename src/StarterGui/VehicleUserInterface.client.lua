local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = script.Parent
local Players = game:GetService("Players")
local Roact = require(ReplicatedStorage.Packages.Roact)

local DevButton = require(ReplicatedStorage.Components:WaitForChild("SpawnCarButton"))

local ScreenGui: ScreenGui = Instance.new("ScreenGui", PlayerGui)

Roact.mount(
    Roact.createElement("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
    },{
       Development = DevButton(),
    }), ScreenGui, "VehicleUI"
)
