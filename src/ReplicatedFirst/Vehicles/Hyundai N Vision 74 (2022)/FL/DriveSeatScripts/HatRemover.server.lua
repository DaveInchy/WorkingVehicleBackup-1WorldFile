local accessories = {}
local ServerScriptService = game:GetService("ServerScriptService")
local Scripts = ServerScriptService:WaitForChild("Scripts")
local Modules = Scripts:WaitForChild("Modules")
local DataModule = require(Modules:WaitForChild("DataModule"))
local Hide = true

function GetData(Player)
	local PlayerData  = DataModule.ReturnData(Player)
	if PlayerData["Settings"] ~= nil then
		if PlayerData["Settings"]["Hide Player Accessories"]~= nil then
			Hide =  PlayerData["Settings"]["Hide Player Accessories"]
		end	
	end
end

script.Parent.Parent.ChildAdded:connect(function(child) 
	if child.Name ~= "Weld" then
		if child:IsA("Weld") and game.Players:GetPlayerFromCharacter(child.Part1.Parent)~=nil and child.Part1.Parent ~= nil then
			GetData(game.Players:GetPlayerFromCharacter(child.Part1.Parent))
			if Hide then
				AccessoryHandler(child.Part1.Parent,1)
			end	
		end
	end
end)

script.Parent.Parent.ChildRemoved:connect(function(child)
	if child.Name ~= "Weld" then
		if child:IsA("Weld") and game.Players:GetPlayerFromCharacter(child.Part1.Parent)~=nil and child.Part1.Parent ~= nil then 
			AccessoryHandler(child.Part1.Parent,0)
		end
	end
end)

function AccessoryHandler(Object,Visible)
	for i, Child in pairs(Object:GetChildren())do
		if Child:IsA("Accessory")then
			for v,children in pairs(Child:GetChildren())do
				if children:IsA("BasePart")then
					children.Transparency = Visible
				end
			end
		end
		AccessoryHandler(Child,Visible)
	end
end
