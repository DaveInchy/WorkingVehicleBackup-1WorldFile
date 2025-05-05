-- Vehicle Mod from the base local script --
wait(.9)
--================= Essential =================-- 
	local sp = script.Parent
	local userInput = game:GetService("UserInputService")
	local repStorage = game:GetService("ReplicatedStorage")
	local vehicle = sp.Parent:WaitForChild("CarGui").VehicleModel.Value

--================= Folders =================--
	local chassis = vehicle:WaitForChild("Chassis")
	local bodykit = vehicle:WaitForChild("Bodykit")
	local handling = vehicle:WaitForChild("Handling")
	local appearance = vehicle:WaitForChild("Appearance")
	local variables = vehicle:WaitForChild("Variables")

--================= Physical Parts =================--
	local seat = chassis.VehicleSeat
	
--Setup
local lightPart = bodykit.Lights.PopUpLights:WaitForChild("Lights")
local lightBase = bodykit.Lights.PopUpLights:WaitForChild("Color2")
local lightPivot = bodykit.Lights.PopUpLights:WaitForChild("Pivot")

if lightPart:FindFirstChild("qCFrameWeld") then
	lightPart.qCFrameWeld:Destroy()
end

if lightBase:FindFirstChild("qCFrameWeld") then
	lightBase.qCFrameWeld:Destroy()
end

----Weld
local weld = Instance.new("Weld")
weld.Name = "BodykitConnector"
weld.Part0 = lightBase
weld.Part1 = lightPart
weld.C0 = lightBase.CFrame:inverse() * CFrame.new(lightBase.Position)
weld.C1 = lightPart.CFrame:inverse() * CFrame.new(lightBase.Position)
weld.Parent = lightBase

--Rotate
local rotate = lightPivot:WaitForChild("HingeConstraint")

--================= Anti-Chatting Input =================-- 
--userInput.TextBoxFocused:connect(function()
--	isChatting = true
--end)
--
--userInput.TextBoxFocusReleased:connect(function()
--	isChatting = false
--end)

--================= Lights =================--
local lights = false
local lightdebounce = false

local function Headlights_InputBegan()
	--if not isChatting then
		--if key == "Headlights" then
		if lightdebounce == false then
			lights = not lights
			lightdebounce = true
			if lights then -- Lights pop up
				rotate.TargetAngle = 70
			else
				rotate.TargetAngle = 0
			end
			wait(2)
			lightdebounce = false
		end
		--end
	--end
end

require(game.ReplicatedStorage:WaitForChild("Simchassis"):WaitForChild("Modules"):WaitForChild("InputManager")).AttachFunction(Headlights_InputBegan, "InputBegan", "Headlights", true)