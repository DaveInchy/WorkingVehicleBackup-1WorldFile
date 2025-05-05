return function()
	
	-- create clouds if nonexistend
	local clouds = Instance.new("Clouds")
	clouds.Parent = game.Workspace.Terrain
	
	-- create atmosphere if nonexistend
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = game.Lighting

	if not game.Lighting:FindFirstChildWhichIsA("BlurEffect") then
		local atmosphere = Instance.new("BlurEffect")
		atmosphere.Parent = game.Lighting
	end
		
	game.Lighting.ClockTime = 0
	game.Lighting.Brightness = 0
end