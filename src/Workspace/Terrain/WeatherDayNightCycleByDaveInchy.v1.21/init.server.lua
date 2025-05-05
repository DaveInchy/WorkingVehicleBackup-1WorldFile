--[[

 Author: DaveInchy on Github <simpli-studios@gmail.com>
 Group Ownership: Simpli Studios
 Date: 8/21/2024
 
 Version: build-21.08.2K24

]]--
local tweenService = game:GetService("TweenService");

local promise = require(script.Promise);
local useState = require(script.Functions.useState);

local weather = useState({});
local season = useState({});
local daytime = useState({});

local Init = require(script.Init);
Init()

local lighting = game.Lighting;
local atmosphere = game.Lighting.Atmosphere;
local clouds = game.Workspace.Terrain.Clouds;
local effects = game.Workspace.Terrain;

local presets = require(script.Presets);

local weatherState = {
	["sun"] = {
		length = 180,
		clouds = {
			properties = {
				Cover = 0.65,
				Density = 0.5,
				Color = Color3.fromHex(`#eeeeee`),
				Enabled = true,
			}
		},
		effects = {
			Rain = false,
			Snow = false,
			Storm = false,
		},
		atmosphere = {
			properties = {
				Density = 0.2,
				Offset = 0.1,
				Color = Color3.fromRGB(199,199,199),
				Decay = Color3.fromRGB(106,112,124),
				Glare = 0,
				Haze = 0,
			}
		}
	},
	["clear"] = {
		length = 120,
		clouds = {
			properties = {
				Cover = 0,
				Density = 0.5,
				Color = Color3.fromHex(`#eeeeee`),
				Enabled = false,
			}
		},
		effects = {
			Rain = false,
			Snow = false,
			Storm = false,
		},
		atmosphere = {
			properties = {
				Density = 0.05,
				Offset = 0.1,
				Color = Color3.fromRGB(199,199,199),
				Decay = Color3.fromRGB(106,112,124),
				Glare = 0,
				Haze = 0,
			}
		}
	},
	["storm"] = {
		length = 60,
		clouds = {
			properties = {
				Cover = 0.9,
				Density = 0.8,
				Color = Color3.fromHex(`#333333`),
				Enabled = true,
			}
		},
		effects = {
			Rain = true,
			Snow = false,
			Storm = true,
		},
		atmosphere = {
			properties = {
				Density = 0.5,
				Offset = 0.25,
				Color = Color3.fromRGB(91, 91, 91),
				Decay = Color3.fromRGB(54, 57, 63),
				Glare = 0.2,
				Haze = 0.2,
			}
		}
	},
	["rain"] = {
		length = 90,
		clouds = {
			properties = {
				Cover = 0.75,
				Density = 0.5,
				Color = Color3.fromHex(`#3e3e3e`),
				Enabled = true,
			}
		},
		effects = {
			Rain = true,
			Snow = false,
			Storm = false,
		},
		atmosphere = {
			properties = {
				Density = 0.1,
				Offset = 0.25,
				Color = Color3.fromRGB(91, 91, 91),
				Decay = Color3.fromRGB(54, 57, 63),
				Glare = 0,
				Haze = 0,
			}
		}
	},
	["fog"] = {
		length = 60,
		clouds = {
			properties = {
				Cover = 0.8,
				Density = 0.5,
				Color = Color3.fromHex(`#eeeeee`),
				Enabled = true,
			}
		},
		effects = {
			Rain = false,
			Snow = false,
			Storm = false,
		},
		atmosphere = {
			properties = {
				Density = 0.8,
				Offset = 0.4,
				Color = Color3.fromRGB(199,199,199),
				Decay = Color3.fromRGB(106,112,124),
				Glare = 0.2,
				Haze = 0.2,
			}
		}
	},
	["snow"] = {
		length = 120,
		clouds = {
			properties = {
				Cover = 0.75,
				Density = 0.5,
				Color = Color3.fromHex(`#eeeeee`),
				Enabled = true,
			}
		},
		effects = {
			Rain = false,
			Snow = true,
			Storm = false,
		},
		atmosphere = {
			properties = {
				Density = 0.4,
				Offset = 0.4,
				Color = Color3.fromRGB(199,199,199),
				Decay = Color3.fromRGB(106,112,124),
				Glare = 0.2,
				Haze = 0.2,
			}
		}
	},
	["snowstorm"] = {
		length = 30,
		clouds = {
			properties = {
				Cover = 0.9,
				Density = 0.8,
				Color = Color3.fromHex(`#333333`),
				Enabled = true,
			}
		},
		effects = {
			Rain = false,
			Snow = true,
			Storm = true,
		},
		atmosphere = {
			properties = {
				Density = 0.4,
				Offset = 0.4,
				Color = Color3.fromRGB(91, 91, 91),
				Decay = Color3.fromRGB(54, 57, 63),
				Glare = 0.2,
				Haze = 0.2,
			}
		}
	}
}

local seasonState = {
	[1] = { -- Summer
		length = 900,
		weather = {
			include = {
				"sun",
				"clear",
			}
		}

	},
	[2] = { -- Autumn
		length = 900,
		weather = {
			include = {
				"rain",
				"sun",
				"storm",
				"clear",
			}
		}
	},
	[3] = { -- Winter
		length = 900,
		weather = {
			include = {
				"snowstorm",
				"snow",
				"fog",
				"clear",
			}
		}
	},
	[4] = { -- Spring
		length = 900,
		weather = {
			include = {
				"snow",
				"rain",
				"sun",
				"fog",
				"clear",
			}
		}
	}
}

local daytimeState = {
	[1] = {
		length = 30,
		preset = "Dawn",
		lighting = { 
			properties = {
				Brightness = 1,
				ClockTime = 8.00,
				Ambient = Color3.new(0.8, 0.8, 0.8),
			},
		},
	},
	[2] = {
		length = 60,
		preset = "Dawn",
		lighting = { 
			properties = {
				Brightness = 1,
				ClockTime = 10.00,
				Ambient = Color3.new(1, 1, 1),
			},
		},
	},
	[3] = {
		length = 300,
		preset = "Midday",
		lighting = { 
			properties = {
				Brightness = 1,
				ClockTime = 12.00,
				Ambient = Color3.new(1, 1, 1),
			},
		},
	},
	[4] = {
		length = 240,
		preset = "Midday",
		lighting = { 
			properties = {
				Brightness = 1,
				ClockTime = 16.00,
				Ambient = Color3.new(1, 1, 1),
			},
		},
	},
	[5] = {
		length = 120,
		preset = "Dusk",
		lighting = { 
			properties = {
				Brightness = 1,
				ClockTime = 18.25,
				Ambient = Color3.new(0.9, 0.9, 0.9),
			},
		},
	},
	[6] = {
		length = 60,
		preset = "Dusk",
		lighting = { 
			Brightness = 0.8,
			properties = {
				ClockTime = 20.00,
				Ambient = Color3.new(0.7, 0.7, 0.7),
			},
		},
	},
	[7] = {
		length = 30,
		preset = "Night",
		lighting = { 
			Brightness = 0.6,
			properties = {
				ClockTime = 23.99,
				Ambient = Color3.new(0.6, 0.6, 0.6),
			},
		},
	},
}

local function enableEffect(name: string, enabled: boolean)
	local effects = game.Workspace.Terrain:GetDescendants();
	for iii, v3 in ipairs(effects) do
		if v3:IsA("ParticleEmitter") and v3.Name == name then
			v3.Enabled = enabled;
			print(`{v3.Name} => {enabled}`)
		end
	end
end

local function isIncluded(arr: {[number]: string}, val: string): boolean
	for i, v in ipairs(arr) do
		if v == val then
			return true;
		end
	end
	return false;
end

local tweenSpeed = script:GetAttribute("TweenSpeed")
local function tweenAtmosphere(properties: {[string]: any})
	return promise.new(function(res, rej, cancel)
		local tweenInfo = TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		local tween = tweenService:Create(atmosphere, tweenInfo, properties)
		tween:Play()
		res()
	end)
end

local function tweenClouds(properties: {[string]: any})
	return promise.new(function(res, rej, cancel)
		local tweenInfo = TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		local tween = tweenService:Create(clouds, tweenInfo, properties)
		tween:Play()
		res()
	end)
end

local function tweenLighting(properties: {[string]: any})
	return promise.new(function(res, rej, cancel)
		local tweenInfo = TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		local tween = tweenService:Create(lighting, tweenInfo, properties)
		tween:Play()
		res()
	end)
end

local SeasonLoop = function()
	local currentState = season.get();

	while true do

		for key, value in pairs(seasonState) do
			season.set(value);
			currentState = season.get();
			wait(value.length);
		end

		task.wait();
	end

end;

local WeatherLoop = function()
	local currentState = weather.get();

	while true do

		for key, value in pairs(weatherState) do
			local included = season.get().weather.include;

			if not isIncluded(included, key) then warn(`{key} wasn't included in current season, skip...`); continue; end;

			weather.set(value);
			currentState = weather.get();

			tweenClouds(currentState.clouds.properties):andThen(function(data)
				print(`[clouds] success tweening clouds...`)
				tweenAtmosphere(currentState.atmosphere.properties):andThen(function(data)
					print(`[atmosphere] success tweening atmosphere...`)
				end);
			end);

			for k, v in pairs(currentState.effects) do
				enableEffect(k, v);
			end

			task.wait(value.length);
		end

		task.wait();
	end

end;

local TimeOfDayLoop = function()
	local currentState = daytime.get();

	while true do

		for num, value in ipairs(daytimeState) do
			daytime.set(value);
			currentState = daytime.get();
			tweenLighting(currentState.lighting.properties):andThen(function(data)
				print(`[lighting] time of day set to #{num}`)
				presets.tweenLightingAsync(script.Configurations[currentState.preset], tweenSpeed, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut);
			end);
			task.wait(value.length);
		end

		game.Lighting.ClockTime = 0;

		task.wait();

	end
end;

local thread0 = coroutine.create(SeasonLoop);
local thread1 = coroutine.create(TimeOfDayLoop);
local thread2 = coroutine.create(WeatherLoop);

coroutine.resume(thread0);
coroutine.resume(thread1);
coroutine.resume(thread2);