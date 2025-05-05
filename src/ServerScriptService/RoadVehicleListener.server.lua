local LastStuff = {
	FL = {},
	FR = {},
	RL = {},
	RR = {},
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleModules = Modules:WaitForChild("Vehicle")

local carProps = require(VehicleModules:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(VehicleModules:WaitForChild("VehiclePhysics"))
local useState = require(Modules:WaitForChild("useState"))

local VehicleFolder = workspace.Vehicles
local AllCarsMemory = {}
local ExistingCarsTable = {}
local PhysicsStates = {} -- Store physics state for each vehicle
local VehicleInputStates = {} -- Store useState objects for each vehicle

local function AddCar(obj, _cprops)
    -- Remove existing Wheels folder or wheel parts to prevent duplicates
    local existingWheels = obj:FindFirstChild("Wheels")
    if existingWheels then
        existingWheels:Destroy()
    end
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("Model") and child.Name:match("^%a%a$") then -- e.g., FL, FR, RL, RR
            child:Destroy()
        end
    end

    local chassis = obj:FindFirstChild("Chassis")
    if not chassis then return end

    -- Initialize physics state for this vehicle
    local id = obj:GetAttribute("id")
    if id then
        PhysicsStates[obj] = VehiclePhysics.createPhysicsState()
    end

    -- Set up the wheels immediately on the server
    VehiclePhysics.setupWheels(obj)

    -- Handle seat occupancy changes
    local driverSeat = obj:FindFirstChildOfClass('VehicleSeat')
    if driverSeat then
        driverSeat:GetPropertyChangedSignal('Occupant'):Connect(function()
            local occ = driverSeat.Occupant
            if not chassis then return end
            if occ then
                local player = game.Players:GetPlayerFromCharacter(occ.Parent)
                if player then
                    chassis:SetNetworkOwner(player)
                end
            else
                chassis:SetNetworkOwner(nil)
            end
        end)
    end

    table.insert(ExistingCarsTable, obj)
end

-- Update ChildAdded listener
VehicleFolder.ChildAdded:Connect(function(child)
    if child:IsA("Model") then
        task.wait() -- Wait for all properties to replicate
        AddCar(child)
    end
end)

local function SpawnCar(carName)
    local props = carProps[carName]
    if not props then return end

    local clonedCar = props.model:Clone()
    clonedCar.Parent = workspace.Vehicles
    clonedCar:SetAttribute("id", carName)

    local spawnPos = Vector3.new(math.random(-50,50), 10, math.random(-50,50))
    clonedCar:PivotTo(CFrame.new(spawnPos))

    AddCar(clonedCar, props)

    local chassis = clonedCar:FindFirstChild("Chassis")
    if chassis then
        task.spawn(function()
            pcall(function()
                chassis:SetNetworkOwner(nil)
            end)
        end)
    end

    return clonedCar
end

local WhatPlayerCarTab = {}
game.Players.PlayerAdded:Connect(function(p)

	local isP = p.MembershipType == Enum.MembershipType.Premium

	p.CharacterRemoving:Connect(function(c)

		if WhatPlayerCarTab[p] then
			WhatPlayerCarTab[p]:Destroy()
		end
	end)
end)

local function getAllLightTypesInside(parent: Instance): {Light}
	local lightObjects = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
			table.insert(lightObjects, child)
		else --if it's a part, it can have lights inside
			local foundLights = getAllLightTypesInside(child)
			for _, x in ipairs(foundLights) do
				table.insert(lightObjects, x)
			end
		end
	end
	return lightObjects
end

local function switchLightsInside(parent: Instance, state: true|false)
	local lightObjects = getAllLightTypesInside(parent)
	for _, x in ipairs(lightObjects) do
		x.Enabled = true
	end
    return;
end

local LIGHTS_STATE = true
game.ReplicatedStorage.SwitchLight.OnServerEvent:Connect(function(plr)

	if plr.Character and plr.Character.Humanoid.SeatPart and plr.Character.Humanoid.SeatPart:FindFirstAncestor('Vehicles')then

		local partsModel = plr.Character.Humanoid.SeatPart:FindFirstAncestorOfClass('Model').RootPart
		LIGHTS_STATE = not LIGHTS_STATE;
		switchLightsInside(partsModel.HLL,LIGHTS_STATE)
		switchLightsInside(partsModel.TLL,LIGHTS_STATE)
		switchLightsInside(partsModel.HLR,LIGHTS_STATE)
		switchLightsInside(partsModel.TLR,LIGHTS_STATE)
	end
end)


game.ReplicatedStorage.AskForDoor.OnServerEvent:Connect(function(plr)
    if plr.Character then
        local nearestcar, nearestdist = nil, 10
        for _, v in pairs(workspace.Vehicles:GetChildren()) do
            local chassis = v:FindFirstChild("Chassis")
            if chassis then
                local dist = (chassis.Position - plr.Character.HumanoidRootPart.Position).magnitude
                if dist < nearestdist then
                    nearestcar = v
                    nearestdist = dist
                end
            end
        end

        if nearestcar then
            local nearestseat, seatDist = nil, nearestdist
            for _, v in pairs(nearestcar:GetChildren()) do
                if (v:IsA('VehicleSeat') or v:IsA("Seat")) and not v.Occupant then
                    local dist = (v.Position - plr.Character.HumanoidRootPart.Position).magnitude
                    if dist < seatDist then
                        nearestseat = v
                        seatDist = dist
                    end
                end
            end

            if nearestseat then
                -- Open door using hinge constraint
                local chassis = nearestcar:FindFirstChild("Chassis")
                if chassis then
                    local curHingeConstraint = chassis[nearestseat.Name]
                    if curHingeConstraint then
                        curHingeConstraint.TargetAngle = 90
                        task.wait(0.5)
                    end
                end
            end
        end
    end
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpawnPlayerCarEvent = ReplicatedStorage:WaitForChild("SpawnPlayerCar")

-- Table to track which car belongs to which player
local PlayerCars = {}

game.Players.PlayerRemoving:Connect(function(player)
	if PlayerCars[player] then
		PlayerCars[player]:Destroy()
		PlayerCars[player] = nil
	end
end)

SpawnPlayerCarEvent.OnServerEvent:Connect(function(player)
	if PlayerCars[player] and PlayerCars[player].Parent then
		-- remove the old car

		PlayerCars[player]:Destroy()
		PlayerCars[player] = nil

	end
	-- Get all available car names from carProps (only those with a 'model' property)
	local carNames = {}
	for name, value in pairs(carProps) do
		if type(value) == "table" and value.model then
			table.insert(carNames, name)
		end
	end
	if #carNames == 0 then return end
	local randomCarName = carNames[math.random(1, #carNames)]
	local car = SpawnCar(randomCarName)
	if car then
		car:SetAttribute("owner", player.Name)
		PlayerCars[player] = car
		-- Optionally move car to player spawn location
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			car:MoveTo(player.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0))
		end
	end
end)

local RunService = game:GetService("RunService")
local PHYSICS_WAKE_INTERVAL = 0.4 -- seconds

local lastWakeNudge = {}

RunService.Heartbeat:Connect(function(delta)
    local now = os.clock()
    local success, err = pcall(function()
        for _, carModel in pairs(ExistingCarsTable) do
            if not carModel or not carModel.Parent then continue end

            local chassis = carModel:FindFirstChild("Chassis")
            if not chassis then continue end

            lastWakeNudge[carModel] = lastWakeNudge[carModel] or 0
            if now - lastWakeNudge[carModel] > PHYSICS_WAKE_INTERVAL then
                chassis:ApplyImpulse(Vector3.new(1e-3, 0, 0))
                lastWakeNudge[carModel] = now
            end

            -- Update vehicle physics on the server
            local id = carModel:GetAttribute("id")
            local props = carProps[id]
            if not props then continue end

            -- Get input states from useState objects
            local inputStates = VehicleInputStates[carModel]
            local throttle = 0
            local steer = 0
            local braking = false

            if inputStates then
                throttle = inputStates.Throttle:get()
                steer = inputStates.Steer:get()
                braking = inputStates.Braking:get()
            end

            -- Update physics and visuals
            local physicsState = PhysicsStates[carModel]
            if physicsState then
                VehiclePhysics.updateVehiclePhysics(
                    carModel,
                    physicsState,
                    props,
                    delta,
                    throttle,
                    steer,
                    braking,
                    false, -- boosting not handled on server
                    props.PhysicsConstraints
                )
                -- Remove or implement updateWheelVisuals in VehiclePhysics module
            end


        end
    end)
    if not success then
        warn("[Vehicle Loop Error]:", err)
    end
end)