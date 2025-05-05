--[=[
VehicleEffects.luau

A module for vehicle effects in Roblox.
Features to implement:
- Ground/gravel particle effects when driving on different surfaces.
- Slipping/skidding effects (e.g., tire marks, sound, particles).
- Burnout effects (smoke, sound, tire marks).
- Optionally, sparks or debris when colliding or scraping.
- Modular design to allow easy addition of new effects.
- Efficiently handle effect spawning and cleanup.
- Add more features as needed for immersive vehicle feedback.

-- Example usage:
-- local VehicleEffects = require(path.to.VehicleEffects)
-- VehicleEffects:PlayGravelEffect(vehicle)
-- VehicleEffects:PlaySlipEffect(vehicle)
]=]

local _RunService = game:GetService("RunService")  -- Prefix with _ since unused
local Debris = game:GetService("Debris")

local VehicleEffects = {}
VehicleEffects.__index = VehicleEffects

local lastSoundTime = {} -- { [vehicleModel] = { [soundType] = timestamp } }
local activeSounds = {} -- { [vehicleModel] = { [soundType] = Sound } }

local SOUND_COOLDOWNS = {
    SlipSound = 0.5, -- Increased from 0.1
    BurnoutSound = 0.75, -- Increased from 0.2
    SkidSound = 0.5 -- Increased from 0.15
}

function VehicleEffects.new()
    local self = setmetatable({}, VehicleEffects)
    self.activeSounds = {}
    return self
end

local function stopExistingSound(vehicleModel, soundType)
    if activeSounds[vehicleModel] and activeSounds[vehicleModel][soundType] then
        activeSounds[vehicleModel][soundType]:Stop()
        activeSounds[vehicleModel][soundType]:Destroy()
        activeSounds[vehicleModel][soundType] = nil
    end
end

-- Configuration (using Instance.new properties)
local effectProperties = {
	GravelParticles = {
		Texture = "rbxassetid://18406763", -- Example: Roblox smoke texture
		Color = ColorSequence.new(Color3.fromRGB(139, 119, 101)), -- Brownish color
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1),
		Rate = 1,
		Speed = NumberRange.new(5, 10),
		SpreadAngle = Vector2.new(45, 45),
		Acceleration = Vector3.new(0, -10, 0), -- Gravity
		EmissionDirection = Enum.NormalId.Top,
	},
	SlipSound = { -- Updated properties
		SoundId = "rbxassetid://14593442958",
		Name = "Tire Skid",
		Volume = 1,
		RollOffMaxDistance = 110,
		RollOffMinDistance = 22,
		-- RollOffMode defaults to InverseTapered which is fine
	},
	SlipSoundReverb = { -- Added Reverb properties
		Enabled = true,
		Density = 0.8,
		DecayTime = 0.4,
		-- Other reverb properties can be added here if needed
	},
	BurnoutSmoke = { -- Updated properties from user example
		Texture = "rbxassetid://8581391856",
		Color = ColorSequence.new(Color3.fromRGB(77, 77, 77)), -- Approximated from 0.3, 0.3, 0.3
		Size = NumberSequence.new(2.00),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0.00, 0.00, 0.00), NumberSequenceKeypoint.new(0.40, 1.00, 0.00), NumberSequenceKeypoint.new(1.00, 0.99, 0.00)}),
		Lifetime = NumberRange.new(10.00, 20.00),
		Rate = 25,
		Speed = NumberRange.new(15.00),
		Drag = 3,
		SpreadAngle = Vector2.new(10.00, 10.00),
		Rotation = NumberRange.new(-50.00, 50.00),
		RotSpeed = NumberRange.new(-30.00, 30.00),
		LightEmission = 0.8,
		LightInfluence = 1,
		EmissionDirection = Enum.NormalId.Front,
		VelocityInheritance = 1,
		-- Enabled = false, -- Will be enabled on creation
		-- Parent = ..., -- Handled in createEffect
		-- Note: Decals inside ParticleEmitter are not standard, ignoring HQ_Smoke_Particle and particle_smoke
	},
	BurnoutSound = { -- Added Burnout Sound
		SoundId = "rbxassetid://14593442958", -- Replace with actual asset ID
		Volume = 0.8,
		Looped = true,
		RollOffMaxDistance = 120,
		RollOffMinDistance = 15,
		RollOffMode = Enum.RollOffMode.Inverse,
	},
	CollisionSparks = { -- Added Collision Sparks
		Texture = "rbxassetid://637274943", -- Example: Roblox Sparkle texture
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(255, 150, 50)),
		LightEmission = 0.5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(1, 0.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.1, 0.3),
		Rate = 0, -- Emit manually
		Speed = NumberRange.new(15, 25),
		SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -20, 0), -- Sparks fall
	},
	SkidParticles = { -- Added Skid Particles
		Texture = "rbxassetid://18406763", -- Example: Roblox smoke texture (use something wispy)
		Color = ColorSequence.new(Color3.fromRGB(100, 100, 100), Color3.fromRGB(50, 50, 50)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 0.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.6),
		Rate = 0, -- Emit manually
		Speed = NumberRange.new(8, 15),
		SpreadAngle = Vector2.new(10, 10),
		Acceleration = Vector3.new(0, 1, 0), -- Slight upward drift
		Drag = 1,
		LockedToPart = false,
		-- EmissionDirection will be set based on skid direction
	},
	TireMarkTrail = { -- Added properties from user example
		Name = "TireTrack",
		Texture = "rbxassetid://16458623812",
		Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
		Transparency = NumberSequence.new(0.60),
		WidthScale = NumberSequence.new(1.80),
		Lifetime = 5,
		MinLength = 0.08,
		TextureMode = Enum.TextureMode.Wrap,
		TextureLength = 2.5,
		LightInfluence = 1,
		-- Enabled = false, -- Will be handled by controller
		-- Attachment0 = ..., -- Will be handled by controller
		-- Attachment1 = ..., -- Will be handled by controller
		-- Parent = ..., -- Will be handled by controller
	},
	TireMarkDecal = {
		Texture = "rbxassetid://16458623812",  -- Use tire mark texture
		Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
		Transparency = 0.6
	},
}

-- Move getWheelPart to top and use it consistently
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

function VehicleEffects:createEffect(effectType, parent, positionOrAttachment0, rotationOrNormalOrDirectionOrAttachment1, duration)
    if effectType:find("Sound") and parent then
        local vehicleModel = parent:FindFirstAncestorOfClass("Model")
        local chassis = vehicleModel and vehicleModel:FindFirstChild("Chassis")
        if chassis then
            -- Initialize tracking tables if needed
            lastSoundTime[vehicleModel] = lastSoundTime[vehicleModel] or {}
            activeSounds[vehicleModel] = activeSounds[vehicleModel] or {}

            -- Check cooldown
            local now = os.clock()
            if lastSoundTime[vehicleModel][effectType] and
               now - lastSoundTime[vehicleModel][effectType] < (SOUND_COOLDOWNS[effectType] or 0.5) then
                return nil -- Still in cooldown
            end

            -- Stop existing sound of same type
            stopExistingSound(vehicleModel, effectType)

            lastSoundTime[vehicleModel][effectType] = now

            -- Create new sound
            if effectType == "SlipSound" then
                local props = effectProperties.SlipSound
                local sound = Instance.new("Sound")
                sound.Parent = chassis
                for propName, propValue in pairs(props) do
                    sound[propName] = propValue
                end

                -- Add Reverb Effect
                local reverbProps = effectProperties.SlipSoundReverb
                local reverb = Instance.new("ReverbSoundEffect")
                reverb.Parent = sound
                for propName, propValue in pairs(reverbProps) do
                    reverb[propName] = propValue
                end

                sound:Play()
                activeSounds[vehicleModel][effectType] = sound
                return sound
            end
            -- Handle other sound types similarly...
        end
    end

	if effectType == "Gravel" then
		local props = effectProperties.GravelParticles
		local attachment = Instance.new("Attachment")
		attachment.Parent = parent
		attachment.WorldPosition = positionOrAttachment0
		local emitter = Instance.new("ParticleEmitter")
		emitter.Parent = attachment
		for propName, propValue in pairs(props) do
			emitter[propName] = propValue
		end
		emitter.Enabled = true
		emitter:Emit(15) -- Emit a burst
		Debris:AddItem(attachment, duration or props.Lifetime.Max + 0.1)
		return emitter

	elseif effectType == "BurnoutSmoke" then
		local props = effectProperties.BurnoutSmoke
		local attachment = Instance.new("Attachment")
		attachment.Parent = parent
		attachment.WorldPosition = positionOrAttachment0 -- Use position here
		local emitter = Instance.new("ParticleEmitter")
		emitter.Parent = attachment
		for propName, propValue in pairs(props) do
			emitter[propName] = propValue
		end
		emitter.Enabled = true -- Keep enabled for continuous smoke
		Debris:AddItem(attachment, duration or props.Lifetime.Max + 1) -- Use emitter lifetime for cleanup
		return emitter

	elseif effectType == "BurnoutSound" then
		local props = effectProperties.BurnoutSound
		local sound = Instance.new("Sound")
		sound.Parent = parent -- Parent directly
		for propName, propValue in pairs(props) do
			sound[propName] = propValue
		end
		-- sound.WorldPosition = position -- Removed
		sound:Play()
		-- For looped sounds, manual stopping is required, Debris is not ideal here.
		-- We return the handle so StopEffect can be called.
		return sound

	elseif effectType == "CollisionSparks" then
		local props = effectProperties.CollisionSparks
		local attachment = Instance.new("Attachment")
		attachment.Parent = workspace.Terrain -- Set parent separately
		attachment.WorldPosition = positionOrAttachment0
		attachment.WorldAxis = rotationOrNormalOrDirectionOrAttachment1 or Vector3.yAxis

		local emitter = Instance.new("ParticleEmitter")
		emitter.Parent = attachment -- Set parent separately
		for propName, propValue in pairs(props) do
			emitter[propName] = propValue
		end
		emitter.Enabled = true
		emitter:Emit(math.random(5, 15))
		Debris:AddItem(attachment, duration or props.Lifetime.Max + 0.2)
		return emitter

	elseif effectType == "SkidParticles" then
		local props = effectProperties.SkidParticles
		local attachment = Instance.new("Attachment")
		attachment.Parent = workspace.Terrain -- Set parent separately
		attachment.WorldPosition = positionOrAttachment0

		local emitter = Instance.new("ParticleEmitter")
		emitter.Parent = attachment -- Set parent separately
		for propName, propValue in pairs(props) do
			emitter[propName] = propValue
		end
		emitter.EmissionDirection = Enum.NormalId.Front
		attachment.CFrame = CFrame.lookAt(positionOrAttachment0, positionOrAttachment0 + rotationOrNormalOrDirectionOrAttachment1)

		emitter.Enabled = true
		emitter:Emit(math.random(3, 8))
		Debris:AddItem(attachment, duration or props.Lifetime.Max + 0.2)
		return emitter

	elseif effectType == "TireMarkTrail" then
		local props = effectProperties.TireMarkTrail
		local trail = Instance.new("Trail")
		trail.Parent = parent -- Set parent separately
		for propName, propValue in pairs(props) do
			trail[propName] = propValue
		end
		trail.Attachment0 = positionOrAttachment0
		trail.Attachment1 = rotationOrNormalOrDirectionOrAttachment1
		trail.Enabled = false
		return trail
	end
	return nil
end

-- Table to track active slip sounds per vehicle/wheel
local activeSlipSounds = {} -- [vehicle][wheelName] = Sound

function VehicleEffects:PlaySlipSound(vehicle, wheelPart)
    if not vehicle or not wheelPart then return end
    local wheelName = wheelPart.Name
    activeSlipSounds[vehicle] = activeSlipSounds[vehicle] or {}
    -- If already playing, do nothing
    if activeSlipSounds[vehicle][wheelName] and activeSlipSounds[vehicle][wheelName].IsPlaying then return end
    -- Create and play looped slip sound
    local props = effectProperties.SlipSound
    local sound = Instance.new("Sound")
    for propName, propValue in pairs(props) do
        sound[propName] = propValue
    end
    sound.Looped = true
    sound.Parent = wheelPart
    sound:Play()
    activeSlipSounds[vehicle][wheelName] = sound
end

function VehicleEffects:StopSlipSound(vehicle, wheelPart)
    if not vehicle or not wheelPart then return end
    local wheelName = wheelPart.Name
    if activeSlipSounds[vehicle] and activeSlipSounds[vehicle][wheelName] then
        local sound = activeSlipSounds[vehicle][wheelName]
        if sound.IsPlaying then
            sound:Stop()
        end
        sound:Destroy()
        activeSlipSounds[vehicle][wheelName] = nil
    end
end

-- Public methods
function VehicleEffects:PlayGravelEffect(vehicle, wheelPart)
    if not vehicle or not wheelPart then return end
    local mainPart = getWheelPart(wheelPart)
    if not mainPart then return end

    -- Determine position based on wheel contact (approximate)
    local effectPosition = mainPart.Position - Vector3.new(0, mainPart.Size.Y / 2, 0)
    self:createEffect("Gravel", mainPart, effectPosition, nil, 1) -- Pass primary part for parenting if needed
end

function VehicleEffects:PlaySlipEffect(vehicle, wheelPart)
    if not vehicle or not wheelPart then return end
    local mainPart = getWheelPart(wheelPart)
    if not mainPart then return end

    -- Play sound attached to vehicle root
    --self:createEffect("SlipSound", vehicle.PrimaryPart, primary.Position) -- Position is now unused by sound creation but kept for potential future use (e.g. effects needing position)

    -- TODO: Add tire mark decal logic here if an asset ID is available
    -- local raycastResult = workspace:Raycast(primary.Position, Vector3.new(0, -primary.Size.Y, 0))
    -- if raycastResult then
    -- 	 createEffect("TireMark", workspace.Terrain, raycastResult.Position, primary.Orientation.Y, 15)
    -- end
end

function VehicleEffects:PlayBurnoutEffect(vehicle, wheelPart)
    if not vehicle or not wheelPart then return end
    local mainPart = getWheelPart(wheelPart)
    if not mainPart then return end

    -- Position effects at ground contact point
    local effectPosition = mainPart.Position - Vector3.new(0, mainPart.Size.Y / 2, 0)
    -- Create continuous smoke attached to the wheel's primary part
    local smokeEmitter = self:createEffect("BurnoutSmoke", mainPart, effectPosition, nil, 5)
    -- Play burnout sound attached to vehicle root
    local burnoutSound = self:createEffect("BurnoutSound", vehicle:FindFirstChild("Chassis"), effectPosition)

    return {smoke = smokeEmitter, sound = burnoutSound}
end

-- Added PlayCollisionEffect
function VehicleEffects:PlayCollisionEffect(vehicle, contactPoint, contactNormal, impactMagnitude)
    if not vehicle then return end
    local chassis = vehicle:FindFirstChild("Chassis")
    if not chassis then return end

    -- Play sparks at the contact point, oriented by the contact normal
	local sparkCount = math.clamp(math.floor(impactMagnitude / 5), 1, 10) -- More sparks for harder impacts
	local sparkEmitter = self:createEffect("CollisionSparks", workspace.Terrain, contactPoint, contactNormal, 0.5)
	if sparkEmitter then
		sparkEmitter:Emit(sparkCount)
	end

	-- TODO: Play collision sound based on impactMagnitude
	-- TODO: Spawn debris based on impactMagnitude and materials involved
end

-- Updated PlaySkidEffect to prepare for Trail (will be fully implemented in controller)
function VehicleEffects:PlaySkidEffect(vehicle, wheelPart, skidDirection)
    if not vehicle or not wheelPart then return end
    local mainPart = getWheelPart(wheelPart)
    if not mainPart then return end

    -- Position effects at ground contact point
    local effectPosition = mainPart.Position - Vector3.new(0, mainPart.Size.Y / 2, 0)
    -- Create skid particles at ground level
    self:createEffect("SkidParticles", workspace.Terrain, effectPosition, skidDirection, 0.6)

    -- Tire Mark Trail creation/management will happen in the controller script
    -- It needs to create/update attachments based on wheel position.
end

function VehicleEffects:StopEffect(effectInstance)
	if not effectInstance then return end

	if effectInstance:IsA("ParticleEmitter") then
		effectInstance.Enabled = false
		-- Parent attachment will be cleaned up by Debris
	elseif effectInstance:IsA("Sound") then
		effectInstance:Stop()
		-- Sound will be cleaned up by Debris
	elseif effectInstance:IsA("Decal") then
		-- Decals rely on Debris for cleanup, no explicit stop needed
		return
	end
end

-- Added StopBurnoutEffect to handle multiple parts
function VehicleEffects:StopBurnoutEffect(effectHandles)
	if not effectHandles then return end
	if effectHandles.smoke then
        self:StopEffect(effectHandles.smoke)
    end
	if effectHandles.sound then
        self:StopEffect(effectHandles.sound)
    end
	if effectHandles.tireMark then
        self:StopEffect(effectHandles.tireMark)
    end
end

-- TODO: Add methods for collision effects (sparks, debris)

local activeSkidSounds = {} -- [vehicle][wheelName] = Sound

function VehicleEffects:GetOrCreateSkidSound(vehicle, wheelPart)
    if not vehicle or not wheelPart then return nil end
    local mainPart = getWheelPart(wheelPart)
    if not mainPart then return nil end

    local wheelName = wheelPart.Name
    activeSkidSounds[vehicle] = activeSkidSounds[vehicle] or {}
    if activeSkidSounds[vehicle][wheelName] then
        return activeSkidSounds[vehicle][wheelName]
    end

    local props = effectProperties.SlipSound
    local sound = Instance.new("Sound")
    for propName, propValue in pairs(props) do
        sound[propName] = propValue
    end
    sound.Looped = true
    sound.Parent = mainPart
    activeSkidSounds[vehicle][wheelName] = sound
    return sound
end

function VehicleEffects:PlaySkidSound(vehicle, wheelPart)
    local sound = self:GetOrCreateSkidSound(vehicle, wheelPart)
    if sound and not sound.IsPlaying then
        sound:Play()
    end
end

function VehicleEffects:StopSkidSound(vehicle, wheelPart)
    local sound = self:GetOrCreateSkidSound(vehicle, wheelPart)
    if sound and sound.IsPlaying then
        sound:Stop()
    end
end

function VehicleEffects:CleanupSkidSounds(vehicle)
    if activeSkidSounds[vehicle] then
        for _, sound in pairs(activeSkidSounds[vehicle]) do
            if sound then
                sound:Stop()
                sound:Destroy()
            end
        end
        activeSkidSounds[vehicle] = nil
    end
end

return VehicleEffects