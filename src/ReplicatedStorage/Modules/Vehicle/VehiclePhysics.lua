local VehiclePhysics = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleModules = Modules:WaitForChild("Vehicle")

local carProps = require(VehicleModules:WaitForChild("VehiclePropertiesList"))
local RunService = game:GetService("RunService")

-- Constants
local WHEEL_ROTATION_SCALE = 1/56 -- Current scale factor from velocity to rotation
local RAYCAST_EXTRA_LENGTH = 2.0 -- How much further to cast the ray beyond max suspension travel

local DEFAULT_PHYSICS_CONSTRAINTS = {
    MAX_SUSPENSION_FORCE = 2500, -- Reduced from 5000
    MIN_SUSPENSION_LENGTH = 2.0, -- Increased from 0.2 for more stable suspension
    MAX_LATERAL_FORCE = 1500, -- Reduced from 2000
    MAX_TRACTION_FORCE = 2000, -- Reduced from 2500
    STEERING_DAMPING = 50.0,
    STATIC_FRICTION_THRESHOLD = 1,
    WEIGHT_TO_FRICTION_MULT = 0.4,
    STATIC_FRICTION_COEFFICIENT = 10.0,
    PARKING_BRAKE_FORCE = 1000
}

type PhysicsConstraints = {
    MAX_SUSPENSION_FORCE: number,
    MIN_SUSPENSION_LENGTH: number, -- Added type
    MAX_LATERAL_FORCE: number,
    MAX_TRACTION_FORCE: number,
    STEERING_DAMPING: number,
    STATIC_FRICTION_THRESHOLD: number,
    WEIGHT_TO_FRICTION_MULT: number,
    STATIC_FRICTION_COEFFICIENT: number,
    PARKING_BRAKE_FORCE: number
}

type VehicleProps = {
    SuspensionMaxLength: number,
    wheelRadius: number,
    Stiffness: number,
    Damper: number,
    wheelFriction: number,
    torque: number,
    MaxSpeed: number,
    SteerAngle: number,
    driverSeatName: string,
    brakeForce: number?,
    BoostForce: number?,
    PhysicsConstraints: PhysicsConstraints,
    SteeringSensitivity: number?
}

type PhysicsState = {
    springLengthMemory: {[string]: number},
    steeringAngle: number,
    wheelRotations: {[string]: number},
    lastUpdateTime: number,
    velocity: Vector3,
    isParked: boolean,
    wheelVelocities: {[string]: Vector3}
}

function VehiclePhysics.createPhysicsState(): PhysicsState
    return {
        springLengthMemory = {},
        steeringAngle = 0,
        wheelRotations = {},
        lastUpdateTime = os.clock(),
        velocity = Vector3.new(0, 0, 0),
        isParked = false,
        wheelVelocities = {}
    }
end

-- Move getWheelMotor to the top level since it's used across modules
function VehiclePhysics.getWheelMotor(wheelName, carModel)
    local chassisParts = carModel.Chassis:GetDescendants()
    for _, v in ipairs(chassisParts) do
        if v:IsA("Motor6D") then
            if v.Name == wheelName .. "_Wheel_Motor" or v.Name == wheelName .. "_Motor" then
                return v
            end
        end
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

-- Pass constraints down
function VehiclePhysics.updateVehiclePhysics(carModel: Model, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, steerInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel:FindFirstChild("Chassis")
    if not carPrim then return end

    -- Calculate car mass and center of mass
    local totalMass = 0
    local centerOfMass = Vector3.new(0, 0, 0)
    for _, part in pairs(carModel:GetDescendants()) do
        if part:IsA("BasePart") then
            totalMass += part.Mass
            centerOfMass += part.Position * part.Mass
        end
    end
    centerOfMass = centerOfMass / totalMass

    -- Apply steering with sensitivity and damping
    local targetSteerAngle = steerInput * props.SteerAngle
    local steeringSensitivity = props.SteeringSensitivity or 1.0
    local steeringDamping = constraints.STEERING_DAMPING or 5.0
    local steerLerpRate = delta * steeringSensitivity * (1/steeringDamping*4)
    if steerInput == 0 then
        steerLerpRate = steerLerpRate * 5 -- Centering is 5x faster
        physicsState.steeringAngle = physicsState.steeringAngle +
            (0 - physicsState.steeringAngle) * math.min(1, steerLerpRate)
    else
        physicsState.steeringAngle = physicsState.steeringAngle +
            (targetSteerAngle - physicsState.steeringAngle) * math.min(1, steerLerpRate)
    end

    -- Get car's current velocity
    local carVelocity = carPrim.AssemblyLinearVelocity
    local speed = carVelocity.Magnitude

    -- Determine if we should enter parking/static friction mode
    local isNearlyStatic = speed < (constraints.STATIC_FRICTION_THRESHOLD or 5)
    if isNearlyStatic and (isBraking or physicsState.isParked) then
        physicsState.isParked = true
    elseif throttleInput ~= 0 or not isBraking then
        physicsState.isParked = false
    end

    local forces = {}
    local wheelStates = {}

    -- Use module-level getWheelPositions function
    for wheelName, originalPosition in pairs(carProps.getWheelPositions(carModel)) do
        local wheelState = VehiclePhysics.calculateWheelPhysics(
            carModel,
            wheelName,
            originalPosition,
            physicsState,
            props,
            delta,
            throttleInput,
            isBraking,
            isBoosting,
            constraints
        )

        wheelStates[wheelName] = wheelState
        if wheelState.forces then
            table.insert(forces, wheelState.forces)
        end
    end

    -- Apply accumulated forces
    for _, force in ipairs(forces) do
        carPrim:ApplyImpulseAtPosition(
            force.suspensionForce + force.lateralForce + force.tractionForce,
            force.applicationPoint
        )
    end

    return wheelStates
end

-- Accept constraints
function VehiclePhysics.calculateWheelPhysics(carModel: Model, wheelName: string, wheelPos: Vector3, physicsState: PhysicsState, props: VehicleProps, delta: number, throttleInput: number, isBraking: boolean, isBoosting: boolean, constraints: PhysicsConstraints)
    -- Clamp delta time to prevent extreme values during lag spikes
    local MAX_DELTA = 1/20 -- Don't allow delta to be larger than 1/20th of a second for physics stability
    local clampedDelta = math.min(delta, MAX_DELTA)

    constraints = constraints or props.PhysicsConstraints or DEFAULT_PHYSICS_CONSTRAINTS
    local carPrim = carModel:FindFirstChild("Chassis")
    local carCFrame = carPrim.CFrame

    -- On the server, only allow boost/brake if a player is in the seat (Keep this logic)
    if RunService:IsServer() then
        local seat = carModel:FindFirstChildOfClass('VehicleSeat')
        local occupant = seat and seat.Occupant
        local isPlayerInSeat = false
        if occupant then
            local player = game.Players:GetPlayerFromCharacter(occupant.Parent)
            isPlayerInSeat = player ~= nil
        end
        if not isPlayerInSeat then
            isBraking = false
            isBoosting = false
        end
    end

    -- Initialize rotation for this wheel if not exists
    if not physicsState.wheelRotations[wheelName] then
        physicsState.wheelRotations[wheelName] = 0
    end

    -- Setup raycast from the actual wheel position (no additional offset)
    local rayOrigin = carCFrame:ToWorldSpace(CFrame.new(wheelPos + Vector3.new(0, props.SuspensionMaxLength, 0))).p
    local rayLength = props.SuspensionMaxLength + props.wheelRadius + RAYCAST_EXTRA_LENGTH
    local rayDirection = -carCFrame.UpVector * rayLength
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {carModel}
    local raycast = workspace:Raycast(rayOrigin, rayDirection, rayParams)

    -- Base wheel orientation
    local wheelDirCFrame = CFrame.lookAt(Vector3.zero, carCFrame.LookVector, carCFrame.UpVector)

    -- Apply steering for front wheels
    if string.sub(wheelName, 1, 1) == 'F' then
        wheelDirCFrame = wheelDirCFrame * CFrame.Angles(0, -math.rad(physicsState.steeringAngle), 0)
    end

    -- Get wheel velocity at the actual ground contact point
    local velocityCheckPos = if raycast
        then raycast.Position
        else rayOrigin - carCFrame.UpVector * (props.SuspensionMaxLength + props.wheelRadius)

    local wheelVelocity = carPrim:GetVelocityAtPosition(velocityCheckPos)
    local LocalVelocity = wheelDirCFrame:ToObjectSpace(CFrame.new(wheelVelocity))

    -- Update wheel rotation based on velocity
    local rotationDelta = LocalVelocity.z * WHEEL_ROTATION_SCALE
    physicsState.wheelRotations[wheelName] += rotationDelta

    if raycast then
        local RaycastDistance = (rayOrigin - raycast.Position).magnitude
        local effectiveDistance = RaycastDistance - props.wheelRadius -- Only subtract once for actual physics
        local surfaceMaterial = raycast.Material

        if effectiveDistance <= props.SuspensionMaxLength then
            local SpringLength = math.clamp(effectiveDistance,
                constraints.MIN_SUSPENSION_LENGTH,
                props.SuspensionMaxLength)

            physicsState.springLengthMemory[wheelName] = SpringLength

            -- Calculate Stiffness Force (based on compression)
            local StiffnessForce = props.Stiffness * (props.SuspensionMaxLength - SpringLength)

            -- Calculate Velocity-Based Damper Force
            local chassisWheelPointVelocity = carPrim:GetVelocityAtPosition(rayOrigin)
            local groundContactVelocity = Vector3.new(0,0,0) -- Assume terrain/static part
            if raycast.Instance and raycast.Instance.Anchored == false then
                 -- If hitting a non-anchored part, get its velocity at the contact point
                 groundContactVelocity = raycast.Instance:GetVelocityAtPosition(raycast.Position)
            end
            -- Calculate relative velocity along the suspension axis (car's UpVector)
            local relativeVelocityAlongSuspension = (chassisWheelPointVelocity - groundContactVelocity):Dot(carCFrame.UpVector)
            -- Damping force opposes this relative velocity
            local DamperForce = props.Damper * relativeVelocityAlongSuspension

            -- Calculate Total Suspension Force Vector (Stiffness + Damping)
            -- Both forces act along the car's UpVector. Stiffness pushes up based on compression.
            -- Damping pushes up if compressing (negative relative velocity) and down if extending (positive relative velocity).
            local SuspensionForceVec3 = carCFrame.UpVector * (StiffnessForce - DamperForce) -- Subtraction handles the opposing force direction correctly

            -- Optional: Clamp the total suspension force magnitude
            local suspensionForceMagnitude = SuspensionForceVec3.Magnitude
            if suspensionForceMagnitude > constraints.MAX_SUSPENSION_FORCE then
                SuspensionForceVec3 = SuspensionForceVec3.Unit * constraints.MAX_SUSPENSION_FORCE
                -- print("Clamped suspension force for wheel:", wheelName) -- Debugging
            end

            -- Lateral Force (Xforce) - unchanged
            local Xforce = wheelDirCFrame.RightVector * -LocalVelocity.x * props.wheelFriction

            -- Traction Force (Zforce) - calculation logic mostly unchanged, uses throttle/braking/boost
            local baseZForce = throttleInput * props.torque *
                (math.sign(-LocalVelocity.z) == math.sign(throttleInput) and
                (1 - math.min(1, math.abs(LocalVelocity.z) / props.MaxSpeed)) or 1)

            if isBraking then
                local brakeForceMagnitude = -(props.brakeForce or 100)
                if math.abs(LocalVelocity.z) > 0.5 then
                    local brakingForceComponent = -math.sign(LocalVelocity.z) * brakeForceMagnitude * math.min(1, math.abs(LocalVelocity.z) / (props.MaxSpeed or 1))
                    baseZForce = baseZForce + brakingForceComponent * clampedDelta
                else
                    isBraking = false
                end
            end

            if isBoosting then
                local boostForce = props.BoostForce or 200
                baseZForce = baseZForce + boostForce
            end

            baseZForce = math.clamp(baseZForce, -constraints.MAX_TRACTION_FORCE * 2, constraints.MAX_TRACTION_FORCE * 2)
            local Zforce = wheelDirCFrame.LookVector * baseZForce

            -- Weight distribution and friction calculations (updated for new structure)
            local weightOnWheel = carPrim.Mass * workspace.Gravity / 4 -- Assume equal distribution for 4 wheels

            local baseFriction = props.wheelFriction
            local weightFrictionMult = constraints.WEIGHT_TO_FRICTION_MULT or 0.1
            local effectiveFriction = baseFriction + (weightOnWheel * weightFrictionMult)

            if physicsState.isParked then
                effectiveFriction *= constraints.STATIC_FRICTION_COEFFICIENT or 2.0
            end

            -- Parking brake impulse (skip wheelPart logic, just skip impulse for now)

            -- @TODO: use the wheelDirCFrame cframe orientation that weve calculated to set the wheel's rotation and steering angles.
            -- note: we use these wheels isnide the attachments but the motor6D is outside that instance, its inside the chassis.
            -- im not sure if that means were moving or turning the chassis or wheel... but you know that!

            -- Slip calculations (unchanged)
            local wheelSurfaceSpeed = physicsState.wheelRotations[wheelName] * props.wheelRadius
            local groundSpeedAlongWheel = LocalVelocity.z
            local longitudinalSlipRatio = 0
            if math.abs(groundSpeedAlongWheel) > 0.3 then
                longitudinalSlipRatio = (wheelSurfaceSpeed - groundSpeedAlongWheel) / math.abs(groundSpeedAlongWheel)
            elseif math.abs(wheelSurfaceSpeed) > 0.3 then
                longitudinalSlipRatio = math.sign(wheelSurfaceSpeed)
            end
            local isSlippingLongitudinally = math.abs(longitudinalSlipRatio) > 0.35

            local lateralVelocity = LocalVelocity.x
            local lateralSlipRatio = 0
            local forwardSpeed = math.abs(LocalVelocity.z)
            if forwardSpeed > 1.0 then
                lateralSlipRatio = math.abs(lateralVelocity) / forwardSpeed
            end
            local isSkidding = lateralSlipRatio > 0.1

            return {
                onGround = true,
                forces = {
                    suspensionForce = SuspensionForceVec3,
                    lateralForce = Xforce,
                    tractionForce = Zforce,
                    applicationPoint = raycast.Position
                },
                springLength = SpringLength, -- No additional offset here since Motor6D handles it
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = effectiveFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = longitudinalSlipRatio,
                isSlipping = isSlippingLongitudinally,
                lateralVelocityX = lateralVelocity,
                lateralSlipRatio = lateralSlipRatio,
                isSkidding = isSkidding,
                surfaceMaterial = surfaceMaterial
            }
        else
            -- Ray hit ground, but BEYOND suspension range - treat as air for physics
            physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
            return {
                onGround = false, -- No forces applied
                springLength = props.SuspensionMaxLength,
                wheelRotation = physicsState.wheelRotations[wheelName],
                friction = props.wheelFriction,
                isParked = physicsState.isParked,
                longitudinalSlipRatio = 0,
                isSlipping = false,
                lateralVelocityX = 0,
                lateralSlipRatio = 0,
                isSkidding = false,
                surfaceMaterial = Enum.Material.Air
            }
        end
    else
        -- Air physics (ray didn't hit anything)
        physicsState.springLengthMemory[wheelName] = props.SuspensionMaxLength
        return {
            onGround = false,
            springLength = props.SuspensionMaxLength,
            wheelRotation = physicsState.wheelRotations[wheelName],
            friction = props.wheelFriction,
            isParked = physicsState.isParked,
            longitudinalSlipRatio = 0,
            isSlipping = false,
            lateralVelocityX = 0,
            lateralSlipRatio = 0,
            isSkidding = false,
            surfaceMaterial = Enum.Material.Air
        }
    end
end

-- Utility to create a Motor6D between two parts
local function createMotor6D(part0, part1, name)
	local motor = Instance.new("Motor6D", part0)
	motor.Name = name or (part0.Name .. "_to_" .. part1.Name)
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	motor.C1 = CFrame.new()
	return motor
end

function VehiclePhysics.setupWheels(carModel)
    local chassis = carModel:FindFirstChild("Chassis")
    assert(chassis, "Chassis not found")
    local wheelNames = {"FL_Wheel", "FR_Wheel", "RL_Wheel", "RR_Wheel"}

    -- Get vehicle properties for wheel radius
    local id = carModel:GetAttribute("id")
    local props = carProps[id]
    if not props then return end

    for _, attachName in ipairs(wheelNames) do
        local attach = chassis:FindFirstChild(attachName)
        if attach then
            local wheel = attach:FindFirstChild("Wheel") or attach:FindFirstChild("Part") or attach:FindFirstChild("Model")
            if wheel then
                local partToWeld = wheel:IsA("Model") and (wheel.PrimaryPart or wheel:FindFirstChildWhichIsA("BasePart")) or wheel
                if partToWeld then
                    -- Remove existing constraints
                    for _, obj in ipairs(partToWeld:GetChildren()) do
                        if obj:IsA("Motor6D") or obj:IsA("WeldConstraint") then
                            obj:Destroy()
                        end
                    end

                    -- Create Motor6D with correct initial orientation and offset
                    local motor = getWheelMotor(attachName, carModel) or createMotor6D(chassis, partToWeld, attachName.."_Motor")

                    -- Calculate base orientation plus vertical offset for wheelRadius
                    --local wheelOffset = CFrame.new(0, props.wheelRadius, 0) -- Offset wheel up by wheelRadius
					local wheelOffset = Vector3.new(0, props.wheelRadius, 0) * -1
                    if attach.Position.X > 0 then
                        motor.C0 = attach.CFrame:ToObjectSpace(partToWeld.CFrame) * CFrame.new(wheelOffset) * CFrame.Angles(0, math.rad(180), 0)
                    else
                        motor.C0 = attach.CFrame:ToObjectSpace(partToWeld.CFrame) * CFrame.new(wheelOffset)
                    end
                    motor.C1 = CFrame.new()
                    partToWeld.Anchored = false
                end

                -- Unanchor all parts in wheel model
                if wheel:IsA("Model") then
                    for _, part in ipairs(wheel:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                            part.Anchored = false
                        end
                    end
                end
            end
        end
    end
    chassis.Anchored = false
end

return VehiclePhysics