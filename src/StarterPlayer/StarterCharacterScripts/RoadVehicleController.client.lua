local _VisualiseRaycast = false -- Prefix with _ since unused

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleModules = Modules:WaitForChild("Vehicle")
local Debris = game:GetService("Debris") -- Add Debris service

local carProps = require(VehicleModules:WaitForChild("VehiclePropertiesList"))
local VehiclePhysics = require(VehicleModules:WaitForChild("VehiclePhysics"))
local VehicleCamera = require(VehicleModules:WaitForChild("VehicleCamera"))
local VehicleEffects = require(VehicleModules:WaitForChild("VehicleEffects"))
local useState = require(Modules:WaitForChild("useState"))
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local PlrGui = player.PlayerGui
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

PlrGui.gaag.ag:ClearAllChildren()
PlrGui.gaag.ag2:ClearAllChildren()

-- Initialize humanoid with proper line breaks
local humanoid
local function initHumanoid()
    repeat
        task.wait()
    until char:FindFirstChild("Humanoid")
    return char.Humanoid
end
humanoid = initHumanoid()

local isBraking = false
local isBoosting = false
local activeVehicleState = nil
local activeVehicleCamera = nil -- Added for camera instance
local activeVehicleEffects = nil -- Added for effects instance
local activeBurnoutEffects = {} -- Table to store handles for continuous burnout effects { [wheelName]: {smoke=instance, sound=instance} }
local activeSkidTrails = {} -- Table to store handles for skid trails { [wheelName]: {trail=instance, attachment0=instance, attachment1=instance} }
local vehicleInputStates = nil -- To store references to the useState objects
local ownershipConnection = nil
local steeringThread = nil

-- Add per-wheel slip/skid state tracking
local _lastWheelSlipState = {} -- Prefix with _ since unused
local _lastWheelSkidState = {} -- Prefix with _ since unused

-- Add debounce for tire sounds and cooldown for car entry
local _slipTimers = {} -- Prefix with _ since unused
local lastCarEntryTime = 0
local CAR_ENTRY_COOLDOWN = 0.5
local _SLIP_DEBOUNCE = 0.12 -- Prefix with _ since unused

-- Define missing DEFAULT_PHYSICS_CONSTRAINTS
local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 2500,
    MIN_SUSPENSION_LENGTH = 2,
    MAX_LATERAL_FORCE = 1500,
    MAX_TRACTION_FORCE = 2000,
    STEERING_DAMPING = 5.0,
    STATIC_FRICTION_THRESHOLD = 1,
    WEIGHT_TO_FRICTION_MULT = 0.1,
    STATIC_FRICTION_COEFFICIENT = 5.0,
    PARKING_BRAKE_FORCE = 1000
}

-- Utility: get the main part of a wheel (handles Model, Part, or nested Model)
local function getWheelPart(wheel)
    if not wheel then return nil end
    if wheel:IsA("BasePart") then return wheel end
    if wheel:IsA("Model") then
        return wheel:FindFirstChild("Wheel") or
               wheel:FindFirstChildWhichIsA("BasePart") or
               wheel.PrimaryPart
    end
    return nil
end

local function getWheelMotor(wheelName, carModel)
    local chassisParts = carModel.Chassis:GetDescendants()
    for i, v in ipairs(chassisParts) do
        if v:IsA("Motor6D") then
            -- match the wheelName and motorname
            if v.Name == wheelName .. "_Wheel_Motor" or v.Name == wheelName .. "_Motor"  then
                return v
            end
        end
    end
    return nil
end

-- Create a separate function for visual updates that can run regardless of network ownership
local function updateWheelVisuals(carModel, wheelStates, physicsState)
    if not wheelStates then return end

    for wheelName, state in pairs(wheelStates) do
        local chassis = carModel:FindFirstChild("Chassis")
        local attach = chassis and chassis:FindFirstChild(wheelName .. "_Wheel")
        local wheel = attach and (attach:FindFirstChild("Wheel") or attach:FindFirstChild("Part") or attach:FindFirstChild("Model"))
        if wheel then
            local wheelPart = getWheelPart(wheel)
            if wheelPart then
                local motor = VehiclePhysics.getWheelMotor(wheelName, carModel)

                if motor and motor:IsA("Motor6D") then
                    -- Get base position and spring length from physics state
                    local basePos = attach.Position

                    -- Create initial position -- DONT OFFSET THIS IN BOTH THE LOOP AND THE UPDATE FUNCTION
                    local weldInitPos = CFrame.new(basePos) + Vector3.new(0,state.springLength,0) - Vector3.new(0, wheelPart.Size.Y /3, 0)

                    -- Apply steering for front wheels
                    if string.sub(wheelName,1,1)=='F' then
                        weldInitPos = weldInitPos * CFrame.Angles(0, -math.rad(physicsState.steeringAngle), 0)
                    end

                    -- Apply wheel rotation based on side (left/right)
                    motor.C0 = weldInitPos
                    local wheelRotation = if basePos.X > 0
                        then -state.wheelRotation
                        else state.wheelRotation

                    if basePos.X > 0 then
                        motor.C0 = motor.C0 * CFrame.Angles(wheelRotation, 0, 0) * CFrame.Angles(0, math.rad(180), 0)
                    else
                        motor.C0 = motor.C0 * CFrame.Angles(wheelRotation, 0, 0)
                    end
                end
            end
        end
    end
end

-- Create separate function for steering update loop
local function startSteeringUpdateLoop(seatPart, carModel, props, activeVehicleStateRef)
    local thread = coroutine.create(function()
        local lastSteerValue = 0
        local constraints = props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
        local steeringSensitivity = props.SteeringSensitivity or 1.0
        local steeringDamping = constraints.STEERING_DAMPING or 5.0

        while seatPart and carModel:IsDescendantOf(workspace) do
            local delta = RunService.RenderStepped:Wait()

            -- Get current steer value directly from VehicleSeat
            local currentSteer = seatPart.SteerFloat

            -- Only update if steering changed
            if currentSteer ~= lastSteerValue then
                -- Update steering angle in our physics state with proper damping
                local targetSteer = currentSteer * props.SteerAngle
                local steerLerpRate = delta * steeringSensitivity * (1/steeringDamping)

                -- Faster return to center (when steering input is 0)
                if currentSteer == 0 then
                    steerLerpRate = steerLerpRate * 2.5 -- Make centering 2.5x faster
                end

                activeVehicleStateRef.steeringAngle = activeVehicleStateRef.steeringAngle +
                    (targetSteer - activeVehicleStateRef.steeringAngle) * math.min(1, steerLerpRate)

                -- Update wheel visuals for steering
                for wheelName, _ in pairs(carProps.getWheelPositions(carModel)) do
                    local chassis = carModel:FindFirstChild("Chassis")
                    local attach = chassis and chassis:FindFirstChild(wheelName .. "_Wheel")
                    local wheel = attach and (attach:FindFirstChild("Wheel") or attach:FindFirstChild("Part") or attach:FindFirstChild("Model"))
                    local wheelPart = getWheelPart(wheel)
                    if wheelPart and string.sub(wheelName,1,1)=='F' then
                        local motor = getWheelMotor(wheelName, carModel)
                        if motor and motor:IsA("Motor6D") then
                            local basePos = carProps.getWheelPositions(carModel)[wheelName]

                            -- Get current spring length from physics state or use max
                            local springLength = activeVehicleStateRef.springLengthMemory[wheelName]
                                or props.SuspensionMaxLength

                            local weldInitPos = CFrame.new(basePos) + Vector3.new(0,springLength,0) - Vector3.new(0, wheelPart.Size.Y / 2, 0)
                            weldInitPos = weldInitPos * CFrame.Angles(0, -math.rad(activeVehicleStateRef.steeringAngle), 0)

                            -- Preserve wheel rotation but update steering
                            local currentRotation = if basePos.x > 0
                                then -activeVehicleStateRef.wheelRotations[wheelName]
                                else activeVehicleStateRef.wheelRotations[wheelName]

                            motor.C0 = weldInitPos
                            if basePos.x > 0 then
                                motor.C0 = motor.C0 * CFrame.Angles(0,0,0)
                                motor.C0 = motor.C0 * CFrame.Angles(currentRotation,0,0)
                            else
                                motor.C0 = motor.C0 * CFrame.Angles(currentRotation,0,0)
                                motor.C0 = motor.C0 * CFrame.Angles(0, math.rad(180), 0)
                            end
                        end
                    end
                end

                lastSteerValue = currentSteer
            end
        end
    end)

    coroutine.resume(thread)
    return thread
end

-- Clean up function to handle all disconnections and state resets
-- Module state variables
local simRoutine = nil
local carModel = nil
local function cleanupVehicle()
    if ownershipConnection then
        ownershipConnection:Disconnect()
        ownershipConnection = nil
    end

    if steeringThread then
        coroutine.close(steeringThread)
        steeringThread = nil
    end

    ContextActionService:UnbindAction("BrakeVehicle")
    ContextActionService:UnbindAction("ToggleParking")

    if vehicleInputStates then
        vehicleInputStates.Throttle:set(0)
        vehicleInputStates.Steer:set(0)
        vehicleInputStates.Braking:set(false)
    end

    activeVehicleState = nil
    vehicleInputStates = nil
    isBraking = false
    isBoosting = false
    if simRoutine then
        simRoutine:Disconnect();
    end

    -- Detach Camera
    if activeVehicleCamera then
        activeVehicleCamera:Detach()
        activeVehicleCamera = nil
    end

    -- Stop any continuous vehicle effects
    if activeVehicleEffects then
        -- Stop Burnout
        for _, handles in pairs(activeBurnoutEffects) do
            activeVehicleEffects:StopBurnoutEffect(handles)
        end
        activeBurnoutEffects = {}

        -- Stop and cleanup Skid Trails
        for _, handles in pairs(activeSkidTrails) do
            if handles.trail then
                handles.trail:Destroy()
            end
            if handles.attachment0 then
                handles.attachment0:Destroy()
            end
            if handles.attachment1 then
                handles.attachment1:Destroy()
            end
        end
        activeSkidTrails = {}

        activeVehicleEffects:CleanupSkidSounds(carModel)
        activeVehicleEffects = nil
    end

    print("[DEBUG] Vehicle control cleaned up.")
end

-- Type assertion for VehicleSeat properties
local function getVehicleInputs(seat: BasePart)
    local throttle = 0
    local steer = 0
    -- Cast to VehicleSeat and safely access properties
    if seat:IsA("VehicleSeat") then
        throttle = (seat :: VehicleSeat).ThrottleFloat
        steer = (seat :: VehicleSeat).SteerFloat
    end
    return throttle, steer
end

humanoid.Seated:Connect(function(isSeated, seat)
    if isSeated and seat then
        if seat:IsA("VehicleSeat") and seat:FindFirstAncestor('Vehicles') then
            carModel = seat.Parent
            local chassis = carModel:FindFirstChild("Chassis")
            if not chassis then return end

            print("[DEBUG] LocalPlayer is:", tostring(player))
            local id = carModel:GetAttribute("id")
            local props = carProps[id]

            -- Immediately start physics and input as soon as seated
            activeVehicleState = VehiclePhysics.createPhysicsState()
            vehicleInputStates = {
                Throttle = useState(0, "ThrottleInput", carModel),
                Steer = useState(0, "SteerInput", carModel),
                Braking = useState(false, "BrakingInput", carModel)
            }

            -- Attach Camera
            activeVehicleCamera = VehicleCamera -- Use the required module
            activeVehicleCamera:AttachToVehicle(carModel)

            -- Initialize Effects Module (can be done once or per vehicle)
            activeVehicleEffects = VehicleEffects.new() -- Use constructor instead of module directly

            steeringThread = startSteeringUpdateLoop(seat, carModel, props, activeVehicleState)
            -- Bind Brake Action (Space)
            ContextActionService:BindAction("BrakeVehicle", function(_actionName, inputState)
                if inputState == Enum.UserInputState.Begin then
                    isBraking = true
                    if vehicleInputStates then
                        vehicleInputStates.Braking:set(true)
                    end
                elseif inputState == Enum.UserInputState.End then
                    isBraking = false
                    if vehicleInputStates then
                        vehicleInputStates.Braking:set(false)
                    end
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.Space)
            -- Add Parking Brake Toggle (P key)
            ContextActionService:BindAction("ToggleParking", function(_actionName, inputState, _inputObject)
                if inputState == Enum.UserInputState.Begin and activeVehicleState then
                    activeVehicleState.isParked = not activeVehicleState.isParked
                    if activeVehicleState.isParked then
                        print("Parking brake engaged")
                    else
                        print("Parking brake released")
                    end
                end
                return Enum.ContextActionResult.Sink
            end, false, Enum.KeyCode.P)
            -- Main control loop (no ownership wait)

            simRoutine = RunService.Stepped:Connect(function(delta: number)
                if humanoid.Sit and seat:IsDescendantOf(workspace) then
                    local currentChassis = carModel:FindFirstChild("Chassis")
                    if not currentChassis then return end

                    local currentThrottle, currentSteer = getVehicleInputs(seat)
                    local currentBraking = isBraking
                    local currentBoosting = isBoosting
                    local currentSpeed = currentChassis.AssemblyLinearVelocity.Magnitude

                    if vehicleInputStates then
                        vehicleInputStates.Throttle:set(currentThrottle)
                        vehicleInputStates.Steer:set(currentSteer)
                    end
                    local wheelStates = VehiclePhysics.updateVehiclePhysics(
                        carModel,
                        activeVehicleState,
                        props,
                        delta,
                        currentThrottle,
                        currentSteer,
                        currentBraking,
                        currentBoosting,
                        props.PhysicsConstraints
                    )
                    updateWheelVisuals(carModel, wheelStates, activeVehicleState)

                    -- Trigger Vehicle Effects based on wheelStates and vehicle state
                    if activeVehicleEffects and wheelStates then
                        for wheelName, state in pairs(wheelStates) do
                            -- Find the wheel under the correct attachment in Chassis
                            local wheelChassis = carModel:FindFirstChild("Chassis") -- Renamed from chassis to avoid shadowing
                            local attach = wheelChassis and wheelChassis:FindFirstChild(wheelName .. "_Wheel")
                            local wheel = attach and (attach:FindFirstChild("Wheel") or attach:FindFirstChild("Part") or attach:FindFirstChild("Model"))
                            if wheel then
                                local wheelPart = getWheelPart(wheel)
                                if wheelPart then
                                    local isDoingBurnout = false
                                    local isDoingSkid = false

                                    -- Burnout Check (High throttle, high longitudinal slip, low speed, on ground)
                                    if currentThrottle > 1 and state.isSlipping and currentSpeed < 15 and state.onGround then
                                        isDoingBurnout = true
                                        if not activeBurnoutEffects[wheelName] then
                                            activeBurnoutEffects[wheelName] = activeVehicleEffects:PlayBurnoutEffect(carModel, wheelPart)
                                        end
                                    end
                                    if not isDoingBurnout and activeBurnoutEffects[wheelName] then
                                        activeVehicleEffects:StopBurnoutEffect(activeBurnoutEffects[wheelName])
                                        activeBurnoutEffects[wheelName] = nil
                                    end

                                    -- Manage Skid Trail
                                    if not isDoingBurnout then
                                        if state.isSkidding and state.onGround and currentSpeed > 20 and math.abs(state.lateralSlipRatio) > 0.8 then

                                            isDoingSkid = true
                                            local skidDirection = currentChassis.CFrame.RightVector * math.sign(state.lateralVelocityX)
                                            local contactPoint = wheelPart.Position - Vector3.new(0, wheelPart.Size.Y / 2, 0)

                                            if not activeSkidTrails[wheelName] then
                                                -- Create Attachments
                                                local att0 = Instance.new("Attachment")
                                                att0.Name = wheelName .. "_SkidAtt0"
                                                att0.Parent = workspace.Terrain
                                                att0.WorldPosition = contactPoint

                                                local att1 = Instance.new("Attachment")
                                                att1.Name = wheelName .. "_SkidAtt1"
                                                att1.Parent = workspace.Terrain
                                                att1.WorldPosition = contactPoint - skidDirection * 0.1 -- Start slightly behind

                                                -- Create Trail
                                                local trail = activeVehicleEffects:createEffect("TireMarkTrail", workspace.Terrain, att0, att1)
                                                if trail then
                                                    trail.Enabled = true
                                                    activeSkidTrails[wheelName] = { trail = trail, attachment0 = att0, attachment1 = att1 }
                                                    activeVehicleEffects:PlaySkidEffect(carModel, wheelPart, skidDirection)
                                                else
                                                    att0:Destroy()
                                                    att1:Destroy()
                                                end
                                            else
                                                -- Update existing attachments
                                                local handles = activeSkidTrails[wheelName]
                                                handles.attachment0.WorldPosition = contactPoint
                                                handles.attachment1.WorldPosition = contactPoint - skidDirection * 0.1
                                                -- Ensure trail is enabled if it was somehow disabled
                                                if not handles.trail.Enabled then
                                                    handles.trail.Enabled = true
                                                end
                                            end
                                        end
                                    end

                                    -- Stop Skid Trail if conditions are no longer met
                                    if not isDoingSkid and activeSkidTrails[wheelName] then
                                        local handles = activeSkidTrails[wheelName]

                                        print("[DEBUG] Skid END for wheel:", wheelName)
                                        activeVehicleEffects:StopSkidSound(carModel, wheelPart)

                                        if handles.trail then
                                            handles.trail.Enabled = false
                                        end
                                        -- Disable first
                                        -- Use Debris to clean up after trail fades
                                        if handles.trail then
                                            Debris:AddItem(handles.trail, handles.trail.Lifetime + 0.5)
                                        end
                                        if handles.attachment0 then
                                            Debris:AddItem(handles.attachment0, handles.trail.Lifetime + 0.5)
                                        end
                                        if handles.attachment1 then
                                            Debris:AddItem(handles.attachment1, handles.trail.Lifetime + 0.5)
                                        end
                                        activeSkidTrails[wheelName] = nil
                                    end

                                    -- Play other effects only if not doing a burnout or skid
                                    if not isDoingBurnout and not isDoingSkid then
                                        -- Skidding Effect (Lateral Slip

                                        local _lateralSpeed = math.abs(state.lateralVelocityX) -- Prefix with _ since unused
                                        local forwardSpeed = currentChassis.AssemblyLinearVelocity.Magnitude

                                        if (state.isSkidding and state.onGround) and (forwardSpeed > 20
                                            and math.abs(state.lateralSlipRatio) > 0.8) then
                                            print("[DEBUG] Skid START for wheel:", wheelName)
                                            activeVehicleEffects:PlaySkidSound(carModel, wheelPart)
                                            isDoingSkid = true
                                            -- Calculate skid direction (vehicle's right vector, scaled by lateral velocity direction)
                                            local skidDirection = currentChassis.CFrame.RightVector * math.sign(state.lateralVelocityX)
                                            activeVehicleEffects:PlaySkidEffect(carModel, wheelPart, skidDirection)
                                        end

                                        --[[-- Slipping Effect (Longitudinal Slip - e.g., braking lockup or moderate acceleration slip)
                                        -- Only play if not skidding (to avoid overlapping sounds/effects)
                                        if not isDoingSkid and state.isSlipping and state.onGround and currentSpeed > 5 then
                                            activeVehicleEffects:PlaySlipEffect(carModel, wheelPart)
                                        end]]

                                        -- Gravel/Surface Effect
                                        if state.onGround and currentSpeed > 20 then -- Only play if moving
                                            if state.surfaceMaterial == Enum.Material.Ground or state.surfaceMaterial == Enum.Material.Sand or state.surfaceMaterial == Enum.Material.Mud then
                                                activeVehicleEffects:PlayGravelEffect(carModel, wheelPart)
                                            end
                                            -- TODO: Add checks for other surface types if needed
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    cleanupVehicle()
                end
            end)
        end
    end
end)

-- Handle cleanup when player exits vehicle
humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
    if not humanoid.Sit then
        cleanupVehicle()
    end
end)

-- Handle F key for entering vehicles
ContextActionService:BindAction("EnterVehicle", function(_, inputState)
    if inputState ~= Enum.UserInputState.Begin then return end
    if humanoid.Sit then
        -- If seated, pressing F exits the car
        local seatPart = humanoid.SeatPart
        if seatPart and seatPart:IsA("BasePart") then
            local exitOffset = seatPart.CFrame.RightVector * 0 -- 4 studs to the right of the seat
            local exitPosition = seatPart.Position + exitOffset + Vector3.new(0, 10, 0) -- 2 studs above ground
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(exitPosition, exitPosition + seatPart.CFrame.LookVector)
            end
        end
        humanoid.Sit = false
        return
    end
    -- Car entry cooldown
    if tick() - lastCarEntryTime < CAR_ENTRY_COOLDOWN then return end
    lastCarEntryTime = tick()
    -- If not seated, try to enter the nearest car
    game.ReplicatedStorage.AskForDoor:FireServer()
    task.wait(0.2)
    local nearestcar, nearestdist = nil, 24
    local vehicles = workspace.Vehicles:GetChildren()
    for i = 1, #vehicles do
        local v = vehicles[i]
        local chassis = v:FindFirstChild("Chassis")
        if not chassis then continue end
        local dist = (chassis.Position - char.HumanoidRootPart.Position).Magnitude
        if dist < nearestdist then
            nearestcar = v
            nearestdist = dist
        end
    end
    if nearestcar then
        local nearestseat, seatDist = nil, nearestdist
        for _, v in pairs(nearestcar:GetChildren()) do
            if (v:IsA('VehicleSeat') or v:IsA("Seat")) and not v.Occupant then
                local dist = (v.Position - char.HumanoidRootPart.Position).Magnitude
                if dist < seatDist then
                    nearestseat = v
                    seatDist = dist
                end
            end
        end
        if nearestseat then
            local curCFrame = char.HumanoidRootPart.CFrame
            nearestseat:Sit(humanoid)
            if nearestseat:IsA("VehicleSeat") then
                local seatweld = nearestseat:FindFirstChild("SeatWeld")
                if seatweld then
                    local oldC0 = seatweld.C0
                    local oldC1 = seatweld.C1
                    seatweld.C0 = nearestseat.CFrame:ToObjectSpace(curCFrame)
                    seatweld.C1 = CFrame.new()
                    TweenService:Create(seatweld, TweenInfo.new(0.35), {
                        C1 = oldC1,
                        C0 = oldC0
                    }):Play()
                    task.wait(0.2)
                    local chassis = nearestcar:FindFirstChild("Chassis")
                    local hinge = chassis and chassis:FindFirstChild(nearestseat.Name)
                    if hinge and hinge:IsA("HingeConstraint") then
                        hinge.TargetAngle = 0
                    end
                end
            end
        end
    end
end, false, Enum.KeyCode.F)

-- Handle L key for lights
ContextActionService:BindAction("lightButton", function(_, inputState)
    if humanoid.SeatPart and inputState == Enum.UserInputState.Begin then
        game.ReplicatedStorage.SwitchLight:FireServer()
    end
end, false, Enum.KeyCode.L)