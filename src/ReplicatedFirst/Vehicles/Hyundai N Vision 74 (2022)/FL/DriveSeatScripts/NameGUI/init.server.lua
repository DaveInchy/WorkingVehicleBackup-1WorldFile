local seat = script.Parent.Parent
local team = seat.Parent.MISC.TEAM.Value
local playerHead 
local GUI 

script.Parent.Parent.ChildAdded:connect(function(child) 
	if child.Name ~= "Weld" then
		if child:IsA("Weld") and  child.Name=="SeatWeld" and game.Players:GetPlayerFromCharacter(child.Part1.Parent)~=nil then 
			local P=game.Players:GetPlayerFromCharacter(child.Part1.Parent) 
			local S=script.NameGUILocal:Clone() S.Parent=P.PlayerGui 
			S.Seat.Value=script.Parent.Parent.Parent:WaitForChild("DriveSeat") 
			S.Disabled=false 
			playerHead = seat.Occupant.Parent.Head
			local GUI = playerHead:FindFirstChild("NameTagGUI")
			if GUI ~= nil then
				local teamLogo = GUI.TeamLogo
				local speedText = GUI.SpeedText
				if team == "TEKU" then
					teamLogo.Image = "rbxassetid://6148664756"
				elseif team == "METAL_MANIACS" then
					teamLogo.Image = "rbxassetid://6148664020"
				elseif team == "DRONES" then
					teamLogo.Image = "rbxassetid://6148661270"
				elseif team == "SILENCERZ" then
					teamLogo.Image = "rbxassetid://6148663089"
				elseif team == "DUNE_RATZ" then
					teamLogo.Image = "rbxassetid://6237570621"
				elseif team == "ROAD_BEASTS" then
					teamLogo.Image = "rbxassetid://6237571200"
				else
					teamLogo.Image = ""
				end
				GUI.Size = UDim2.new(15,0,15,0)
				GUI.StudsOffset = Vector3.new(0,6,0)
				teamLogo.Visible = true
				speedText.Visible = true
			end
		end 
	end
end)

seat.ChildRemoved:Connect(function(child)
	if child.Name=="SeatWeld" and child:IsA("Weld") then
	if GUI ~= nil then
		local GUI = playerHead:FindFirstChild("NameTagGUI")
		local teamLogo = GUI.TeamLogo
		local speedText = GUI.SpeedText
		teamLogo.Image = ""
		speedText.Text = ""
		teamLogo.Visible = false
		speedText.Visible = false
		GUI.Size = UDim2.new(6,0,4,0)
		GUI.StudsOffset = Vector3.new(0,1.5,0)
		end
	end	
end)

while wait(.1) do
	local SO = seat.Occupant
	if SO ~= nil then
		local playerHead = seat.Occupant.Parent.Head
		GUI = playerHead:FindFirstChild("NameTagGUI")
		if GUI ~= nil then
			local Velocity = seat.AssemblyAngularVelocity.Magnitude
			if Velocity ~= Velocity then
				Velocity = 0
			end
			local speedMPH = math.floor(Velocity * ((10/12)*(60/88)))
			GUI.SpeedText.Text = speedMPH .. " MPH"
			if(speedMPH >= 201) then
				GUI.SpeedText.TextColor3 = Color3.new(1, 0.360784, 0.360784)
			elseif(speedMPH >= 151 and speedMPH <= 200) then
				GUI.SpeedText.TextColor3 = Color3.new(1, 0.741176, 0.380392)
			elseif(speedMPH >= 101 and speedMPH <= 150) then
				GUI.SpeedText.TextColor3 = Color3.new(1, 1, 0.498039)
			else
				GUI.SpeedText.TextColor3 = Color3.new(1, 1, 1)
			end	
		end
	end
end