script.Parent.Parent.ChildAdded:connect(function(child) 
	if child.Name ~= "Weld" then
		if child:IsA("Weld") and game.Players:GetPlayerFromCharacter(child.Part1.Parent)~=nil then 
			local P=game.Players:GetPlayerFromCharacter(child.Part1.Parent) 
			local S=script.L:Clone() S.Parent=P.PlayerGui 
			S.Seat.Value=script.Parent.Parent.Parent:WaitForChild("DriveSeat")
			S.Disabled=false 
		end
	end 
end)