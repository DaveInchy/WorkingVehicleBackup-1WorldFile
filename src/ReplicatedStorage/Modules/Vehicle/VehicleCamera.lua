--[=[
DrivingCamera.luau

A camera module for vehicle driving in Roblox.
Features to implement:
- Camera follows the vehicle smoothly.
- When going backwards, camera does not reset or snap to a new position.
- Camera shake effect when accelerating, colliding, or driving on rough terrain.
- Adjustable camera distance and angle.
- Optionally, allow player to rotate camera around vehicle with mouse.
- Smooth transitions between camera states (e.g., entering/exiting vehicle).
- Add more features as needed for a polished driving experience.

-- Example usage:
-- local DrivingCamera = require(path.to.DrivingCamera)
-- DrivingCamera:AttachToVehicle(vehicle)
-- DrivingCamera:Detach()
]=]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local _TweenService = game:GetService("TweenService")

local VehicleCamera = {}
VehicleCamera.__index = VehicleCamera

local currentCamera = workspace.CurrentCamera
local player = Players.LocalPlayer

local attachedVehicle = nil
local baseCameraOffset = Vector3.new(0, 8, 20)
local _cameraOffset = baseCameraOffset
local cameraTargetOffset = Vector3.new(0, 2, 0)
local cameraSmoothingFactor = 7
local isReversing = false
local cameraCollisionBuffer = 0.5

-- Zooming Variables
local currentZoomMultiplier = 1.0
local minZoomMultiplier = 0.5
local maxZoomMultiplier = 5.0
local zoomSensitivity = 0.1

-- Orbiting Variables
local isOrbiting = false
local orbitYaw = 0
local orbitPitch = 0
local orbitSensitivity = 0.005
local orbitReturnSmoothing = 5

-- Camera Shake Variables
local shakeIntensity = 0
local shakeFrequency = 5 -- Reduced from 10 for smoother shake
local shakeAmplitude = 0.25 -- Reduced from 0.5 for less dramatic shake
local shakeDampening = 8 -- Increased from 5 for faster shake recovery
local shakeSeed = Random.new()

-- Collision Raycast Variables
local _lastDownHitDistance = nil
local _lastForwardHitTime = 0
local _forwardHitCooldown = 0.2
local _downRayLength = 5
local _forwardRayLength = 3
local _collisionShakeMultiplier = 1.5

local connection = nil
local inputConnections = {}

-- Function to handle camera shake
local function applyCameraShake(dt)
	if shakeIntensity > 0 then
		local shakeOffsetX = math.noise(shakeSeed:NextNumber() * shakeFrequency, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity
		local shakeOffsetY = math.noise(shakeSeed:NextNumber() * shakeFrequency * 1.1, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity
		local shakeOffsetZ = math.noise(shakeSeed:NextNumber() * shakeFrequency * 1.2, RunService.Stepped:Wait()) * shakeAmplitude * shakeIntensity

		local shakeCFrame = CFrame.new(shakeOffsetX, shakeOffsetY, shakeOffsetZ)
		currentCamera.CFrame = currentCamera.CFrame * shakeCFrame

		-- Dampen shake over time
		shakeIntensity = math.max(0, shakeIntensity - shakeDampening * dt)
	end
end

-- Function to trigger camera shake
function VehicleCamera:TriggerShake(intensity) -- Renamed from DrivingCamera
	shakeIntensity = math.max(shakeIntensity, intensity) -- Don't override if a stronger shake is active
end

-- Move updateCamera function definition before it's used in AttachToVehicle
local function updateCamera(dt)
    if not attachedVehicle then return end
    local chassis = attachedVehicle:FindFirstChild("Chassis")
    if not chassis then
        warn("VehicleCamera: Cannot update camera, vehicle has no Chassis!")
        return
    end

    -- Update camera based on chassis
    local vehicleCF = chassis.CFrame
    local vehicleVel = chassis.AssemblyLinearVelocity
    local speed = vehicleVel.Magnitude

    -- Determine if reversing
    local forwardVector = vehicleCF.LookVector
    local velocityDirection = vehicleVel.Magnitude > 0.1 and vehicleVel.Unit or Vector3.zero
    local dotProduct = forwardVector:Dot(velocityDirection)
    isReversing = dotProduct < -0.1 -- Threshold to consider it reversing

    -- Smoothly return orbit angles if not orbiting
    if not isOrbiting then
        local orbitReturnAlpha = 1 - math.exp(-orbitReturnSmoothing * dt)
        orbitYaw = orbitYaw * (1 - orbitReturnAlpha)
        orbitPitch = orbitPitch * (1 - orbitReturnAlpha)

        if math.abs(orbitYaw) < 0.001 then
            orbitYaw = 0
        end

        if math.abs(orbitPitch) < 0.001 then
            orbitPitch = 0
        end
    end

    -- Calculate the base offset considering zoom
    local zoomedOffset = Vector3.new(baseCameraOffset.X, baseCameraOffset.Y, baseCameraOffset.Z * currentZoomMultiplier)

    -- Apply orbit rotation
    local orbitRotation = CFrame.Angles(0, orbitYaw, 0) * CFrame.Angles(orbitPitch, 0, 0)
    local rotatedOffset = orbitRotation * zoomedOffset

    -- Adjust offset based on reversing state (apply AFTER orbit/zoom)
    local actualOffset = rotatedOffset
    if isReversing then
        actualOffset = Vector3.new(rotatedOffset.X, rotatedOffset.Y, -rotatedOffset.Z)
    end

    local idealPosition = vehicleCF * (actualOffset + cameraTargetOffset)
    local lookAtPosition = vehicleCF * cameraTargetOffset

    -- Raycast to prevent clipping
    local rayOrigin = lookAtPosition
    local rayDirection = idealPosition - rayOrigin
    local rayDistance = rayDirection.Magnitude
    local finalPosition = idealPosition -- Start with the ideal position

    if rayDistance > 0.1 then -- Only cast if there's a significant distance
        rayDirection = rayDirection.Unit
        local clipRayParams = RaycastParams.new()
        clipRayParams.FilterDescendantsInstances = {attachedVehicle, player.Character or Instance.new("Model")}
        clipRayParams.FilterType = Enum.RaycastFilterType.Exclude
        local clipRaycastResult = workspace:Raycast(rayOrigin, rayDirection * rayDistance, clipRayParams)

        if clipRaycastResult then
            -- Hit something, move camera closer
            finalPosition = clipRaycastResult.Position - rayDirection * cameraCollisionBuffer
        end
    end

    -- Smoothly interpolate camera position using frame-rate independent exponential smoothing
    local currentCFrame = currentCamera.CFrame
    local targetCFrame = CFrame.lookAt(finalPosition, lookAtPosition)
    local alpha = 1 - math.exp(-cameraSmoothingFactor * dt)
    currentCamera.CFrame = currentCFrame:Lerp(targetCFrame, alpha)

    -- Camera shake based on collisions and speed
    local shakeTriggerIntensity = 0

    -- Speed-based shake (clamped to be less intense)
    if speed > 50 then
        shakeTriggerIntensity = math.clamp((speed - 50) / 800, 0, 0.25) -- Further reduced maximum shake and made it more gradual
    end

    if shakeTriggerIntensity > 0 then
        VehicleCamera:TriggerShake(shakeTriggerIntensity)
    end

    -- Apply camera shake
    applyCameraShake(dt)
end

-- Input Handlers
local function handleMouseWheel(inputObject)
	local delta = inputObject.Position.Z -- Z indicates scroll wheel delta
	currentZoomMultiplier = math.clamp(currentZoomMultiplier - delta * zoomSensitivity, minZoomMultiplier, maxZoomMultiplier)
end

local function handleInputBegan(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
		isOrbiting = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local function handleInputEnded(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if inputObject.UserInputType == Enum.UserInputType.MouseButton2 then
		isOrbiting = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function handleInputChanged(inputObject, gameProcessedEvent)
	if gameProcessedEvent then return end
	if isOrbiting and inputObject.UserInputType == Enum.UserInputType.MouseMovement then
		orbitYaw = orbitYaw - inputObject.Delta.X * orbitSensitivity
		orbitPitch = math.clamp(orbitPitch - inputObject.Delta.Y * orbitSensitivity, -math.pi/4, math.pi/4) -- Clamp pitch
	end
end

-- Public methods
function VehicleCamera:AttachToVehicle(vehicle) -- Renamed from DrivingCamera
	if not vehicle then return end
	if not vehicle:FindFirstChild("Chassis") then
		warn("VehicleCamera: Cannot attach to vehicle without a Chassis:", vehicle.Name)
		return
	end
	attachedVehicle = vehicle
	if not attachedVehicle.PrimaryPart then
		warn("VehicleCamera: Cannot attach to vehicle without a PrimaryPart:", vehicle.Name) -- Renamed from DrivingCamera
		attachedVehicle = nil
		return
	end

	currentCamera.CameraType = Enum.CameraType.Scriptable

	-- Connect to RenderStepped for smooth camera updates
	-- Use BindToRenderStep for better control over priority if needed
	connection = RunService.RenderStepped:Connect(updateCamera)

	-- Reset zoom and orbit
	currentZoomMultiplier = 1.0
	orbitYaw = 0
	orbitPitch = 0
	isOrbiting = false

	-- Connect Input Listeners
	inputConnections.MouseWheelForward = UserInputService.InputChanged:Connect(function(inputObject, gameProcessedEvent)
		if not gameProcessedEvent and inputObject.UserInputType == Enum.UserInputType.MouseWheel then
			handleMouseWheel(inputObject)
		end
	end)
	inputConnections.InputBegan = UserInputService.InputBegan:Connect(handleInputBegan)
	inputConnections.InputEnded = UserInputService.InputEnded:Connect(handleInputEnded)
	inputConnections.InputChanged = UserInputService.InputChanged:Connect(handleInputChanged)

	_lastDownHitDistance = nil -- Reset collision state on attach
	_lastForwardHitTime = 0
	print("VehicleCamera attached to:", vehicle.Name) -- Renamed from DrivingCamera
end

function VehicleCamera:Detach()
    if connection then
        connection:Disconnect()
        connection = nil
    end
    attachedVehicle = nil
    currentCamera.CameraType = Enum.CameraType.Custom
    currentCamera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid") or nil

    -- Fix connection shadowing by renaming the loop variable
    for _, inputConnection in pairs(inputConnections) do
        inputConnection:Disconnect()
    end
    inputConnections = {}

    if isOrbiting then
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        isOrbiting = false
    end

    _lastDownHitDistance = nil
    _lastForwardHitTime = 0
    print("VehicleCamera detached")
end

-- Placeholder methods for settings
function VehicleCamera:SetOffset(newOffset: Vector3) -- Renamed from DrivingCamera
	baseCameraOffset = newOffset
end

function VehicleCamera:SetSmoothingFactor(newFactor: number) -- Renamed from DrivingCamera
	cameraSmoothingFactor = newFactor
end

-- REMOVED EnableMouseControl function as it's replaced by RMB orbiting
-- function VehicleCamera:EnableMouseControl(enabled: boolean)
-- 	...
-- end

return VehicleCamera -- Renamed from DrivingCamera