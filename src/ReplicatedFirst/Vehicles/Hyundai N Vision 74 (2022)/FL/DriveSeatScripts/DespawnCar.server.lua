local s = script.Parent.Parent.Parent
local TimerEnabled = true
local counter = 0
local DespawnTime = 300 -- despawn time in seconds
local player

function removeCarOnLeave(Player)
	if player ~= nil then
		if Player == player then
			s:remove()
		end
	end
end

local function onPlayerAdded(Player)
	Player.CharacterAdded:connect(function(character)
		character:WaitForChild('Humanoid').Died:Connect(function()
		if player ~= nil then
			if Player == player then
					s:remove()
				end
			end
		end)
	end)
end

game.Players.PlayerAdded:Connect(onPlayerAdded)

game.Players.PlayerRemoving:connect(removeCarOnLeave)

script.Parent.Parent.ChildRemoved:connect(function(child)
	TimerEnabled = true
end)

script.Parent.Parent.ChildAdded:connect(function(child) 
	if child.Name ~= "Weld" then
		if child:IsA("Weld") and game.Players:GetPlayerFromCharacter(child.Part1.Parent)~=nil then 
			player = game.Players:GetPlayerFromCharacter(child.Part1.Parent) 
		end
	end
	TimerEnabled = false
	counter = 0
end)

while(wait(1))do
	if TimerEnabled == true then
		counter = counter + 1
		if counter >= DespawnTime then
			s:remove()
			TimerEnabled = false
		end
	end
end