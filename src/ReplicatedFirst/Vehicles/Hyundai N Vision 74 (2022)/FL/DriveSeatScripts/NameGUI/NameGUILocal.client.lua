local seat = script.Seat.Value
local localP = game.Players.LocalPlayer

function HideGui(enabled)
	local Head = localP.Character:FindFirstChild("Head")
	if Head ~= nil then
		local GUI = Head:FindFirstChild("NameTagGUI")
		if GUI ~= nil then
			GUI.Enabled = enabled
		end
		local tablePlayers = game.Players:GetPlayers()
		for i, v in pairs (tablePlayers) do
			if v~= localP then
				local GUI = v.Character.Head:FindFirstChild("NameTagGUI")
				if GUI ~= nil then
					local teamLogo = GUI.TeamLogo
					local speedText = GUI.SpeedText
					teamLogo.Visible = not enabled
					speedText.Visible = not enabled
				end
			end
		end
	end	
end

seat.ChildRemoved:Connect(function(child)
	if child.Name=="SeatWeld" and child:IsA("Weld") then
		HideGui(true)
		script:Destroy()
	end	
end)
HideGui(false)