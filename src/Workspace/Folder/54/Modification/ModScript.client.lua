-- Vehicle Mod from the base local script --
-- Hover mode
wait(1.5)
--================= Essential =================--
	local sp = script.Parent
	local userInput = game:GetService("UserInputService")
	local repStorage = game:GetService("ReplicatedStorage")
	repeat
		wait()
	until sp.Parent:FindFirstChild("CarGui") and sp.Parent.CarGui.VehicleModel.Value
	local vehicle = sp.Parent.CarGui.VehicleModel.Value
	local ignoreList = 
	{vehicle,
	workspace.Foliage,
	--workspace.Parachutes,
	workspace.GasStation,
	workspace.GasStationRaceTrack,
	workspace.speed_cameras,
	}

--================= Folders =================--
	local chassis = vehicle:WaitForChild("Chassis")
	local bodykit = vehicle:WaitForChild("Bodykit")
	local handling = vehicle:WaitForChild("Handling")
	local appearance = vehicle:WaitForChild("Appearance")
	local variables = vehicle:WaitForChild("Variables")
	local disable_controls = variables:WaitForChild("Controls_Enabled")
--================= Physical Parts =================--
	local seat = chassis.VehicleSeat


--================= Hover =================--
local HoverThrottle = 0			-- How much force the craft starts with when starting up. Set this back to it's original value every time the player begins flying
local upForce = false
local Handbrake = false

local Player = game.Players.LocalPlayer
local Mouse = Player:GetMouse()
local Craft = bodykit.Hover

local Start = tick()
local SteerForce = 10000			--Move the CenterOfMass attachment forward/backward relative to the Body to change steering handling
local ThrottleForce = 45000		

local Power = 88888 				-- How much force does it use to stabilize on each of the 4 corner vectors? The higher this is the more spazzy the craft can get trying to stabilize itself
local HoverDist = 15  				-- This number is actually a lie. The craft will attempt to hover at this height, but Power/Dampening morph the actual ride height quite a bit
local HoverHistory = {}

local PushVector = Vector2.new() 	-- X represents turns, Y represents throttle. This is set automagically as the player uses WASD to move
local LastPos = Craft.CFrame
----------Some notes
--Make sure the craft has it's mass balanced with the center of vertical forces or it'll drift towards whichever side is heavier
--Too little power on too heavy an object can make the craft fly poorly or not even take off of the ground
--Too much power will cause the boards ride quality to suffer by being way too bumpy


local vehMaxTorque = Vector3.new(20, 10, 5)
local hovering = false
local InputManager = require(game.ReplicatedStorage:WaitForChild("Simchassis"):WaitForChild("Modules"):WaitForChild("InputManager"))


--================= Anti-Chatting Input =================-- 
--userInput.TextBoxFocused:connect(function()
--	isChatting = true
--end)
--
--userInput.TextBoxFocusReleased:connect(function()
--	isChatting = false
--end)

local function TweenAxle(Axle, Goal, RunTime)
	spawn(function()
		local S = tick()
		local Start = Axle.InclinationAngle
		
		while tick()-S < RunTime do
			Axle.InclinationAngle = Start+(Goal-Start)*(((tick()-S)/RunTime)^2)
			game:GetService("RunService").Heartbeat:Wait()
		end
		
		Axle.InclinationAngle = Goal
	end)
end


userInput.InputBegan:connect(function(key)
	if key.KeyCode == Enum.KeyCode.Space then
		Handbrake = true
	end
end)

userInput.InputEnded:connect(function(key)
	if key.KeyCode == Enum.KeyCode.Space then
		Handbrake = false
	end
end)

--userInput.InputBegan:connect(function(key)
--game.ReplicatedStorage:WaitForChild("Simchassis"):WaitForChild("Modules"):WaitForChild("InputManager"):WaitForChild("InputBegan").Event:Connect(function(key)
local function DeloreanHover_InputBegan()
	--if not isChatting then
		--if key.KeyCode == Enum.KeyCode.Y or key.KeyCode == Enum.KeyCode.ButtonL3 then
		--if key == "DeloreanHover" then
			if not hovering and not game:GetService("CollectionService"):HasTag(game.Players.LocalPlayer.Character,"race") and disable_controls.Value then
				hovering = true
				upForce = true
				HoverThrottle = 0
				
				for i,v in pairs(Craft.Forces:GetChildren()) do
					HoverHistory[v.Attachment0.Name] = 0
					v.Enabled = true
				end
				
				pcall(function()
				bodykit.CenterOfMass.WheelPoint1.Position = Vector3.new(3.25, -5.75, -1)
				bodykit.CenterOfMass.WheelPoint1.Orientation = Vector3.new(0,-115,-90)
				bodykit.CenterOfMass.WheelPoint2.Position = Vector3.new(-3.25, -5.75, -1)
				bodykit.CenterOfMass.WheelPoint2.Orientation = Vector3.new(0,-75,-90)
				
				bodykit.CenterOfMass.WheelPoint3.Position = Vector3.new(3.25, 5.75, -1)
				bodykit.CenterOfMass.WheelPoint3.Orientation = Vector3.new(0,-115,-90)
				bodykit.CenterOfMass.WheelPoint4.Position = Vector3.new(-3.25, 5.75, -1)
				bodykit.CenterOfMass.WheelPoint4.Orientation = Vector3.new(0,-75,-90)
				end)
				
				bodykit.CenterOfMass.WheelPoint1.HoverEffect.Enabled = true
				bodykit.CenterOfMass.WheelPoint2.HoverEffect.Enabled = true
				bodykit.CenterOfMass.WheelPoint3.HoverEffect.Enabled = true
				bodykit.CenterOfMass.WheelPoint4.HoverEffect.Enabled = true
				
				bodykit.CenterOfMass.WheelPoint1.HoverEffect2.Enabled = true
				bodykit.CenterOfMass.WheelPoint2.HoverEffect2.Enabled = true
				bodykit.CenterOfMass.WheelPoint3.HoverEffect2.Enabled = true
				bodykit.CenterOfMass.WheelPoint4.HoverEffect2.Enabled = true
				
				bodykit.CenterOfMass.WheelPoint1.HoverLight.Enabled = true
				bodykit.CenterOfMass.WheelPoint2.HoverLight.Enabled = true
				bodykit.CenterOfMass.WheelPoint3.HoverLight.Enabled = true
				bodykit.CenterOfMass.WheelPoint4.HoverLight.Enabled = true
				
				TweenAxle(chassis.Axles.BL, 155, 0.6)
				TweenAxle(chassis.Axles.BR, 25, 0.6)
				TweenAxle(chassis.Axles.FL, 155, 0.6)
				TweenAxle(chassis.Axles.FR, 25, 0.6)
				
				repStorage:WaitForChild("Simchassis"):WaitForChild("RemoteEvents"):WaitForChild("HoverParticle"):FireServer(true, bodykit.CenterOfMass.WheelPoint1.HoverEffect,bodykit.CenterOfMass.WheelPoint2.HoverEffect, bodykit.CenterOfMass.WheelPoint3.HoverEffect, bodykit.CenterOfMass.WheelPoint4.HoverEffect)
				
				-- Enable Turn and Push
				bodykit.Hover.Push.Enabled = true
				bodykit.Hover.Turn.Enabled = true
				
				intMaxTorque = bodykit.CenterOfMass.Stablize.MaxTorque
				bodykit.CenterOfMass.Stablize.MaxTorque = Vector3.new(40, 20, 10)
				
				-- Disable Gyro
				--vehMaxTorque = vehicle.Bodykit.CenterOfMass.Stablize.MaxTorque
				--vehicle.Bodykit.CenterOfMass.Stablize.MaxTorque =  Vector3.new(0, 0, 0)
			end
		--end
	--end
end--)

--userInput.InputBegan:connect(function(key)
--game.ReplicatedStorage:WaitForChild("Simchassis"):WaitForChild("Modules"):WaitForChild("InputManager"):WaitForChild("InputBegan").Event:Connect(function(key)
local function Jump_InputBegan()
	--if not isChatting then
		--if key.KeyCode == Enum.KeyCode.X or key.KeyCode == Enum.KeyCode.ButtonL3 then
		--if key == "Jump" then
			if hovering then
				hovering = false
				upForce = false
				HoverThrottle = 0
				HoverHistory = {}
				
				bodykit.CenterOfMass.WheelPoint1.HoverEffect.Enabled = false
				bodykit.CenterOfMass.WheelPoint2.HoverEffect.Enabled = false
				bodykit.CenterOfMass.WheelPoint3.HoverEffect.Enabled = false
				bodykit.CenterOfMass.WheelPoint4.HoverEffect.Enabled = false
				
				repStorage:WaitForChild("Simchassis"):WaitForChild("RemoteEvents"):WaitForChild("HoverParticle"):FireServer(false, bodykit.CenterOfMass.WheelPoint1.HoverEffect,bodykit.CenterOfMass.WheelPoint2.HoverEffect, bodykit.CenterOfMass.WheelPoint3.HoverEffect, bodykit.CenterOfMass.WheelPoint4.HoverEffect)
				
				bodykit.CenterOfMass.WheelPoint1.HoverEffect2.Enabled = false
				bodykit.CenterOfMass.WheelPoint2.HoverEffect2.Enabled = false
				bodykit.CenterOfMass.WheelPoint3.HoverEffect2.Enabled = false
				bodykit.CenterOfMass.WheelPoint4.HoverEffect2.Enabled = false
				
				
				bodykit.CenterOfMass.WheelPoint1.HoverLight.Enabled = false
				bodykit.CenterOfMass.WheelPoint2.HoverLight.Enabled = false
				bodykit.CenterOfMass.WheelPoint3.HoverLight.Enabled = false
				bodykit.CenterOfMass.WheelPoint4.HoverLight.Enabled = false
				

				TweenAxle(chassis.Axles.BL, 90, 0.4)
				TweenAxle(chassis.Axles.FL, 90, 0.4)
				TweenAxle(chassis.Axles.FR, 90, 0.4)
				TweenAxle(chassis.Axles.BR, 90, 0.4)

				
				for i,v in pairs(Craft.Forces:GetChildren()) do
					v.Enabled = false
				end
				
				

				-- Disable Turn and Push
				bodykit.Hover.Push.Enabled = false
				bodykit.Hover.Turn.Enabled = false
				
				-- Enable Gyro
				bodykit.CenterOfMass.Stablize.MaxTorque = intMaxTorque
				--vehicle.Bodykit.CenterOfMass.Stablize.MaxTorque =  vehMaxTorque
			end
		--end
	--end
end--)

InputManager.AttachFunctions({
	{DeloreanHover_InputBegan, "InputBegan", "DeloreanHover", true},
	{Jump_InputBegan, "InputBegan", "Jump", true}
})

game:GetService("CollectionService"):GetInstanceAddedSignal("race"):Connect(function(o)
	if o == game.Players.LocalPlayer.Character then
		Jump_InputBegan()
	end
end)

disable_controls.Changed:Connect(function()
	if not disable_controls.Value then
		Jump_InputBegan()
	end
end)


local t= {A = 1 }

game:GetService("RunService").Heartbeat:connect(function(Delta)
	if Player.Character and Player.Character:findFirstChild("Humanoid") and Player.Character.Humanoid.Sit then
		
		if upForce then
			HoverThrottle = math.min(1, HoverThrottle+Delta*2)
			
			local CF = Craft.CFrame
			local PositionDelta = (LastPos:inverse()*CF)
			
			local Height = HoverDist+math.sin((tick()-Start)*4)*2.5
			
			for i,v in pairs(Craft.Forces:GetChildren()) do		
				local SensPos = ((CF*PositionDelta)*CFrame.new(v.Attachment0.Position))
				local Target = SensPos*CFrame.new(0,-Height,0)
				
				local Rayn = Ray.new(SensPos.p, (Target.p-SensPos.p).unit*Height)
				local Hit, Pos = workspace:FindPartOnRayWithIgnoreList(Rayn, ignoreList)
				
				local Dist = (Target.p-Pos).magnitude
				
				local yDif = (HoverHistory[v.Attachment0.Name]-Dist)*0.25
				local Force = -((Dist/Height)-yDif)*Power

				
				v.Force = Vector3.new(Force,0,0)
				
				
				HoverHistory[v.Attachment0.Name] = Dist
			end
			
			for i,v in pairs(Craft.Forces:GetChildren()) do	
				v.Force = v.Force*HoverThrottle
				
				if v.Force.X > 0 then
					v.Force = Vector3.new(v.Force.X^0.75,0,0)
				end
				
				bodykit.CenterOfMass["WheelPoint"..v.Index.Value].HoverEffect.Rate =  -math.min(v.Force.X, 0)/250
				bodykit.CenterOfMass["WheelPoint"..v.Index.Value].HoverEffect2.Rate = -math.min(v.Force.X, 0)/250
			end
			Craft.Turn.Force = Vector3.new(0,0,-PushVector.X*SteerForce)
			Craft.Push.Force = Vector3.new(-PushVector.Y*ThrottleForce,0,0)


			local Vel = Craft.Velocity
			local RotVel = Craft.RotVelocity

			local Direction = Craft.Forward.WorldCFrame*CFrame.Angles(0,math.rad(-90),0)
			local ForwardDirection = Direction*CFrame.new(0,0,-10)
			local ActualDirection = CFrame.new(Direction.p, Vector3.new(ForwardDirection.X, Direction.Y, ForwardDirection.Z)).lookVector
			
			local VelAmount = ((Handbrake and 0.85) or 0.9)
			local BiasAmount = ((Handbrake and 0.05) or 0.08)
			local LateralVel = Vector3.new(Vel.X, 0, Vel.Z)
			
			
			Craft.Velocity = (LateralVel*VelAmount)+(ActualDirection*(LateralVel.magnitude*BiasAmount))+Vector3.new(0,Vel.Y*(1-Delta),0)
			Craft.RotVelocity = Vector3.new(RotVel.X, RotVel.Y*(0.9-(Delta*(Handbrake and 4 or Delta*2))) , RotVel.Z)   -- This one helps prevent it from spinning out a bit too much. Also kinda fun to mess with if you want drifting
		else
			for i,v in pairs(Craft.Forces:GetChildren()) do
				v.Enabled = false
				v.Force = Vector3.new(0,0,0)
			end
			--Craft.Velocity = Vector3.new(0,0,0)
			--Craft.RotVelocity = Vector3.new(0,0,0)
		end
	end
	
	LastPos = Craft.CFrame
end)


seat.ChildRemoved:connect(function(child)
	if child.Name == "SeatWeld" then
		for i,v in pairs(Craft.Forces:GetChildren()) do
			v.Enabled = false
			v.Force = Vector3.new(0,0,0)
		end
		-- Turn off hover mode
		hovering = false
		upForce = false
		HoverThrottle = 0
		HoverHistory = {}
		
		bodykit.CenterOfMass.WheelPoint1.HoverEffect.Enabled = false
		bodykit.CenterOfMass.WheelPoint2.HoverEffect.Enabled = false
		bodykit.CenterOfMass.WheelPoint3.HoverEffect.Enabled = false
		bodykit.CenterOfMass.WheelPoint4.HoverEffect.Enabled = false
		
		repStorage:WaitForChild("Simchassis"):WaitForChild("RemoteEvents"):WaitForChild("HoverParticle"):FireServer(false, bodykit.CenterOfMass.WheelPoint1.HoverEffect,bodykit.CenterOfMass.WheelPoint2.HoverEffect, bodykit.CenterOfMass.WheelPoint3.HoverEffect, bodykit.CenterOfMass.WheelPoint4.HoverEffect)
		
		bodykit.CenterOfMass.WheelPoint1.HoverEffect2.Enabled = false
		bodykit.CenterOfMass.WheelPoint2.HoverEffect2.Enabled = false
		bodykit.CenterOfMass.WheelPoint3.HoverEffect2.Enabled = false
		bodykit.CenterOfMass.WheelPoint4.HoverEffect2.Enabled = false
		
		
		bodykit.CenterOfMass.WheelPoint1.HoverLight.Enabled = false
		bodykit.CenterOfMass.WheelPoint2.HoverLight.Enabled = false
		bodykit.CenterOfMass.WheelPoint3.HoverLight.Enabled = false
		bodykit.CenterOfMass.WheelPoint4.HoverLight.Enabled = false
		
		TweenAxle(chassis.Axles.BL, 90)
		

		-- Disable Turn and Push
		bodykit.Hover.Push.Enabled = false
		bodykit.Hover.Turn.Enabled = false
		
		-- Detach the functions from the InputManager
		InputManager.DetachFunctions({
			{DeloreanHover_InputBegan, "InputBegan", "DeloreanHover"},
			{Jump_InputBegan, "InputBegan", "Jump"}
		})
	end
end)

seat.Changed:connect(function(prop)
	if Player.Character and Player.Character:findFirstChild("Humanoid") and Player.Character.Humanoid.Sit then
		if prop == "Throttle" then
			if seat.Throttle > 0 then
				PushVector = Vector2.new(PushVector.X, 1)
			elseif seat.Throttle < 0 then
				PushVector = Vector2.new(PushVector.X, -1)
			elseif seat.Throttle == 0 then
				PushVector = Vector2.new(PushVector.X, 0)
			end
		end
		
		if prop == "Steer" then
			if seat.Steer > 0 then
				PushVector = Vector2.new(1, PushVector.Y)
			elseif seat.Steer < 0 then
				PushVector = Vector2.new(-1, PushVector.Y)
			elseif seat.Steer == 0 then
				PushVector = Vector2.new(0, PushVector.Y)
			end
		end
	end
end)

