-- Vehicle Mod from the base local script --
-- Coal rolling
wait(3)
--================= Essential =================--
	local sp = script.Parent
	local userInput = game:GetService("UserInputService")
	local repStorage = game:GetService("ReplicatedStorage")
	local vehicle = sp.Parent:WaitForChild("CarGui").VehicleModel.Value
	local InputManager = require(game.ReplicatedStorage:WaitForChild("Simchassis"):WaitForChild("Modules"):WaitForChild("InputManager"))

--================= Folders =================--
	local chassis = vehicle:WaitForChild("Chassis")
	local bodykit = vehicle:WaitForChild("Bodykit")
	local handling = vehicle:WaitForChild("Handling")
	local appearance = vehicle:WaitForChild("Appearance")
	local variables = vehicle:WaitForChild("Variables")
	
--================= Physical Parts =================--
	local seat = chassis.VehicleSeat

--================= Anti-Chatting Input =================-- 
--userInput.TextBoxFocused:connect(function()
--	isChatting = true
--end)
--
--userInput.TextBoxFocusReleased:connect(function()
--	isChatting = false
--end)

--================= Horn =================--
local horn = false
--[[userInput.InputBegan:connect(function(key)
	if not isChatting then
		if key.KeyCode == Enum.KeyCode.H or key.KeyCode == Enum.KeyCode.ButtonR3 then
			horn = true
		end
	end
end)

userInput.InputEnded:connect(function(key)
	if not isChatting then
		if key.KeyCode == Enum.KeyCode.H or key.KeyCode == Enum.KeyCode.ButtonR3 then
			horn = false
		end
	end
end)--]]

--[[InputManager:WaitForChild("InputBegan").Event:Connect(function(key)
	if not isChatting then
		if key == "Horn" then
			horn = true
		end
	end
end)

InputManager:WaitForChild("InputEnded").Event:connect(function(key)
	if not isChatting then
		if key == "Horn" then
			horn = false
		end
	end
end)--]]

local function Horn_InputBegan()
	--if not isChatting then
		horn = true
	--end
end

local function Horn_InputEnded()
	--if not isChatting then
		horn = true
	--end
end

InputManager.AttachFunctions({
	{Horn_InputBegan, "InputBegan", "Horn", true},
	{Horn_InputEnded, "InputEnded", "Horn", true}
})
